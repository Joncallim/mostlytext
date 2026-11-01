# Theme management implementation evidence — 1 November 2026

Source: ce7750aa2e3d8a80eb3a9d17d6decc8e588dcc5c, including native management integration 16d9f6fe and the extended-ACL correction. This evidence commit changes documentation only.

- 202 selected package tests in 25 suites passed, including bootstrap, real ACL controls, observation, last-known-good storage, import decisions, preferences, palette/preview/export and decoding.
- 156 optimized tests in 19 suites passed in a standalone command-line control containing unmodified Themes sources/tests and app model/export sources/tests. It does not construct AppDelegate or start NSApplication and does not prove native panels or full app acceptance. The 10 app-model/export functions cover confirmed/stale/cancelled operations, selection fallback, shutdown and immutable bytes.
- Archived locked Release app and CLI builds, Debug build-for-testing and pin checks passed. The complete tracked archive matches every Git blob at the named source; test input SHA-256 values match that same archive. All inputs remained unchanged.
- Both initial ACL controls failed before correction: mode 0700 alone admitted a granting ACL, and a later grant did not invalidate the held root. The corrected empty/deny-only policy refuses those grants and accepts deny-only protection. Existing ACLs are never edited by production code. Tests alter only owned disposable fixtures.
- Compile diagnostics have the same 31 distinct warning messages as the earlier Appearance build; no warning suppression was introduced. Dependency-scan warnings and the existing test warnings remain recorded in the complete logs.
- Xcode build-product registrations are removed for these exact URLs after verification; the cleanup receipt is retained. No global registry reset or application launch occurred.

The required CORTANA GUI import/copy/replace/export/Cancel/delete/reveal, all-theme switching, keyboard/VoiceOver/layout and exact signed-candidate tests are NOT_RUN. Independent review remains pending. E17 identity/state migration, Quick Look runtime/provider and wider #113/#115/#148 criteria remain open. Translation drafts are not native-speaker approval. No source archive or binary is published.

JSON receipts record full commands and environment paths. Gzip logs are complete, not tail excerpts. source-manifest.json.gz records the SHA-256 of every tracked source/archive file and confirms Git-blob identity. The standalone control is supplemental; the application and test targets were separately compiled from the exact full archive.

Current source-tree compliance passes with zero unverified items; 92 compliance fixtures pass. Release compliance still reports the same six source-offer/attribution failures, retained in release-compliance.log. No failure is waived. Full-tree strict lint and formatting pass.
