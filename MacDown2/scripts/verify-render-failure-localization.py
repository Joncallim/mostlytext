#!/usr/bin/env python3
"""Read-only guard for app-owned diagram and PDF failure catalog routes."""
import re
import argparse
from pathlib import Path


def verify(repo):
    routes = ['noPreviewImage.message()', 'timedOut.message()',
              'outputTooLarge(byteCount: byteCount).message()', 'rendererUnavailable.message()']
    old = ['"no preview image was produced"', '"rendering timed out"',
           '"renderer unavailable"', '"rendered output too large (\\(byteCount) bytes)"']
    for family in ['Mermaid', 'D2', 'Graphviz']:
        source = (repo / 'MacDown2/MacDown2' / f'{family}DiagramBlockView.swift').read_text()
        if any(value in source for value in old):
            raise ValueError(f'{family}: known failure detail bypasses the app catalog')
        if any(source.count('DiagramFailurePresentation.' + route) != 1 for route in routes):
            raise ValueError(f'{family}: missing or duplicate shared failure route')
        if 'case let .invalidSyntax(message): return message' not in source:
            raise ValueError(f'{family}: renderer syntax message must remain literal')
        if 'return error.localizedDescription' not in source:
            raise ValueError(f'{family}: unknown system diagnostic changed')
    counts = [('PDFSnapshotFallback.swift', '    enum FallbackError:', 7),
              ('PDFExportAdapter.swift', '    enum PDFExportError:', 8)]
    for file, declaration, count in counts:
        body = error_body((repo / 'MacDown2/MacDown2' / file).read_text(), declaration)
        if len(re.findall(r'String\(\s*localized:', body)) != count:
            raise ValueError(f'{file}: missing PDF error/recovery catalog route')
        if re.search(r'case[^:\n]+:\s*"', body) or re.search(r'recoverySuggestion: String\?\s*\{\s*"', body):
            raise ValueError(f'{file}: PDF detail bypasses the app catalog')
    return {'views': 3, 'diagram_routes': 12, 'pdf_routes': 15, 'status': 'passed'}


def error_body(source, declaration):
    start = source.index(declaration)
    cursor = source.index('{', start) + 1
    depth = 1
    # These reviewed value enums have plain message literals without braces.
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


if __name__ == '__main__':
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
    print(json.dumps(verify(parser.parse_args().repo)))
