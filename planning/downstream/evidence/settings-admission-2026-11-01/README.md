# Settings admission implementation evidence — 1 November 2026

Source: 81f34378e603a8256031bd82491125793366d95a on integration 9de81f5f. Only the eight existing settings commits were reconciled from the older mixed worktree; unrelated renderer/export/save changes were excluded. This evidence commit changes documentation only.

- 84 selected settings tests in 14 suites passed on CORTANA using synthetic data and unique disposable preference suites. AppSettings source/test hashes remained unchanged and match the build archive.
- The initial precision regression reproduced two failures: fractional raw versions rounded to supported version 1. The first combined run then exposed four expectations in a historical test that explicitly accommodated Foundation rounding. The documented new raw-admission contract strengthens preservation and replaces that accommodation with assertions that ordinary saves retain original primary bytes.
- Normal startup/save protection and future import evidence now use strict editor admission. All five domains use bounded strict raw JSON and exact version classification before Foundation conversion. Existing false/default-equal values and compatible historical status-bar defaults remain covered.
- Archived locked Release app/CLI builds, Debug test-target compilation and package-pin checks passed. Every tracked archive file matches its Git blob at the named source, and all original source bytes remained unchanged.
- Build-generated registrations are removed for the exact new app URLs after checks. No application launched and no real legacy preference domain was accessed.

This does not activate legacy import or complete #53. Three verified Boolean mappings and read-only plans are implemented; remaining font/theme mappings, explicit consent, serialized journal/read-back/recovery, E17 bootstrap and native migration are still required. Independent review of the startup integration and raw helper remains pending. No multi-key transaction, native acceptance or release approval is claimed.

Full gzip logs and JSON receipts preserve commands and results. source-manifest.json.gz binds the complete archive to the commit and records each file SHA-256. Historical evidence from 25 October remains historical; this directory supplies the current-source checks.
