#!/usr/bin/env python3
"""Compose the frozen outlined lockup on a repository social-preview canvas."""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'slant/production/out/mostlytext-lockup.svg'
source = SOURCE.read_text(encoding='utf-8')
match = re.fullmatch(r'<svg[^>]+viewBox="0 0 ([\d.]+) ([\d.]+)"[^>]*>(.*)</svg>\s*', source, re.S)
if match is None:
    raise SystemExit('Expected the canonical self-contained outlined lockup SVG')
width, height = float(match[1]), float(match[2])
body = match[3]
if any(value in body for value in ('<text', '<image', '<script', 'href=')):
    raise SystemExit('Preview must use only the existing outlined geometry')
scale = min(960 / width, 320 / height)
x, y = (1280 - width * scale) / 2, (640 - height * scale) / 2
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="640" viewBox="0 0 1280 640" role="img" aria-labelledby="title desc">
<title id="title">MostlyText</title>
<desc id="desc">The frozen ten-degree Slant MT mark and MostlyText wordmark on white.</desc>
<rect width="1280" height="640" fill="#fff"/>
<g color="#11141A" transform="translate({x:.6f} {y:.6f}) scale({scale:.9f})">{body}</g>
</svg>
'''
(HERE / 'mostlytext-repository-preview.svg').write_text(svg, encoding='utf-8')
print('Wrote the repository preview from the canonical outlined lockup.')
