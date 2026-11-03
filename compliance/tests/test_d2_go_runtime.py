"""Binary structure and exact-input controls for conservative Go attribution."""
import io
import json
from pathlib import Path
import struct
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import audit_d2_go_runtime as subject


def uint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def section(kind, data):
    return bytes([kind]) + uint(len(data)) + data


def fixture(*, mapped=True, version=b'go1.24.6', record_entry=65536, code_count=3, repeated_memory=False):
    memory = bytearray(400)
    memory[8:8 + len(version)] = version
    memory[32:40] = b'\xf1\xff\xff\xff\0\0\x01\x08'
    struct.pack_into('<8Q', memory, 40, 3, 1, 0, 96, 0, 0, 0, 224)
    name_offset = 0
    for index, symbol in enumerate(subject.SYMBOLS):
        entry = (index + 1) << 16
        struct.pack_into('<II', memory, 256 + index * 8, entry, 24 + index * 8)
        struct.pack_into('<Ii', memory, 280 + index * 8, record_entry if index == 0 else entry, name_offset)
        name = symbol.encode() + b'\0'
        memory[128 + name_offset:128 + name_offset + len(name)] = name
        name_offset += len(name)
    parts = [section(2, b'\0'), section(3, b'\3\0\0\0')]
    # Start at table index 1. Reordered function indices model wasm-opt.
    parts.append(section(9, b'\1\0\x41' + uint(1 if mapped else 9) + b'\x0b\3\2\0\1'))
    body = b'\0\x41\0\x0b'
    parts.append(section(10, uint(code_count) + (uint(len(body)) + body) * code_count))
    data_segment = b'\0\x41\0\x0b' + uint(len(memory)) + memory
    parts.append(section(11, uint(2 if repeated_memory else 1) + data_segment * (2 if repeated_memory else 1)))
    return b'\0asm\1\0\0\0' + b''.join(parts)


class D2GoRuntimeTests(unittest.TestCase):
    def test_function_records_resolve_through_reordered_element_table_to_code(self):
        result = subject.inspect_wasm(fixture())
        self.assertEqual(result['runtime_functions']['runtime.main']['wasm_function_index'], 2)
        self.assertEqual(result['runtime_functions']['runtime.mallocgc']['wasm_function_index'], 0)
        self.assertEqual(result['runtime_functions']['runtime.main']['code_bytes'], 4)

    def test_names_without_valid_element_mapping_are_insufficient(self):
        with self.assertRaisesRegex(ValueError, 'unmapped'):
            subject.inspect_wasm(fixture(mapped=False))

    def test_inconsistent_function_record_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'inconsistent'):
            subject.inspect_wasm(fixture(record_entry=123))

    def test_different_go_version_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'version'):
            subject.inspect_wasm(fixture(version=b'go1.24.5'))

    def test_function_code_count_must_agree(self):
        with self.assertRaisesRegex(ValueError, 'counts'):
            subject.inspect_wasm(fixture(code_count=2))

    def test_overlapping_memory_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'overlapping'):
            subject.inspect_wasm(fixture(repeated_memory=True))

    def test_truncated_module_and_duplicate_sections_are_rejected(self):
        binary = fixture()
        for changed in [binary[:7], binary[:-1], binary + section(2, b'\0')]:
            with self.subTest(bytes=len(changed)), self.assertRaises(ValueError):
                subject.inspect_wasm(changed)

    def test_only_runtime_name_strings_do_not_qualify(self):
        with self.assertRaises(ValueError):
            subject.inspect_wasm(b'\0asm\1\0\0\0' + section(0, b' '.join(x.encode() for x in subject.SYMBOLS)))

    def test_committed_inventory_notice_and_binary_record_agree(self):
        root = Path(__file__).resolve().parents[2]
        report = json.loads((root / 'compliance/evidence/d2-go-runtime/binary-audit.json').read_text())
        inventory = json.loads((root / 'compliance/inventory.json').read_text())
        component = next(row for row in inventory['components'] if row['id'] == 'd2-go-runtime')
        text = component['licence_texts'][0]
        self.assertEqual(text['sha256'], subject.digest((root / text['path']).read_bytes()))
        self.assertEqual(text['sha256'], report['notice_sha256'])
        self.assertEqual(text['upstream_archive_sha256'], subject.GO_SHA)
        self.assertEqual(report['wasm_sha256'], subject.WASM_SHA)
        self.assertEqual(component['embedded_in'], 'd2')
        self.assertIn('not independently rebuild', component['notes'])
        self.assertEqual(set(report['binary_structure']['runtime_functions']), set(subject.SYMBOLS))
        for record in report['binary_structure']['runtime_functions'].values():
            self.assertGreater(record['code_bytes'], 2)
        notices = (root / 'compliance/generated/THIRD_PARTY_NOTICES.md').read_text()
        self.assertIn((root / text['path']).read_text().strip(), notices)

    def test_notice_and_archive_are_exactly_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            wasm, archive, notice = [root / name for name in ['d2.wasm', 'go.tar.gz', 'LICENSE']]
            wasm.write_bytes(fixture())
            text = b'Copyright fixture\nFull conditions and disclaimer\n'
            notice.write_bytes(text)
            with tarfile.open(archive, 'w:gz') as output:
                for name, data in [('go/LICENSE', text), ('go/VERSION', b'go1.24.6\ntime fixture\n')]:
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    output.addfile(info, io.BytesIO(data))
            with patch.object(subject, 'WASM_SHA', subject.digest(wasm.read_bytes())), patch.object(subject, 'GO_SHA', subject.digest(archive.read_bytes())):
                self.assertEqual(subject.audit(wasm, archive, notice)['notice_sha256'], subject.digest(text))
                notice.write_bytes(text[:-1])
                with self.assertRaisesRegex(ValueError, 'notice'):
                    subject.audit(wasm, archive, notice)
                notice.write_bytes(text)
                wasm.write_bytes(wasm.read_bytes() + b'changed')
                with self.assertRaisesRegex(ValueError, 'digest'):
                    subject.audit(wasm, archive, notice)
                wasm.write_bytes(fixture())
                archive.write_bytes(archive.read_bytes() + b'changed')
                with self.assertRaisesRegex(ValueError, 'digest'):
                    subject.audit(wasm, archive, notice)


if __name__ == '__main__':
    unittest.main()
