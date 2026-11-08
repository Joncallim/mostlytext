#!/usr/bin/env python3
"""Never-merge hosted renderer-stage diagnostic; records intentionally modified effective source."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys

PIN = 'dd123d4f7052d84032cafb22c62cd467916518dd'
ROOT = Path('/Users/runner/work/_temp/preview-grant-probe')
FORK = Path('/Users/runner/work/_temp/preview-grant-app/SourcePackages/checkouts/textual')
EXPECTED = {
    'Sources/Textual/Internal/Attachment/WithAttachments.swift': 'b35d2896f6bfd4a8a3656d3746b76636a727f9b030e3569292aa4af7d096b1e5',
    'Sources/Textual/Internal/InlineText/WithInlineStyle.swift': '838c1831eda252291266ddc4542ddb1876385c132d45b5fa61bb29e93043e255',
    'Sources/Textual/Internal/TextFragment/TextFragment.swift': '839bae276e3451107bf4d28f9f29a48ea09ea202a54c44a86e708243ec03a6b8',
    'Sources/Textual/Internal/TextFragment/TextBuilder.swift': '8bc965e2ec5c1146ef9857114c24cb32826c9e0e836dc5c60a28157f1d3b027e',
}
HELPER_PATH = 'Sources/Textual/Internal/MostlyTextPublicationTrace.swift'
HELPER = r'''import SwiftUI

/// Disposable hosted diagnosis only. This source is never a shipping dependency change.
@MainActor
public enum MostlyTextPublicationTrace {
  private static var events: [String] = []
  private static var overflow = false
  private static var fault = "none"

  public static func snapshot() -> (events: [String], overflow: Bool, fault: String) {
    (events, overflow, fault)
  }

  public static func setFault(_ value: String) {
    precondition(["none", "inline", "fragment"].contains(value))
    fault = value
  }

  static func shouldSuppress<T: AttributedStringProtocol>(_ stage: String, value: T) -> Bool {
    guard fault == stage, value.runs.contains(where: { $0.textual.attachment != nil }) else {
      return false
    }
    emit("controlled-suppression-" + stage, value: value)
    return true
  }

  public static func reset() {
    events.removeAll(keepingCapacity: true)
    overflow = false
  }

  static func emit<T: AttributedStringProtocol>(
    _ stage: String, value: T, details: String = ""
  ) {
    guard events.count < 4000 else {
      overflow = true
      return
    }
    let attachments = value.runs.filter { $0.textual.attachment != nil }.count
    let urls = value.runs.compactMap { $0.imageURL?.hashValue }.prefix(4)
    events.append("TEXTUAL_PUBLICATION stage=\(stage) attachedRuns=\(attachments) chars=\(value.characters.count) imageHashes=\(Array(urls)) \(details)")
  }

  static func cached(_ value: AttributedString?) {
    if let value {
      emit("inline-body-cached", value: value)
    } else {
      emit("inline-body-cached-missing", value: AttributedString())
    }
  }
}
'''.encode()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def replace_once(raw, anchor, replacement):
    anchor = anchor.encode(); replacement = replacement.encode()
    if raw.count(anchor) != 1:
        raise RuntimeError('The exact existing renderer statement is absent or duplicated')
    return raw.replace(anchor, replacement)


def transformed(originals, variant="original"):
    if variant not in ["original", "current-input"]:
        raise RuntimeError("Unknown controlled renderer variant")
    if set(originals) != set(EXPECTED) or any(sha(originals[p]) != h for p, h in EXPECTED.items()):
        raise RuntimeError('Refuse any renderer source other than the exact four pinned originals')
    result = dict(originals)
    p = 'Sources/Textual/Internal/Attachment/WithAttachments.swift'
    result[p] = replace_once(result[p], '      self.resolvedAttributedString = attributedString', r'''      MostlyTextPublicationTrace.emit(
        "attachments-ready", value: attributedString,
        details: "model=\(ObjectIdentifier(self)) request=\(requestIdentity?.uuidString ?? "none")"
      )
      self.resolvedAttributedString = attributedString''')
    p = 'Sources/Textual/Internal/InlineText/WithInlineStyle.swift'
    result[p] = replace_once(result[p], '    content(output ?? AttributedString())', '''    let _ = MostlyTextPublicationTrace.emit("inline-body-input", value: input)
    let _ = MostlyTextPublicationTrace.cached(output)
    content(output ?? AttributedString())''')
    result[p] = replace_once(result[p], '        resolve(\n', '''        MostlyTextPublicationTrace.emit("inline-existing-change", value: newValue.values.0)
        resolve(
''')
    result[p] = replace_once(result[p], '    self.output = output', '''    MostlyTextPublicationTrace.emit("inline-resolved-output", value: output)
    self.output = output''')
    p = 'Sources/Textual/Internal/TextFragment/TextFragment.swift'
    result[p] = replace_once(result[p], '    text\n', '''    let _ = MostlyTextPublicationTrace.emit("fragment-body", value: content)
    text
''')
    result[p] = replace_once(result[p], '        self.textBuilder = TextBuilder(newValue, environment: textEnvironment)', '''        MostlyTextPublicationTrace.emit("fragment-existing-change", value: newValue)
        self.textBuilder = TextBuilder(newValue, environment: textEnvironment)''')
    p = 'Sources/Textual/Internal/TextFragment/TextBuilder.swift'
    for stage, anchor in [('builder-init', '      let attachmentSizes = content.attachmentSizes(for: .unspecified, in: environment)'),
                          ('builder-size-change', '      let attachmentSizes = content.attachmentSizes(for: .init(size), in: environment)')]:
        result[p] = replace_once(result[p], anchor, anchor + '\n' +
            '      MostlyTextPublicationTrace.emit("' + stage + '", value: content,\n' +
            r'        details: "sizes=\(Array(attachmentSizes.values.prefix(4)))")')
    if variant == "original":
        p = 'Sources/Textual/Internal/InlineText/WithInlineStyle.swift'
        result[p] = replace_once(result[p], '        resolve(\n',
            '        if MostlyTextPublicationTrace.shouldSuppress("inline", value: newValue.values.0) { return }\n        resolve(\n')
        p = 'Sources/Textual/Internal/TextFragment/TextFragment.swift'
        result[p] = replace_once(result[p], '        self.textBuilder = TextBuilder(newValue, environment: textEnvironment)',
            '        if MostlyTextPublicationTrace.shouldSuppress("fragment", value: newValue) { return }\n        self.textBuilder = TextBuilder(newValue, environment: textEnvironment)')
    else:
        result.update(current_input_variants(originals))
    result[HELPER_PATH] = HELPER
    return result


def current_input_variants(originals):
    inline = 'Sources/Textual/Internal/InlineText/WithInlineStyle.swift'
    fragment = 'Sources/Textual/Internal/TextFragment/TextFragment.swift'
    body = """  var body: some View {
    let output = resolve(attributedString: input, style: style, in: environment)
    let _ = MostlyTextPublicationTrace.emit("inline-body-input", value: input)
    let _ = MostlyTextPublicationTrace.emit("inline-resolved-output", value: output)
    content(output)
  }
