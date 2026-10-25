# Phase 1 marketing review notes

## Technical post

The review branch adds the technical post at
`/blog/rebuilding-macdown-native-mac-app/`, prerendered alongside the existing
home and roadmap pages. It deliberately includes no video, GIF, image
placeholder, or invented asset URL.

Before publishing or promoting the post, provide the approved recording asset
and its final alt text. Its caption must say:

> Demo: private development build 9f360cfa, still named MacDown 2. This is not
> the public alpha tag or a signed release.

The recording must not be described as `v0.1.0-alpha.1`, a signed binary, or a
1.0 release. The post itself makes no benchmark or superiority claim.

## Release follow action

The existing release follow action remains the repository’s GitHub control:
**Watch → Custom → Releases**. It is described in the post without adding an
unverified subscription endpoint or a duplicate call to action.

## Analytics disclosure

The footer adds a concise disclosure for the existing Cloudflare Web Analytics
configuration. No beacon, script, Worker setting, DNS record, credential, or
Cloudflare configuration is included or changed by this branch.
