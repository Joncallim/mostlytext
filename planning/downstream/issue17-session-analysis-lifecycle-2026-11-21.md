# JSON and Markdown analysis remain owned until their workers finish

## Owner summary

Closing a tab or window could leave a JSON or Markdown analysis running. Its
late result could publish into the retired session. A separate rapid-edit case
could show the editor as idle while an older analysis still occupied a worker.
This repair invalidates pending analysis when its tab is removed and keeps the
busy state accurate until already-running work drains. Document text and parser
output are unchanged.

## Baseline and controlled failures

- Current-main parent: `7d4970f8d23fc9b3539767e2be9aa24d6a8226fb`.
- Held-worker tests exercise a real `JSONAnalysisStore` session with a
  controlled analyzer. Before the product repair, the focused run failed at
  `supersededDebouncedWorkKeepsTheSessionBusyUntilItDrains` because
  `isAnalyzing` became false while the older worker was held. It also failed
  `evictingATabCancelsItsHeldDebouncedPublication`: the evicted session
  accepted a late result and incremented its completion count.
- The retained failing-before log is
  `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-json-lifecycle-before-20261121.log`,
  SHA-256 `c136ece9f5eed718ab51880456e738ca4aea740cd5f84945d2aa573938a95f19`.
  The test-only store analyzer seam was present in this baseline run; the
  lifetime repair was not.
- The matching `MarkdownParseStore` and `MarkdownParseSession` had the same
  lifetime behavior. With the JSON repair present but before the Markdown
  repair, three new held-engine tests failed with seven assertions: two evicted
  sessions published their late document/text and incremented the completion
  count, and a superseded parse reported idle while its older engine call was
  still held. The retained Markdown baseline log is
  `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-markdown-lifecycle-before-20261121.log`,
  SHA-256 `caf6c6fde69408e77c749136c76478ae1ee8899b63b65ab687de82f1c7ac953b`.

## Repair and scope

- A debounced analysis that has entered its detached worker remains counted
  until its result returns, even if a newer request publishes first. A task
  cancelled after its sleep but before worker admission now skips that work.
- Removing one session or all sessions calls `cancelPending` before releasing
  store ownership. Generation checks prevent a held worker from publishing
  after eviction. The worker itself remains non-preemptible once synchronous
  JSON analysis has begun; its physical work stays observable until it drains.
- The controlled tests also cover `evictAll`, used when a window closes.
  The same admission count and eviction cancellation apply to Markdown parsing.
  This change does not claim a concurrency limit or resolve unrelated editor
  highlighting and protected native acceptance criteria.

## Verification

- Final focused JSON package selection: 106 tests in 13 suites pass in Debug
  and optimized Release. The final Debug log is
  `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-json-lifecycle-final-debug-20261121.log`,
  SHA-256 `8277e59858a1b52194f2edbc9375e0fcac729b3a7153a56d5e84b43341177090`.
  The final Release log is
  `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-json-lifecycle-final-release-20261121.log`,
  SHA-256 `2af8cc4f10764a942088e2b4557ba24d17e6477a3473b590d14a7560d132c45d`.
- The Markdown held-engine suite passes seven tests after the repair. Its
  focused log is
  `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-markdown-lifecycle-fixed-focused-20261121.log`,
  SHA-256 `ec29fea82e8ad30abc84ff9996f823afef1b4e49a0803a589fd6171056f5e441`.
  The final combined JSON/Markdown session selection passes 131 tests in 16
  suites in both Debug and optimized Release. Logs are
  `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-session-lifecycle-final-debug-20261121.log`
  (SHA-256 `59df78b68427efabbcfd06be51dae6689656710bf55ab65554d80c1f01cf7609`)
  and `/Volumes/Fast SSD/CORTANA-Builds/mostlytext-session-lifecycle-final-release-20261121.log`
  (SHA-256 `1595208cfb70c03a4af5a7f2de10667f97e0668e3fd7a6b87a00d8f41057a6ce`).
  Exact-head hosted checks are recorded in the PR/issue update after they finish.
- Changed-source SwiftLint and SwiftFormat, `git diff --check`, and ordinary
  compliance pass. Strict release compliance retains ten existing issue #14
  rights/source-offer failures; this change adds no dependency or resource.
- Exact hosted CI, integrated review and merge identity are recorded after
  the PR completes. The owner-deferred protected native checkpoint stays open.
