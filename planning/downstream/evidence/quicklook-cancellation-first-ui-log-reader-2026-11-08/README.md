# First corrected-window UI log-reader failure

Both787497b1 first outcomes are retained: native42398317823 fails, Compliance
passes. Actual source16/generated13/downloaded compiled11roles/metadata/owned/raw
results are independently verified. Original cold positive passes; actual pending
window uniqueness/spinner checks pass. The UI child log command then returns64,
failing its zero-exit assertion. Its stderr was discarded, so the exact underlying
reason is unknown. No Escape was sent; no cancellation outcome follows. The real
provider pending wait later completes. Actual2cases/1pass/1fail/0skip/0expected,
ownednormal65 without timeout/cancel/forced cleanup. First81failure stays failed.

The same host workflow log query succeeds and captures actual provider events.
Read-only inspection of the downloaded UI runner signature confirms its existing
SDK-injected read-only / exception. The provider retains exactly sandbox plus
user-selected read-only, separately. Do not widen either permission set. Move
read-only observation to the already-working guarded host context, with an atomic
bounded temporary JSON record consumed by the UI. Post-run direct provider logs
must independently match the actual UI attachment and request/timestamp ordering.
