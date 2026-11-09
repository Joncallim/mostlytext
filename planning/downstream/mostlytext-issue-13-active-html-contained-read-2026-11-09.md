# Issue #13: contain active HTML preview resource reads

## Owner summary

Saved HTML previews can show nearby images, styles and other local files. The
active preview checked a resource path and then opened that path separately. A
file replacement between those steps could make the app read a different file.
This change keeps the same preview and automatic document-directory behavior,
but pins the directory when the saved preview loads and reads each resource
through that pinned directory. A resource that escapes the directory or changes
into a symlink during admission is refused.

This is a containment correction for the active HTML preview. It does not
activate the separate explicit-grant preview host, change the editor's saved
revision behavior, or claim the remaining off-main, resource-budget, native
WebKit and final Release acceptance criteria.

## Baseline and authority

Baseline: MostlyText `main` `45fba1d15c13c80a9bc6e7d50d2226a243f0b671`.
`HTMLPreviewPane` uses `HTMLPreviewView`, which installs `PreviewSchemeHandler`
for each clean saved generation. `PreviewSchemeHandler` previously used
`HTMLPreviewResourceScope.approvedFileURL` followed by `Data(contentsOf:)`.
The prepared `SecuredHTMLPreviewView` needs an explicit folder grant and is not
the shipping HTML pane. Switching to it here would change resource access
and saved-preview behavior, so this slice leaves that path alone.

The existing app dependency `LocalResourceAccess` supplies `DirectoryLease`,
`ResourceReference` and `ContainedResourceReader`. The handler now opens a
directory lease when it installs a saved load. It parses the scheme URL's
percent-encoded path once, then reads through the lease with a constrained
`openat` operation. The returned immutable snapshot supplies both data and the
resolved target name for MIME selection. Legitimate in-root symlinks continue
to resolve to their in-root targets. A missing or moved root, escaped path,
non-regular file or unsupported kernel containment fails the resource request;
the saved main HTML can still render. Replacing or retiring a load closes its
lease and revokes its pending scheme-task callbacks.

## Verification and limits

Focused controls exercise the active scheme handler with an in-root symlink,
an outside symlink replacement after path selection, exact one-pass percent
decoding and resource-response revocation. The descriptor reader's controlled
pre-open tests cover a leaf changed to an outside symlink and a directory
component changed during resolution, so the opened object rather than only a
prior path check determines admission. Existing Preview and app tests, a
locked package selection, app test compilation and strict style checks are the
source validation path. No product UI is launched on the owner desktop.

The locked Release `ContainedResourceReaderTests` selection passes 36 tests
in two suites, including the existing controlled pre-open outside-symlink and
root-rename cases. The new active-handler app test cases compile in a pinned
`build-for-testing`; they have not run on this owner desktop because they
instantiate WebKit and need hosted/test-account execution. SwiftFormat and
strict SwiftLint pass for every changed Swift file.

This slice intentionally retains the active handler's synchronous read and
existing resource-size behavior (`maxBytes: Int.max`; no new size ceiling).
Issue #13's bounded/off-main read policy,
explicit folder-grant consumer activation, real WebKit corpus and final
Release-app dogfood remain separate open work.
