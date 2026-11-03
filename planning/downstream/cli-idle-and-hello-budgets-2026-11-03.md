# Keep CLI greetings independent of idle polling

## Owner outcome

A CLI connection arriving near the end of the application's idle polling turn
must still receive its initial instance greeting. Keep that greeting bounded,
preserve cancellation and peer/path checks, and do not retry a user request.

## Baseline and evidence

Master is 87d8d48b; the reviewed source baseline is a84924bb. Hosted runs
41521890558 and 41546448434 both report invalidResponse in the real eight-input
admission/disconnect case. The latter fails after 292 ms. The earlier 30 private
repeats pass, so those repeats do not diagnose the hosted failures.

The application passes one 250 ms deadline to listener.accept. That method
waits for a connection and sends its greeting against the same deadline. A
connection admitted near the boundary can be closed before a single greeting
byte is sent. The client then reports invalidResponse for clean EOF. This is a
confirmed source defect; the hosted logs alone do not identify the precise
failing connect call or prove that every historical invalidResponse has this
cause.

## Binding amendment

Preserve public accept(until:isCancelled:) and its existing shared deadline.
Add a module-internal overload with an explicit optional greeting duration.
Only the application listener supplies a separate 250 ms greeting duration,
starting immediately after the kernel accepts the descriptor. The idle wait
remains 250 ms; both phases still poll cancellation in at most 50 ms slices.
Peer adoption, lease/namespace/socket identity checks and the greeting all
consume the new phase's finite budget. No client input/acceptance deadline,
request cap, resource limit, instance policy, error handling or retry changes.

This narrow amendment replaces the assumption that an idle poll deadline can
also serve as the whole greeting budget. It does not change the public endpoint
contract or introduce a connection pool, reconnect or native activation.

## Verification

Use the real private pathname socket and cancellation probe to expire the idle
deadline at the first greeting check after acceptance. Require a complete valid
instance greeting with the separate phase budget. An explicit legacy-forwarding
adapter makes the old source compile against the new internal test signature;
it must fail that actual greeting assertion. Also verify zero greeting budget
and cancellation close only that peer and leave the listener usable. Retain all
existing endpoint/admission controls, run the complete source corpus in Debug
and Release, then require complete combined hosted qualification before merging.
No local application or UI execution is authorized by these socket controls.
