# D2 embedded font reference comparison — 3 November 2026

The embedded Chroma/D2 WOFF names Liberation Mono, Regular, Version 2.00.5.
The original font project's [2.00.5 release](https://github.com/liberationfonts/liberation-fonts/releases/tag/2.00.5)
links both the TTF and source archives captured in [downloads.json](downloads.json).
Its tag resolves to 24ea9469bfb089ab9bf05adb0871d0065d360edc. These are primary
release references, not assumed fonts from an operating-system installation.

The [comparison](comparison.json) admits the exact already-proven D2 WOFF and
publisher TTF archive by complete SHA-256, decompresses the WOFF tables and
compares all data without masking changes. Fifteen of 18 tables match exactly,
including glyph outlines, character map, layout/metrics, hinting and the complete
name table. This is a strong content correspondence to a named reference; it
is not an identical original TTF or proven conversion history.

Three tables differ: FFTM, head and post. The post header differs beyond checksum
or timestamp data: D2's WOFF has underlinePosition -561 and isFixedPitch 0; the
published TTF has -477 and 1. Both underlineThickness values are 84. Glyph-name
array/data after that header match. The [OpenType post specification](https://learn.microsoft.com/en-us/typography/opentype/spec/post)
defines these typed fields. The raw offsets and hashes are preserved; no result
is normalized into a false equality.

## Subsequent upstream account

In [Chroma commit `06e404d` (8 July 2026)](https://github.com/alecthomas/chroma/commit/06e404d019c4dba37a1e7df45baeb32b7caffd68),
the upstream project states that its previous embedded font came from an
intermediate 2.00.5 build with incorrect `post` metadata (`isFixedPitch=0` and
the wrong `underlinePosition`). The commit replaces that font with a WOFF that
it says was converted losslessly from the official Liberation Mono 2.1.5 TTF.
This upstream account is consistent with the two observed `post` field
differences above. It does not explain the differing `FFTM` or `head` tables,
identify the exact intermediate 2.00.5 input bytes, or independently verify
the replacement WOFF. The pinned Chroma v2.14.0 module and D2 0.1.33 binary
still contain the earlier WOFF identified by the hashes below; this later
upstream commit does not change the shipped font bytes.

## Meaning for the open review

The published [OFL webfont/RFN guidance](https://openfontlicense.org/webfonts-and-reserved-font-names/)
distinguishes unchanged format wrapping from changed font data/metadata and
requires case-specific consideration of functional equivalence. The table
comparison and upstream account do not establish the exact original conversion
input, permission, functional equivalence, a required remedy or legal clearance.
They do establish why a claim of an unchanged reference font is unsupported.
Independent font/RFN review remains explicit in D2 LC-03; no source-offer status
or release gate changes.
The existing font selection, exact publisher WASM and full OFL/copyright notice
are preserved. This audit changes no font name, source or binary.

## Reproduction and controls

Extract the already-hashed WOFF from the verified Chroma module in the D2 review
archive using the base64 string selected by verify_d2_font.py. Then:

```sh
python3 compliance/tools/compare_d2_font_reference.py \
  --woff /path/to/liberation-font.woff \
  --reference /path/to/liberation-fonts-ttf-2.00.5.tar.gz \
  --output /tmp/d2-font-comparison.json
cmp compliance/evidence/d2-font-reference/comparison.json /tmp/d2-font-comparison.json
```

The input archive SHA-256 is f14ff0a0be87b5aeb672e669363b5a699db76feb1144b06798261c0fdcd2b24d;
the unique regular TTF member is pinned at
816a2a46416a2d3550b401ff8d0c084ba7e8138782f7057b1e537446012f769a.
The WOFF remains 29d9447a83dbf9866aff37f7dc972441302da97f9a242ea0405f60841e9b630f.
Two real-input corruption controls reject a changed WOFF and changed publisher
archive before parsing. This read-only tool is deliberately for those pinned
inputs, not an arbitrary untrusted-font parser. No font package/source script,
application, renderer or native UI is executed.

Raw reference archives, WOFF, names and negative controls are retained under
`/Volumes/Fast SSD/CORTANA-Builds/nested-notice-completion-20261103`.
The source archive is captured as a reference, not asserted as the publisher's
original conversion source. No public source object or binary is published.
