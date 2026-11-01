# Recent-file opening completion

## Owner summary

Keep the Open Recent File behavior unchanged while making its completion
observable. Tests must inspect the completed open and recent-file update,
rather than assuming a background file read completes within three seconds.
Close every controller created by each test so its windows cannot leak into
later tests.

## Baseline and observed failure

Master is `15c0fae22f7618e94c82681227057c66011be2a9`; this correction starts
from integration `9de81f5ff5222138a210472f2def33de01df6c8c`.
Settings PR #545 CI run 41268166342 passed the package and build stages but
failed two assertions in `openingAnOrdinaryRecentFileOpensItAndRePromotesIt`.
The app run executed 515 tests in 105 suites. The last controller had no
document and the recents list still began with b.md. This does not establish
a settings failure or prove that the underlying open eventually succeeded.

The current test polls controller count for three seconds and proceeds even
after that deadline expires. It then treats the last controller as the newly
opened document. Its original placeholder controller is never closed.

## Implementation contract

Return the existing `Task<Void, Never>` from `openRecentFile`, marked
`@discardableResult`. A missing resolution returns nil immediately. Menu
callers continue to discard the result; the task uses the existing lexical URL,
document-open serialization and recent-file publication paths. No file-opening
authority, persistence, encoding or document-lifetime behavior changes.

Both app-target recent-file tests require the returned task and await its
value before checking controller count, document identity and recency. Keep
the original assertions and close all controllers in a defer block before
removing their fixtures. No longer sleep or silently pass a timeout boundary.

## Verification and limits

Source formatting and strict lint pass. Compile the app and app tests with
locked dependencies. Execute the existing tests and full app-target suite on
the disposable hosted runner. Local application execution remains held by #88;
build-for-testing alone is not execution evidence. This correction does not
close #112, #183 or #115, and a later green run does not erase the failure above.
