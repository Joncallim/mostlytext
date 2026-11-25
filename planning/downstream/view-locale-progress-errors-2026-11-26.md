# Present progress and recovery copy in the selected view language

## Owner summary

Export progress, the folder-operation alert and the encoding-loss warning were
catalogued, but each became a plain `String` before SwiftUI could apply the
presenting view's locale. A window displayed in another language could therefore
show these messages in the system language. The three owning views now pass
their selected locale when resolving existing catalog text. The file operation,
export phase and encoding-safety behavior is unchanged.

This change starts from `main` `ae829949fef5b83ac4eadf9b1620fe683c6faa36`.

## Source and behavior

- `ContentAreaView` resolves its export phase and unrepresentable-text warning
  with its environment locale. `ExportPhase` keeps the current-locale property
  for existing non-view consumers; the view uses a locale-taking method.
- `SidebarView` resolves typed `FileTreeOperationError` messages with its
  environment locale. An underlying OS or authored error detail remains
  verbatim, as before. The unknown-error fallback uses the same view locale.
- `WorkspaceError` retains its existing `LocalizedError` fallback and exposes
  the specific encoding-loss copy to the view with an explicit locale.
- The test supplies a disposable French resource bundle with deliberately
  distinct values for the three routes, checks the selected locale and an
  unchanged underlying detail, and leaves all production catalog keys intact.

This is a source-level language-routing fix. The issue #3 full string audit,
translation quality, pseudo-localization layout, native non-English app journey
and final post-#8 string freeze remain open. The protected installed-app
checkpoint is deferred.
