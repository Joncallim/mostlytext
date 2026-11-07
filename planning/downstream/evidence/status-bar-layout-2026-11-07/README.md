# First status-layout attempt, 7 November 2026

At head `016afa10`, status run [42338085708](https://github.com/Joncallim/mostlytext/actions/runs/42338085708) built the normal Release app and private driver, then refused missing qualified main history before any UI execution. The checkout used depth 1; `git merge-base --is-ancestor 6b49777d… HEAD` returned 128. This is not a geometry failure. Full logs and downloaded artifacts remain in the local evidence archive; compressed actual receipts and independently checked source/input proofs are retained here.

The distinct ordinary public-focus run [42338085657](https://github.com/Joncallim/mostlytext/actions/runs/42338085657) and original named-focus run [42338085693](https://github.com/Joncallim/mostlytext/actions/runs/42338085693) each genuinely passed their positive and selected cases without retries, skips or deadline changes. Their results do not replace the absent geometry case.

Decision before correction: fetch complete history in the new status workflow, preserving the actual-host and qualified-ancestry guard and all source assertions/deadlines. Re-execute the materially corrected workflow and preserve its first result. No product layout repair until an actual geometry failure.
