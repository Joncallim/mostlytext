# Avoid unnecessary full-line scans during editing assists

## Owner outcome and baseline

Ordinary Markdown editing must meet the existing 50 ms adapter and 200 ms huge
whitespace-line gates. Two full Intel macOS 26 runs at unchanged EditorCore
source failed both: handled 1 MiB assist took 56.26 / 53.91 ms, and 2 MiB Smart
Home exceeded 200 ms. No ceiling or assertion is changed. Master is 87d8d48b;
EditorCore's classifier is unchanged in the pending combined source.

Source inspection shows every fence classification first scans an entire first
line even when its first three units cannot be a front-matter opener. It also
scans each candidate line to its end before checking whether its first four
columns can contain a fence. A multi-megabyte plain line therefore gets redundant
forward traversals, and ordinary short lines pay a needless second traversal.

## Narrow architecture

Keep the exact UTF-16 line helpers, ASCII space/tab and CR/LF rules, 5,000-line
fence and 1,000-line front-matter caps, simplified fence toggle grammar, info
string semantics and runtime profile choices. Check the exact three-dash prefix
before discovering the first line's end. Probe up to three spaces and a real
three-or-more backtick/tilde run before discovering the rest of a fence line.
Only actual delimiter candidates need their full info string. Do not cache
mutable text, change classification, truncate an info string or add dependencies.

Private CharacterSet search prototypes failed existing geometry on malformed
surrogate sequences (3,154 and 432 issues); those failed controls are retained.
A separate literal-search variant passes the generated geometry corpus. Only
the narrower prefix optimization enters production; all line helpers remain
unchanged.
The Foundation-only assist harness uses exact pure engine/line/selection source
plus an explicitly recorded transaction-DTO extraction that excludes all AppKit
owner extensions. It is not full native adapter acceptance. Hosted storage
profiling is separate and does not authorize product execution locally.

## Verification

Compare the final classifier with the exact previous source as an independent
reference over generated marker/space/tab/CR/LF/Unicode/surrogate inputs and every
caret position. Retain the existing pure assist/classifier tests and add long
plain-line, inner-fence and delimiter-prefix controls. Record before/after
complete pure outcomes for representative 1 MiB and 2 MiB fixtures in Debug and
Release. Require the unchanged full hosted suite and adapter budgets before
merge. This is editing-assist cost, not #203 highlighting closure or a native
Release performance/signing qualification.


## Observed source results

The exact prior classifier reference agrees with the changed implementation at
17,376 generated caret positions. All 165 Foundation-only source controls pass
Debug, including existing assist/fence/newline/selection tests, the long-line and
malformed-UTF-16 regressions and explicit profiling/oracle controls. Initial
harness setup errors (missing pure dependencies/import and a type-check-heavy
oracle expression) are retained; the transaction DTO adaptation excludes every
native owner extension. The initial new-test force unwrap was corrected for
strict lint. No AppKit test or product was executed locally.

Debug median whole pure Smart Home cost falls from about 47.70 ms to 23.33 ms
for the exact 2,000,000-unit whitespace fixture. The existing named 1 MB fixture
actually contains 475,008 ASCII units; its pure newline decision falls from
about 3.55 ms to 1.59 ms. Record the actual size: neither number proves a full
1 MiB document or the native adapter's 50 ms budget. That fixture-fidelity debt
remains explicit in #112/#203/#115; no test ceiling or source data is weakened.

The hosted backing-storage getter probe initially used an empty fixture and is
not evidence. The corrected nonempty 1,036,000-unit fixture gives roughly
0.0005 ms for both getters, so no speculative text-storage getter change is
made. The remaining full-suite/adapter gates require hosted execution.

Final Release passes the same 165 source controls/16 suites and all 17,376
reference comparisons. Complete pure outcomes measure about 14.59 ms for the
2,000,000-unit whitespace case and 0.95 ms for the 475,008-unit newline case;
these are fixture observations, not native adapter or full-size acceptance.
The new test's safe buffer-base requirement initially missed its throws marker;
that compile failure is retained and corrected. Strict lint and pinned format
pass. Full hosted execution of the unchanged budgets remains required.
