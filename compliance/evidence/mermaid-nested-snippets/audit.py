#!/usr/bin/env python3
"""Recount selected nested-code positions from exact Mermaid source-map inputs."""

import argparse
import collections
import hashlib
import json
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from source_map_evidence import mapped_positions  # noqa: E402

INPUTS = {
    'mermaid-11.17.2.tgz': '6ad2f42c3fc26bbf9e45cbb6d11898972573ea52b33a5f4ff51952899f950ffd',
    'layout-base-1.0.2.tgz': 'efea1306903d9d043c42c1e7931b2d97b4f519cff04b1347fa308032a52eebab',
    'layout-base-2.0.1.tgz': '34165e46d8c4b9d719a592e39a60fa5f7324c21a3edd02733e1116b17013defd',
    'cytoscape-3.34.0.tgz': '4155f863f4408d18bb637afb5808dff7840ca7361437067faf45bbe8c970e768',
    'js-yaml-4.3.0.tgz': '8594ee34496dd2e41ec934fd202843dc993be9ab2d7d5d47579146962fbdfae6',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def archive_file(archive, name):
    with tarfile.open(archive, 'r:gz') as tar:
        return tar.extractfile('package/' + name).read()


def audit(inputs):
    for name, expected in INPUTS.items():
        if sha((inputs / name).read_bytes()) != expected:
            raise ValueError(name + ': archive hash changed')
    mermaid = inputs / 'mermaid-11.17.2.tgz'
    data = json.loads(archive_file(mermaid, 'dist/mermaid.min.js.map'))
    generated = archive_file(mermaid, 'dist/mermaid.min.js').decode()
    selections = [
        ('jama_svd_hypot', 'layout-base@2.0.1/', 'layout-base-2.0.1.tgz', 'layout-base.js', 4318, 4954, 1989),
        ('random_seed_1_0_2', 'layout-base@1.0.2/', 'layout-base-1.0.2.tgz', 'layout-base.js', 3155, 3159, 21),
        ('random_seed_2_0_1', 'layout-base@2.0.1/', 'layout-base-2.0.1.tgz', 'layout-base.js', 3224, 3228, 21),
        ('cytoscape_rounded_corner', 'cytoscape@3.34.0/', 'cytoscape-3.34.0.tgz', 'dist/cytoscape.esm.mjs', 23500, 23600, 314),
    ]
    indices = {}
    for label, path_part, archive, member, first, end, expected in selections:
        source_index = next(i for i, name in enumerate(data['sources'])
                            if path_part in name and name.endswith(member))
        source = archive_file(inputs / archive, member)
        if source.decode() != data['sourcesContent'][source_index]:
            raise ValueError(label + ': map source differs from npm member')
        indices[label] = {'source_index': source_index, 'source_path': data['sources'][source_index],
                          'source_sha256': sha(source), 'first_line_inclusive': first,
                          'end_line_exclusive': end, 'expected_mappings': expected}
    counts = collections.Counter()
    for _, _, source_index, source_line, _ in mapped_positions(data, generated):
        if source_index is None:
            continue
        for label, item in indices.items():
            if source_index == item['source_index'] and item['first_line_inclusive'] <= source_line + 1 < item['end_line_exclusive']:
                counts[label] += 1
    for label, item in indices.items():
        item['mapped_positions'] = counts[label]
        if counts[label] != item['expected_mappings']:
            raise ValueError(label + ': mapping count changed')
    exception = archive_file(inputs / 'js-yaml-4.3.0.tgz', 'lib/exception.js')
    return {'schema': 1, 'mermaid_archive_sha256': INPUTS['mermaid-11.17.2.tgz'],
            'mermaid_map_sha256': sha(archive_file(mermaid, 'dist/mermaid.min.js.map')),
            'mermaid_bundle_sha256': sha(generated.encode()),
            'snippets': indices,
            'js_yaml_exception': {'source_sha256': sha(exception), 'citation': 'stackoverflow.com/questions/8458984',
                                  'classification': 'Related Error subclass technique; copied expression not established by narrow comparison.'},
            'scope': 'Selected source-map positions, not a grant or complete nested-code review.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(audit(args.inputs), indent=2) + '\n')


if __name__ == '__main__':
    main()
