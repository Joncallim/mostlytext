# Markdown document icon

This candidate puts the frozen 10° Slant mark on a neutral document sheet.
The mark sources come directly from `../slant/validation/` at their approved
display sizes. The sheet silhouette, fold, border and placement are new
composition choices approved by the owner on 9 November 2026. The remaining
Finder handoff is in
[`planning/downstream/markdown-document-icon-decision.md`](../../../planning/downstream/markdown-document-icon-decision.md).

From the repository root on macOS:

```sh
python3 design/brand/document-icon/build.py --preview-dir design/brand/document-icon/preview
cd MacDown2 && xcodegen generate && cd ..
python3 design/brand/document-icon/verify.py
```

The generator uses only Python's standard library plus macOS `sips` and
`iconutil`. It writes the app's `MarkdownDocument.icns` and the four review
PNGs/one SVG. `verify.py` rebuilds and compares every tracked output, checks
the ten extracted icon sizes, and validates the generated plist. Pass a built
`.app` through `--app` for the actual bundle-resource and compiled-plist check.

These checks do not establish installed Finder/Open With acceptance.