"""
    source = originals[inline].decode()
    start = source.index('  var body: some View {')
    end = source.index('\n  private func resolve(', start)
    source = source[:start] + body + source[end:]
    source = source.replace('  @State private var output: AttributedString?\n\n', '')
    source = source.replace('    in environment: TextEnvironmentValues\n  ) {',
                            '    in environment: TextEnvironmentValues\n  ) -> AttributedString {')
    source = source.replace('    self.output = output', '    return output')
    cached = originals[fragment]
    cached = replace_once(cached, '  @State private var textBuilder: TextBuilder?',
                          '  @State private var builders = BuilderCache()')
    cached = replace_once(cached, '    text\n',
                          '    let builder = builders.resolve(content, environment: textEnvironment)\n'
                          '    let _ = MostlyTextPublicationTrace.emit("fragment-body", value: content)\n'
                          '    builder.text\n')
    cached = replace_once(cached, '        guard let size, let textBuilder else { return }\n        textBuilder.sizeChanged(size, environment: textEnvironment)',
                          '        guard let size else { return }\n'
                          '        builders.sizeChanged(size, expected: builder, environment: textEnvironment)')
    cached = replace_once(cached, '      .onChange(of: content, initial: true) { _, newValue in\n'
                          '        self.textBuilder = TextBuilder(newValue, environment: textEnvironment)\n      }\n', '')
    cache = """  @MainActor
  private final class BuilderCache {
    private var builder: TextBuilder?
    private var content: Content?
    private var environment: TextEnvironmentValues?
    private var size: CGSize?

    func resolve(_ content: Content, environment: TextEnvironmentValues) -> TextBuilder {
      if let builder, self.content == content, self.environment == environment {
        return builder
      }
      let current = TextBuilder(content, environment: environment)
      if let size { current.sizeChanged(size, environment: environment) }
      self.content = content
      self.environment = environment
      self.builder = current
      return current
    }

    func sizeChanged(_ size: CGSize, expected: TextBuilder, environment: TextEnvironmentValues) {
      guard builder === expected else { return }
      self.size = size
      expected.sizeChanged(size, environment: environment)
    }
  }"""
    cached = replace_once(cached, '  private var text: Text {\n    textBuilder?.text ?? Text(verbatim: "")\n  }', cache)
    return {inline: source.encode(), fragment: cached}


def command(*args):
    return subprocess.check_output(['git', *args], cwd=FORK)


def read_regular(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
        raise RuntimeError('Effective dependency source must be a bounded regular file')
    return path.read_bytes()


def capture(files, label):
    rows = {}; total = 0
    if not 1 <= len(files) <= 2000: raise RuntimeError('Unknown effective fork file count')
    for name in files:
        if Path(name).is_absolute() or '..' in Path(name).parts: raise RuntimeError('Redirected dependency path')
        data = read_regular(FORK / name); total += len(data)
        if total > 32 * 1024 * 1024: raise RuntimeError('Effective fork source budget exceeded')
        target = ROOT / 'textual-effective-source' / label / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream: stream.write(data)
        rows[name] = {'sha256': sha(data), 'bytes': len(data), 'blob': str(target.relative_to(ROOT))}
    return rows


def main():
    from preview_compiled_inputs import check_host
    if sys.flags.optimize or sys.argv[1:] not in [['patch'], ['verify'], ['bind'], ['observe']]:
        raise RuntimeError('Select one fixed nonoptimized diagnostic phase')
    check_host(ROOT)
    variant = os.environ.get('MOSTLYTEXT_RENDERER_VARIANT')
    if variant not in ['original', 'current-input']:
        raise RuntimeError('Require the fixed original or current-input hosted variant')
    if FORK.resolve() != FORK or command('rev-parse', 'HEAD').decode().strip() != PIN:
        raise RuntimeError('Require the exact actual pinned hosted dependency')
    path = ROOT / 'textual-effective-source.json'
    if sys.argv[1] == 'patch':
        if command('status', '--porcelain', '--untracked-files=all') or path.exists():
            raise RuntimeError('Require a clean actual pinned dependency before patching once')
        names = command('ls-files', '-z').decode().rstrip('\0').split('\0')
        originals = {p: read_regular(FORK / p) for p in EXPECTED}
        changes = transformed(originals, variant)
        ROOT.mkdir(parents=True, exist_ok=True)
        before = capture(names, 'before')
        batch = subprocess.check_output(['git', 'cat-file', '--batch'], input=''.join(PIN + ':' + p + '\n' for p in names).encode(), cwd=FORK)
        stream = io.BytesIO(batch)
        for name in names:
            header = stream.readline().split()
            if len(header) != 3 or header[1] != b'blob': raise RuntimeError('Unknown actual pinned fork object')
            raw = stream.read(int(header[2]))
            if stream.read(1) != b'\n' or sha(raw) != before[name]['sha256']:
                raise RuntimeError('Actual initial fork bytes differ from its committed pin')
        for name, data in changes.items():
            target = FORK / name
            if target.exists(): target.chmod(target.stat().st_mode | 0o200)
            target.write_bytes(data)
        after = capture([*names, HELPER_PATH], 'after')
        dirty = command('status', '--porcelain', '--untracked-files=all').decode()
        record = {'diagnostic_only': True, 'qualification_candidate': False, 'original_pin': PIN,
                  'variant': variant, 'original_tree': command('rev-parse', 'HEAD^{tree}').decode().strip(),
                  'effective_source_modified': True, 'actual_dirty_status': dirty,
                  'changed_paths': sorted(changes), 'before': before, 'after': after}
        path.write_text(json.dumps(record, indent=2) + '\n')
        print('Actual pinned bytes and every intentionally modified effective dependency file captured')
        return
    record = json.loads(path.read_bytes())
    if record['original_pin'] != PIN or record['qualification_candidate'] is not False or record['variant'] != variant:
        raise RuntimeError('Effective dependency proof was retargeted')
    for label in ['before', 'after']:
        for name, row in record[label].items():
            archived = read_regular(ROOT / row['blob'])
            if len(archived) != row['bytes'] or sha(archived) != row['sha256']:
                raise RuntimeError('Archived original/effective source changed')
            if label == 'after' and read_regular(FORK / name) != archived:
                raise RuntimeError('Actual compiled dependency source changed after capture')
    if command('status', '--porcelain', '--untracked-files=all').decode() != record['actual_dirty_status']:
        raise RuntimeError('Unknown extra dependency changes appeared')
    if sys.argv[1] == 'bind':
        compiled_raw = (ROOT / 'compiled-initial.json').read_bytes()
        compiled = json.loads(compiled_raw)
        if compiled['phase'] != 'initial' or compiled['configuration'] != 'Release':
            raise RuntimeError('Require actual initial Release compiled inputs')
        value = {'diagnostic_only': True, 'qualification_candidate': False,
                 'effective_source_manifest_sha256': sha(path.read_bytes()),
                 'compiled_manifest_sha256': sha(compiled_raw),
                 'actual_compiled_role_hashes': {k: v['sha256'] for k, v in compiled['inputs'].items()}}
        with (ROOT / 'textual-compiled-binding.json').open('x') as output:
            output.write(json.dumps(value, indent=2) + '\n')
    if sys.argv[1] == 'observe':
        binding = json.loads((ROOT / 'textual-compiled-binding.json').read_bytes())
        if (binding['effective_source_manifest_sha256'] != sha(path.read_bytes())
                or binding['compiled_manifest_sha256'] != sha((ROOT / 'compiled-initial.json').read_bytes())):
            raise RuntimeError('Actual source/compiled binding changed after build')
        raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(ROOT / 'actual-initial.xcresult')])
        (ROOT / 'actual-initial-summary.json').write_bytes(raw)
        owned = json.loads((ROOT / 'diagnostics/status.json').read_bytes())
        log = (ROOT / 'probe.log').read_text()
        rows = [line for line in log.splitlines() if 'TEXTUAL_SCENARIO' in line]
        buffered = []; missing = []
        for name in ['initial', *[f'{i:02d}-{journey}' for i in range(12) for journey in ['production', 'revision']], 'final']:
            try:
                data = json.loads((ROOT / 'textual-scenarios' / (name + '.json')).read_bytes())
                if data['scenario'] != name or data['diagnostic_only'] is not True or data['qualification_candidate'] is not False:
                    raise RuntimeError('Native buffered scenario identity changed')
                buffered.append(data)
            except (OSError, ValueError, KeyError, RuntimeError) as error:
                missing.append({'scenario': name, 'outcome': 'NOT_CAPTURED', 'error': str(error)[:2048]})
        host_path = ROOT / 'textual-diagnostic-host.json'
        host = json.loads(host_path.read_bytes()) if host_path.exists() else None
        output = {'diagnostic_only': True, 'qualification_candidate': False,
                  'effective_source_manifest_sha256': sha(path.read_bytes()),
                  'actual_owned_status': owned, 'actual_summary': json.loads(raw),
                  'actual_trace_lines': rows, 'buffered_scenarios': buffered,
                  'scenario_errors': missing, 'actual_diagnostic_host': host,
                  'trace_limit_reached': any(row['overflow'] for row in buffered) if not missing else None,
                  'scope': 'Actual stage observations of deliberately modified pinned source, never whole Preview qualification or sole causal proof'}
        (ROOT / 'textual-stage-observations.json').write_text(json.dumps(output, indent=2) + '\n')
        if missing: raise RuntimeError('Fixed buffered scenarios were not all captured; actual failed outcome retained')
        if host is None: raise RuntimeError('Actual native diagnostic host facts were not captured')
        if not rows: raise RuntimeError('Actual compiled renderer emitted no stage observations')
        if output['trace_limit_reached']: raise RuntimeError('Actual diagnostic trace budget exhausted')
    print('Every original and effective renderer source byte is bound; pin metadata is not mistaken for unchanged source')


if __name__ == '__main__':
    main()
