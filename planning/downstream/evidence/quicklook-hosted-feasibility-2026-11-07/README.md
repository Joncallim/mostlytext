# First hosted Quick Look fixture outcome

The actual standalone fixture builds, receives an ad-hoc signature and appears
at its exact hosted path in PlugInKit. The first test command fails before tests:
Xcode interprets NO after a boolean retry switch as an unknown build action.
Owned return65, no timeout/cancel; actual provider log is empty. No Finder test
or provider callback executed and no native acceptance or environment blockade
is inferred. All ten source hashes and unchanged root product tree are checked.
Original metadata, entitlements, hashes and owned command are retained here.
The complete original build/job logs and xcresult remain in the run artifact.
The workflow-only correction removes retry mode and uses test-iterations1;
provider/UI-test/deadlines and all actual positive criteria remain unchanged.
This is not the complete QL-REPLY gate or a production extension.

The second preparation run49802e60 also stops before tests: Xcode requires
test-iterations greater than1. Both actual parser failures are preserved.
An actual local showBuildSettings-only negative reproduces that refusal; the
ordinary command without any retry/repetition flags parses successfully for
the selected container target, and the generated scheme has no repetition mode.
The initial verifier incorrectly expected settings for a dependency target;
it was corrected to the actual selected target. No local native test executed.
The corrected command now uses ordinary single execution without repetition.

The first actual UI test at5edddde4 executes exactly one test and fails its
initial Foundation-home assertion: the observed path is the expected XCUITest
sandbox container. No Finder activation/provider callback occurs. All ten
source inputs and actual owned process/status are verified. The correction
requires the POSIX runner account/home plus the exact observed container path;
it does not disable sandboxing or weaken Finder/visible/cold assertions.
