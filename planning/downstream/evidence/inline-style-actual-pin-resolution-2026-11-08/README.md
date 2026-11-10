# Actual deliberate Textual lock resolution

[Complete first 42449931117](https://github.com/Joncallim/mostlytext/actions/runs/42449931117)
passes at never-merge source `b7d0d246`. Eleven exact gzip records preserve the
whole workflow log ZIP, original metadata, source/host/command/restoration receipt,
both manifests/locks, complete stdout/stderr and independent readback. All six
source hashes and the actual resolved Git revision are verified. SwiftPM resolves
Textual `ff74cf54`; the other 23 immutable pin rows remain identical. Ordinary
originHash metadata changes. The canonical candidate adopts the exact downloaded
lock bytes, SHA256 `716882ac8bc84aae7f5fa0c8b9ea627d9a6330ba24688f486fc690cd710be176`.
The original checkout inputs are restored exactly after capture. No local package
resolution, product build, app/GUI or engine execution occurs. The shipping
candidate still requires its complete uninstrumented native/full qualification.
