# Native adapter fixture content ownership

The first bc8da866 Release integration executed all29 functions in9 suites and
failed21 current-parse assertions. Its original full job log and exact source,
pin and owned normal-exit receipts are retained here. They are failures, not
acceptance or a diagnosis of the historical parser assertion.

The direct editor fixture now supplies an empty native content controller at
construction. Production callers retain the original workspace default; the
adapter fixture never mounts a competing SwiftUI parser. All navigation, source,
focus and selection assertions and deadlines remain unchanged. The factory's
default workspace path is retained for the other tests.

The final unsigned Release build-for-testing compiles the actual app, app tests
and UI tests without launching them in the owner account. Strict lint reports
zero violations in1485 files. Earlier source-size lint failures are retained;
no limit or suppression was added. Fresh hosted Debug and Release integration
and normal CI remain required.
