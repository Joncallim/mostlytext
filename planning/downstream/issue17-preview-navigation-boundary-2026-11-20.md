# Keep Preview link and popup actions within their stated authority

## Owner summary

Clicking a Markdown link should open a local text document in MostlyText,
reveal a local non-document file in Finder, or open an ordinary web/mail link.
An authored `file:` URL with another host or user information must not be
treated as a local document path. Separately, an HTML preview's fragment link
must not bypass the no-popup rule just because it points at the current page.
This change makes those two existing decisions explicit at the shared policy
boundaries. It introduces no network, filesystem or WebKit capability.

## Baseline and controlled failures

The unchanged product baseline is `8436aeca9f54940180ec5acf321050d77717fdd0`.
With only the new tests added, the selected package run failed five assertions:
the HTML policy allowed a same-page popup and allowed a popup when external
navigation was enabled but popup permission was disabled; the Markdown link
resolver returned `openInApp` for three non-local `file:` authorities.
The app's `WKUIDelegate` separately returns `nil` for new web views, so these
policy failures are a defense-in-depth gap, not proof that a popup was shown.
The link action reaches the app document opener or Finder unless rejected.

## Repair and verification

- Popup permission is checked before same-document or external-navigation
  permission. An explicitly permitted popup still obeys the URL scheme rule.
- `file:` links are local-action candidates only when their URL has no remote
  host, user, password or port. Local Markdown/text links and the existing
  executable-file reveal behavior are preserved.
- The final pinned package selection passed 42 tests in five relevant Preview
  suites. Ordinary compliance, changed-file strict lint and formatting, and
  `git diff --check` passed. Hosted exact-head app/package checks remain the
  PR qualification step.

The [first hosted heading-probe run](https://github.com/Joncallim/mostlytext/actions/runs/44711400607)
on PR #315 executed all **69 tests in nine
suites successfully** in Debug and Release, but its verifier still required
the old exact count of 68. This is a count-contract failure caused by the new
`PreviewLinkActionTests` case, not a failed product assertion. The verifier is
updated to require all 69. The corrected head must pass its own hosted checks
before merge.

The compressed logs preserve the first failure and final selected result:

| Log | SHA-256 |
| --- | --- |
| `evidence/issue17-preview-navigation-2026-11-20/baseline-failure.log.gz` | `fc8d58ba68201b1e0f628b0c2fc146b2cfaf146f6a1c892c0c9f14bc8eac9050` |
| `evidence/issue17-preview-navigation-2026-11-20/final-preview-suite.log.gz` | `7d96580aeb5b55e31d5d9bb2502a35db6ea504acea6f2760d22fe9f108db86af` |

This is a scoped #17/#8 Preview review repair. It does not establish the
complete post-E23 whole-repository review, protected native journeys, or the
final candidate's HTML preview acceptance.
