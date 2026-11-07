# Line-index capacity reservation: first qualification and actual integration

[PR134](https://github.com/Joncallim/mostlytext/pull/134) merges at actual main
38ccd5d533938c4dbc31f01d9dabbc72025adc71, parents56725f94+6acab2ec. Reviewed source,
tested checkout34c77b5c, computed merge and actual merge share tree0518c29a. The
canonical checkout is clean and fast-forwarded.

The only runtime change reserves the known final line-offset array capacity with
three added lines. Removing them restores exact original bytes. Original scans,
CRLF/Unicode/UTF-16 coordinates, tests/fixtures/delegates/compiler settings, limits,
interfaces, authority and all pins remain unchanged. Tail copying remains linear.

All five first workflows pass. Full CI reports3,719package/536suites and680app/
143suites, allfourlockedbuilds, app/UI compilation, metadata/catalog/finalpins,
zero style violations and no new owned crash reports. Both complete theme
selections report1,087tests/145suites passed, with both original bitmap failures
and both orientation mutant/restoration pairs. The original50ms/10MBline-index
keystroke assertion passes in both configurations. Both strict highlighting
replays and the actual Debug debugger pass, as do six publicCLI comparisons.

Independent readback verifies1,597themeinputs/24pins/148copiedtests perconfiguration,
1,599replayinputs/39copiedtests,1,600CLIinputs and actual raw logs/owned outcomes.
Original opt-in skipped declarations match fc29 exactly and are retained in the
proof; they are not claimed executed. Native theme/replay execution hashes are
worker-recorded, not independent downloaded-binary claims.

Release fullhighlight361.91ms<the unchanged500msfixture bound does not establish
issue18's genuine1MiBwhole-edit50msbudget, constant-time parsing/indexing, the old
Debug abort or a sole explanation of fc29's62.876833msfailure. Preview, final
locale/VoiceOver, signing/installed/owner and exact-artifact gates remain open.
Reader-only inherited Preview counts/display-name errors retain their first
refusals; no native source, timing bound or run is changed/repeated to fix them.
Raw original complete logs/artifacts remain in the engineering archive/GitHub;
compressed records retain their original source identities.
