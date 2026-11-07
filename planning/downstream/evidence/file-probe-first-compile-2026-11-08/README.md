# First executor-proof compilation failure

Both first native configurations atfada82cd fail compilation before any native
execution. Xcode26 marks Thread.isMainThread unavailable from asynchronous
contexts, including the async MainActor test body. The real moved-read hook is
synchronous and has no such error. Original source is restored; native original,
counterexample and restored results remain NOT_RUN, not passing.

Keep this source frozen through all four first workflow outcomes. The local
material correction will read the same physical-thread property in a synchronous
MainActor helper, with no suspension between caller and observation. The genuine
main-thread precondition stays required, along with all original bytes/hash/size/
thread assertions, sizes, flags, limits, counterexample and native phases. No
warning suppression, skip, weaker actor-only substitute or native retry follows.
