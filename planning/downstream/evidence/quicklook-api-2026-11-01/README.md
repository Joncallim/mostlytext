# Quick Look SDK contract check

CORTANA, macOS 26.5.1, Xcode 26.6 / macOS 26.5 SDK, 1 November 2026.

The inherited-method control fails with `method does not override any method
from its superclass`. Explicit QLPreviewingController conformance compiles with
Swift 6, complete strict concurrency and warnings as errors. The async method,
HTML reply, `.utf8` String.Encoding property and typed PNG attachment also
compile into a standalone library. Source and SDK header hashes are recorded.

This corrects the older handoff's instruction against explicit conformance.
The shipping header and Apple's current [provider documentation](https://developer.apple.com/documentation/quicklookui/qlpreviewprovider)
require that conformance. The [reply initializer](https://developer.apple.com/documentation/quicklookui/qlpreviewreply/init(dataofcontenttype:contentsize:createdatausing:))
still uses a synchronous data factory. This type check does not establish the
best placement for expensive work, callback executor behavior or cancellation.

Run `python3 -B verify-api.py --output <new-empty-output-path>` to replay.
It writes compiler outputs and receipts only. It never invokes the library,
packages an application/extension, calls Launch Services/PlugInKit, registers a
handler, or changes any default application. The positive source is a
compile-only witness, not an installable preview provider.

Runtime QL-REPLY remains NOT_RUN: a signed/isolated static HTML+PNG reply,
actual grants, cold Finder invocation, factory repetition/retention, slow
worker fallback, cancellation and timing all still require the protected test
account's usable GUI session. Compile success is not that platform acceptance.
