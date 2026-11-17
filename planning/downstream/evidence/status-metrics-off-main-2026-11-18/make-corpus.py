#!/usr/bin/env python3
"""Recreate the benchmark input from the pinned distinct Markdown paths."""

from pathlib import Path
import sys

repo = Path(sys.argv[1])
paths = Path(__file__).with_name('corpus-paths.txt').read_text().splitlines()
output = ''.join(
    f'\n# {name}\n' + (repo / name).read_text(encoding='utf-8', errors='replace')
    for name in paths
)
Path(sys.argv[2]).write_text(output, encoding='utf-8')
