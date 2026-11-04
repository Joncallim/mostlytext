"""Refuse substituted image graphs and ambiguous selected-source overlays."""
import copy
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import verify_viz_image as image


class VizImageTests(unittest.TestCase):
    def setUp(self):
        self.root = TOOLS.parents[1]
        self.folder = self.root / image.PACKET
        self.raw = [(self.folder / n).read_bytes() for n in ('index.json', 'amd64-manifest.json', 'amd64-config.json')]
        self.index, self.manifest, self.config = image.checked_graph(*self.raw)
        self.layers = json.loads((self.folder / 'layer-verification.json').read_text())
        self.selected = json.loads((self.folder / 'selected-files.json').read_text())
        self.old = image.checked_notices(self.root)

    def test_current_graph_and_selected_source_proof_binds_the_publisher_record(self):
        image.verify_installed(self.root)

    def test_index_child_and_config_byte_mutations_refuse(self):
        for i in range(3):
            raw = self.raw.copy()
            raw[i] += b' '
            with self.subTest(object=i), self.assertRaises(ValueError):
                image.checked_graph(*raw)

    def coherent_graph(self, index, manifest, config):
        raw_config = json.dumps(config).encode()
        manifest['config'].update(digest='sha256:' + image.sha(raw_config), size=len(raw_config))
        raw_image = json.dumps(manifest).encode()
        child = next(x for x in index['manifests'] if x['platform'] == {'architecture': 'amd64', 'os': 'linux'})
        child.update(digest='sha256:' + image.sha(raw_image), size=len(raw_image))
        raw_index = json.dumps(index).encode()
        # Exercise graph policy beneath its immutable publisher root. Production
        # roots are never replaced, and verify_installed binds the actual record.
        with patch.multiple(image, INDEX_SHA=image.sha(raw_index), IMAGE_SHA=image.sha(raw_image)):
            image.checked_graph(raw_index, raw_image, raw_config)

    def test_coherently_hashed_wrong_platform_still_refuses(self):
        self.config['architecture'] = 'arm64'
        with self.assertRaisesRegex(ValueError, 'platform'):
            self.coherent_graph(self.index, self.manifest, self.config)

    def test_coherently_hashed_incomplete_or_duplicate_layers_refuse(self):
        for kind in ('missing', 'duplicate'):
            manifest = copy.deepcopy(self.manifest)
            if kind == 'missing':
                manifest['layers'].pop()
            else:
                manifest['layers'][1] = manifest['layers'][0]
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, 'four-layer'):
                self.coherent_graph(copy.deepcopy(self.index), manifest, copy.deepcopy(self.config))

    def test_layer_order_diff_id_size_and_boolean_claims_refuse(self):
        for kind in ('order', 'diff', 'size', 'boolean'):
            rows = copy.deepcopy(self.layers)
            if kind == 'order':
                rows.reverse()
            elif kind == 'diff':
                rows[0]['uncompressedDigest'] = 'sha256:' + '0' * 64
            elif kind == 'size':
                rows[0]['compressedBytes'] += 1
            else:
                rows[0]['compressedBytes'] = True
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                image.validate_layer_receipt(rows, self.manifest, self.config)

    def test_selected_files_cannot_be_missing_duplicate_or_changed(self):
        for kind in ('missing', 'duplicate', 'changed'):
            selected = copy.deepcopy(self.selected)
            if kind == 'missing':
                selected['files'].pop()
            elif kind == 'duplicate':
                selected['files'][1] = selected['files'][0]
            else:
                next(r for r in selected['files'] if r['path'].endswith('/LICENSE.TXT'))['sha256'] = '0' * 64
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                image.validate_selected(selected, self.old, self.manifest)

    def test_release_marker_difference_cannot_be_relabeled_as_equality(self):
        row = next(r for r in self.selected['comparison'] if r['path'] == 'emscripten-version.txt')
        row['matchesPreviousSource'] = True
        with self.assertRaisesRegex(ValueError, 'marker difference'):
            image.validate_selected(self.selected, self.old, self.manifest)

    def layer(self, directory, label, entries):
        path = directory / (label + '.tar.gz')
        with tarfile.open(path, 'w:gz') as file:
            for name, body, kind in entries:
                member = tarfile.TarInfo(name)
                if kind == 'file':
                    member.size = len(body)
                    file.addfile(member, io.BytesIO(body))
                else:
                    member.type = tarfile.SYMTYPE if kind == 'symlink' else tarfile.LNKTYPE
                    member.linkname = body.decode()
                    file.addfile(member)
        return label, path

    def test_overlay_uses_later_replacement_without_applying_host_files(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            a = self.layer(root, 'a', [('emsdk/file', b'old', 'file')])
            b = self.layer(root, 'b', [('emsdk/file', b'new', 'file')])
            files, events = image.read_selected([a, b], {'emsdk/file'})
            self.assertEqual(files, {'emsdk/file': (b'new', 'b')})
            self.assertEqual(events, [])
            self.assertEqual(sorted(p.name for p in root.iterdir()), ['a.tar.gz', 'b.tar.gz'])

    def test_whiteout_and_opaque_directory_hide_lower_sources(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            a = self.layer(root, 'a', [('emsdk/file', b'old', 'file')])
            for marker in ('emsdk/.wh.file', 'emsdk/.wh..wh..opq'):
                b = self.layer(root, 'b', [(marker, b'', 'file')])
                files, events = image.read_selected([a, b], {'emsdk/file'})
                self.assertEqual(files, {})
                self.assertEqual(len(events), 1)

    def test_selected_symlinks_hardlinks_and_linked_parents_refuse(self):
        with tempfile.TemporaryDirectory() as d:
            for name, kind in [('emsdk/file', 'symlink'), ('emsdk/file', 'hardlink'), ('emsdk', 'symlink')]:
                layer = self.layer(Path(d), 'a', [(name, b'/owner/data', kind)])
                with self.subTest(name=name, kind=kind), self.assertRaisesRegex(ValueError, 'link'):
                    image.read_selected([layer], {'emsdk/file'})

    def test_unsafe_duplicate_or_oversized_selected_records_refuse(self):
        with tempfile.TemporaryDirectory() as d:
            for entries, maximum in [([('../escape', b'x', 'file')], 10),
                                     ([('emsdk/file', b'x', 'file')] * 2, 10),
                                     ([('emsdk/file', b'oversized', 'file')], 3)]:
                layer = self.layer(Path(d), 'a', entries)
                with self.subTest(entries=entries), self.assertRaises(ValueError):
                    image.read_selected([layer], {'emsdk/file'}, maximum)

    def test_missing_proof_does_not_qualify(self):
        with tempfile.TemporaryDirectory() as d, self.assertRaisesRegex(ValueError, 'proof missing'):
            image.verify_installed(Path(d))


if __name__ == '__main__':
    unittest.main()
