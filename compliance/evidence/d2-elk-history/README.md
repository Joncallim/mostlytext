# D2 ELK JavaScript modification history

The pinned D2 source commit `581c91096b62d644fb5168313142c836b7e68e74`
contains `d2layouts/d2elklayout/elk.js`, 3,677,009 bytes, SHA-256
`a297b92da4a257b95c129cc1d8cfb379e2c89bcd4442af90ac06fdd2b1e220b4`.
Its Git blob ID `9ea3a05eb3e8e9663a9b2022e911940a19de264f`
equals the file after D2's [6 August 2025 race fix](https://github.com/d2lang/d2/commit/7861053f3ad8fdec3b52098afd574729b0bab1d9).
The local verifier checks both identities against the complete pinned D2 source
archive without executing the JavaScript. The [history receipt](history.json)
records the immutable file-commit identities, dates, file blob IDs, change
counts and observed GitHub patch digests.
The receipt dates are Git commit **author** dates in UTC; they do not assert
the committer or merge dates.

D2's [11 November 2022 introduction](https://github.com/d2lang/d2/commit/136faa0d1a9d99e1f610ca0260f2603861f17b17)
added the large generated file. The later file history narrows D2's visible
modifications:

- [14 January 2025 layout migration](https://github.com/d2lang/d2/commit/e723881dfe2e0715cd6915d569cb65d48c8fb194): changes global object selection, worker environment selection and startup invocation for the synchronous embedding.
- [5 August 2025 synchronous wrapper](https://github.com/d2lang/d2/commit/c3b5af68178d9711276cada263144155e933779c): exposes layout internals and appends a D2-specific synchronous layout wrapper.
- [5 August 2025 formatting](https://github.com/d2lang/d2/commit/9640af1558d797e51bef4f4568813b095a2ffc5a): changes formatting of that addition.
- [6 August 2025 race fix](https://github.com/d2lang/d2/commit/7861053f3ad8fdec3b52098afd574729b0bab1d9): reuses the worker, adds an initialization path and adjusts the synchronous wrapper.

These file revisions identify actual D2 changes and the exact final blob, but
do **not** establish that the 2022 generated file can be rebuilt from the
staged elkjs 0.8.2, ELK Java, GWT and other preferred-source inputs. The D2
file and elkjs 0.8.2 distribution are not byte-identical; the D2-specific
wrapper is outside the upstream release. The source-offer review must identify
the generator inputs/build procedure and applicable per-file obligations.
This packet is technical provenance, not a grant interpretation or approval to
publish the local source package.

Recheck the pinned source member:

```sh
python3 compliance/evidence/d2-elk-history/verify.py \
  --archive /path/to/d2-source-581c9109.tar.gz
```
