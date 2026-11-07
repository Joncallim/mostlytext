# Actual current-domain Foundation counterexample

A standalone Swift6 Foundation-only console carries a unique real bundle
identifier through its embedded Info.plist. No owner app, AppKit/SwiftUI/WebKit
code, preferences read/write or GUI launch occurs. The actual old
UserDefaults(suiteName: own identifier) returns nil and Foundation emits its
explicit refusal. Standard defaults is available for the same current identity;
a different owned suite is also available. The executable digest and successful
bounded exit are retained. Source, embedded identity and exact linkage output
are included. This isolates the documented API error; it does not qualify the
production store, app startup or CLI. Hosted app/native checks remain required.

Compile with Swift6, embedding Info.plist using linker -sectcreate __TEXT
__info_plist. Inspect otool -L before execution and refuse GUI libraries. Run
only this console with the exact identity.txt argument, finite10s deadline,
retaining separate stdout/stderr and unchanged binary hash.

Apple's constructor contract:
https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:)
