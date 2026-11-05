# Reconcile audit ownership and release-gate evidence

The release owner needs three evidence-handling criteria resolved without
mistaking source integration for native or release acceptance. Verify the
existing compliance failure path, delegated finding ownership and gate-consumer
rules, then attach exact evidence to the corresponding issue rows.

## Baseline and scope

Main is `a33662d92dd401c163513d17e8809093c6e30e5d`. MostlyText #8 owns the
carried-forward debt gate, #14 owns compliance, #4 owns distribution and #17
owns the merged-code audit. The transfer map resolves older numbers; closed
historical issues and native receipts retain their original repositories and
source identities. Current live state is 17 open issues / 182 unchecked rows.

Only documentation and evidence records change. No product, release-script,
validator, package, normal CI, attribution inventory or native-receipt changes.
Do not close an owning issue or remove an incomplete acceptance requirement.

## Verification slices

1. Execute the existing release-script behavioral suite with stub Apple tools
   and an owned temporary repository. Confirm a failing compliance check is
   fatal before notary submission in release-candidate mode, while dry-run
   tolerance is explicitly unverified. Do not execute real signing or notary
   tools. Independently retain the real six strict source-gate failures.
2. Read current #11/#13/#3 delegation records and #8/#4 consumers. Fetch original
   #159/#163/#173/#174 statuses without changing their closure records. Keep the
   open #15 WebKit diagnosis open. Record evidence links and hashes; delegation
   is ownership, not proof that the delegated work passed.
3. Execute the existing readiness validator/self-tests normally and optimized.
   Its architecture-only result must retain `not_run`, the native/artifact
   dependencies and separate public authorization. A green validator or CI
   cannot become an application or issue-closure pass.

Run ordinary Compliance/inventory and final-head hosted Compliance for the
resulting documentation PR. Record exact file hashes, commands and outcomes.
Merge only after checks/review, verify actual parents/tree and clean canonical
main, then update exactly the three issue criteria with immutable evidence.
Immediately reread all open issues and reassess whole-issue closure after each
issue update. Reconcile the engineering remainder count only after live checks.

## Limits and continuation

This verifies the existing policy and mocked command control flow. It neither
adds a GitHub issue-state enforcement service nor proves real signing, native
UI, installed migration, source publication or final artifact compliance.
Historical source identities remain historical. All other issue rows, strict
release failures, both renderer failures and the current-account native hold
remain intact. Continue independent engineering only where its actual source
interfaces and test prerequisites permit it.
