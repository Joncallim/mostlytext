#!/usr/bin/env python3
"""Bind conservative Go runtime attribution to the immutable D2 publisher WASM.

Uses Go 1.24's runtime PC table and the WASM element table, including wasm-opt's
function reindexing. Does not execute WASM or attest a publisher rebuild.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import tarfile

WASM_SHA = '7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af'
GO_SHA = '4e29202c49573b953be7cc3500e1f8d9e66ddd12faa8cf0939a4951411e09a2a'
SYMBOLS = ('runtime.main', 'runtime.mallocgc', 'syscall/js.valueCall')


def digest(data):
    return hashlib.sha256(data).hexdigest()


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, count):
        if count < 0 or count > len(self.data) - self.pos:
            raise ValueError('truncated binary field')
        result = self.data[self.pos:self.pos + count]
        self.pos += count
        return result

    def byte(self):
        return self.take(1)[0]

    def uint(self):
        value = 0
        for shift in range(0, 35, 7):
            byte = self.byte()
            value |= (byte & 127) << shift
            if not byte & 128:
                if value > 0xffffffff:
                    raise ValueError('oversized integer')
                return value
        raise ValueError('unterminated integer')

    def string(self):
        return self.take(self.uint()).decode('utf-8')

    def offset_expression(self):
        if self.byte() != 0x41:
            raise ValueError('expected bounded i32.const offset')
        # This frozen publisher module uses nonnegative canonical offsets.
        start = self.pos
        value = self.uint()
        if self.data[self.pos - 1] & 64 or self.pos - start > 5 or self.byte() != 11:
            raise ValueError('invalid/nonpositive offset expression')
        return value

    def done(self):
        if self.pos != len(self.data):
            raise ValueError('unconsumed section bytes')


def inspect_wasm(data):
    module = Reader(data)
    if module.take(8) != b'\0asm\x01\0\0\0':
        raise ValueError('unexpected WASM header')
    sections = {}
    while module.pos < len(data):
        kind = module.byte()
        payload = module.take(module.uint())
        if kind:
            if kind in sections or kind > 12:
                raise ValueError('duplicate/unknown standard section')
            sections[kind] = payload
    if not {2, 3, 9, 10, 11}.issubset(sections):
        raise ValueError('missing required WASM section')
    imports = Reader(sections[2])
    imported = imports.uint()
    for _ in range(imported):
        imports.string()
        imports.string()
        if imports.byte() != 0:
            raise ValueError('unexpected non-function import')
        imports.uint()
    imports.done()
    functions = Reader(sections[3])
    defined = functions.uint()
    for _ in range(defined):
        functions.uint()
    functions.done()
    code = Reader(sections[10])
    if code.uint() != defined:
        raise ValueError('function/code counts differ')
    bodies = []
    for _ in range(defined):
        body = code.take(code.uint())
        if len(body) < 3 or body[-1] != 11:
            raise ValueError('empty/truncated defined code body')
        bodies.append(body)
    code.done()
    elements = Reader(sections[9])
    if elements.uint() != 1 or elements.uint() != 0:
        raise ValueError('unexpected element segment/table')
    table_start = elements.offset_expression()
    table = [elements.uint() for _ in range(elements.uint())]
    elements.done()
    if any(index < imported or index >= imported + defined for index in table):
        raise ValueError('element does not identify defined code')
    segments = Reader(sections[11])
    parts, end = [], 0
    segment_count = segments.uint()
    for _ in range(segment_count):
        if segments.uint() != 0:
            raise ValueError('unexpected passive/nonzero memory segment')
        address = segments.offset_expression()
        payload = segments.take(segments.uint())
        if address < end or address + len(payload) > 64 * 1024 * 1024:
            raise ValueError('overlapping/oversized data memory')
        end = address + len(payload)
        parts.append((address, payload))
    segments.done()
    memory = bytearray(end)
    for address, payload in parts:
        memory[address:address + len(payload)] = payload
    magic = b'\xf1\xff\xff\xff\0\0\x01\x08'
    if memory.count(magic) != 1 or b'go1.24.6\0' not in memory:
        raise ValueError('missing unique Go PC table/version')
    header = memory.index(magic)
    def unpack(fmt, address):
        if address < 0 or address + struct.calcsize(fmt) > len(memory):
            raise ValueError('PC table field outside initialized memory')
        return struct.unpack_from(fmt, memory, address)
    count, _, text_start, names, _, _, _, records = unpack('<8Q', header + 8)
    if not 0 < count <= defined:
        raise ValueError('invalid Go function count')
    found = {}
    for index in range(count):
        entry, offset = unpack('<II', header + records + index * 8)
        record_entry, name = unpack('<Ii', header + records + offset)
        if entry != record_entry or name < 0:
            raise ValueError('inconsistent Go function record')
        address = header + names + name
        if not 0 <= address < len(memory):
            raise ValueError('name outside initialized memory')
        terminator = memory.find(0, address, min(address + 4096, len(memory)))
        if terminator < 0:
            raise ValueError('unterminated function name')
        symbol = memory[address:terminator].decode('utf-8')
        if symbol not in SYMBOLS:
            continue
        slot = ((entry + text_start) >> 16) - table_start
        if symbol in found or not 0 <= slot < len(table):
            raise ValueError('duplicate/unmapped runtime function')
        function_index = table[slot]
        body = bodies[function_index - imported]
        found[symbol] = {'go_pc': entry + text_start, 'table_index': slot + table_start,
                         'wasm_function_index': function_index, 'code_bytes': len(body),
                         'code_sha256': digest(body)}
    if set(found) != set(SYMBOLS):
        raise ValueError('required Go functions lack defined code linkage')
    return {'imported_functions': imported, 'defined_functions': defined,
            'go_function_records': count, 'data_segments': segment_count,
            'initialized_memory_bytes': len(memory), 'runtime_functions': found}


def audit(wasm, go_archive, notice):
    binary, archive = wasm.read_bytes(), go_archive.read_bytes()
    if digest(binary) != WASM_SHA or digest(archive) != GO_SHA:
        raise ValueError('WASM/toolchain archive digest mismatch')
    with tarfile.open(go_archive, 'r:gz') as source:
        license_text = source.extractfile('go/LICENSE').read()
        version = source.extractfile('go/VERSION').read().splitlines()[0]
    if version != b'go1.24.6' or notice.read_bytes() != license_text:
        raise ValueError('toolchain version/full notice mismatch')
    return {'schema': 1, 'wasm_sha256': WASM_SHA, 'go_archive_sha256': GO_SHA,
            'go_version': version.decode(), 'notice_sha256': digest(license_text),
            'binary_structure': inspect_wasm(binary),
            'limits': 'Conservative root runtime attribution; not a publisher rebuild, exhaustive per-file rights audit or source-offer approval.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['wasm', 'go-archive', 'notice', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.wasm, args.go_archive, args.notice)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
