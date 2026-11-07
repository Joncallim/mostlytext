# Actual pending Finder closure, negative cancellation propagation

PR #138 source `b6445bfb` / actual checkout `4f7391ff` / merge `3b141d4d` have the verified
computed tree `5fd0ddaad5227a6029978284aecf2fd9bea2c77a`. Native42404172704 and
Compliance42404172739 pass on their complete first attempts. Independently read
raw result: two actual cases pass, zero failed/skipped/expected failures. Verify
20 canonical/11 copied/14 generated inputs,12 downloaded compiled roles, actual minimal
provider entitlements,15 immutable log generations, genuine nonce within 0.611 seconds,
live/direct provider events and clean owned UI/observer/stream lifecycle.

Actual provider request 2: start 303.867981, observed pending 305.585778,
Escape 305.585901, window closed 306.859329, terminal completed 314.171539.
The task does not receive cancellation: its cooperative 10.303558-second wait
completes 7.312210 seconds after visible closure, with no cancellation handler.
This is negative system-cancellation feasibility evidence, not a production
cancellation pass. The two actual screenshots show the cold static marker/blue
control and later closed Quick Look window; they are not a full content audit.

Production must not assume closing Quick Look cancels an async provider task.
Real renderer deadlines, bounded admission, fallback, failure-once delivery,
production shared presentation/extension and whole QL-REPLY remain open. All
three earlier first refusals are retained in adjacent first-failure packets.
No product, provider permission, native assertion or original deadline changed.

Each deterministic gzip record preserves exact original bytes. The manifest records
original path, raw length and SHA-256. Native compiled blobs and complete result
bundles remain in the retained first artifact; source/role hashes are bound by the
receipt and independent reader. Original receipts identify their actual tested
checkout and are never retargeted to this documentation commit.
