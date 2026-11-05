# Audit ownership and release-gate checks — 5 November 2026

Verified source: `a33662d92dd401c163513d17e8809093c6e30e5d`.
The [machine-readable record](verification.json) binds source hashes, exact
commands/results, retained log hashes and live issue-body hashes. These are
source/policy/control-flow observations, not native or final-release evidence.

## Three completed evidence-handling criteria

| Criterion | Evidence and meaning |
|---|---|
| MostlyText #8: #4 consumes the compliance gate | #4 explicitly requires #14 final exact-artifact verification. `sign-notarize-dmg.sh` invokes `check --release --artifact` against the built app before submission; 23 existing behavioral tests pass using stub Apple tools. The negative compliance fixture stops release-candidate mode before any notary submission; dry-run records UNVERIFIED. The real source gate still fails six predicates. Green app/Compliance CI cannot substitute for them. |
| MostlyText #17: delegated evidence stays with owners | Current #11 explicitly owns F06/F13 and final F07 export parity; #13 explicitly owns R02; #3 explicitly owns L01. The transfer map resolves historical #118/#121/#17. #15 remains OPEN. Original macdown_2 #159/#163/#173/#174 remain CLOSED at their original URLs. This completes link/ownership reconciliation, not the delegated acceptance work. |
| MostlyText #17: #8 consumes the full audit | #8 explicitly requires every direct finding fixed/proved, delegated closure, native evidence and fresh post-E23 review. Its original closure rows remain incomplete. The existing readiness validator passes 49 controls normally and optimized, including runtime/publication/independence/closure-waiver rejection. Its output declares six probes NOT RUN and zero application tests. The graph is architecture-only; it does not query or enforce live GitHub issue state. |

## Live ownership links

- [F06/F13/final F07: MostlyText #11](https://github.com/Joncallim/mostlytext/issues/11)
- [R02: MostlyText #13](https://github.com/Joncallim/mostlytext/issues/13), transferred from [macdown_2 #121](https://github.com/Joncallim/macdown_2/issues/121)
- [L01: MostlyText #3](https://github.com/Joncallim/mostlytext/issues/3)
- [Audit consumer: MostlyText #8](https://github.com/Joncallim/mostlytext/issues/8)
- [Compliance consumer: MostlyText #4](https://github.com/Joncallim/mostlytext/issues/4)
- [WebKit diagnosis: MostlyText #15 remains open](https://github.com/Joncallim/mostlytext/issues/15)
- Historical closed records: [#159](https://github.com/Joncallim/macdown_2/issues/159), [#163](https://github.com/Joncallim/macdown_2/issues/163), [#173](https://github.com/Joncallim/macdown_2/issues/173), [#174](https://github.com/Joncallim/macdown_2/issues/174)

## Limits

No production script/validator/pin/resource or acceptance receipt changed. No
real signing, Apple submission, product/AppKit/WebKit execution, native-account
change or publication occurred. Mocked success is not a successful real release.
The strict failures remain failures; both renderer failures remain unresolved.
Historical native receipts are not retargeted. Whole-issue closure and all other
acceptance criteria remain subject to their original requirements. After merge,
update only the three evidence-handling rows, and reassess all live issues after
each update before closing any whole issue.
