# Actual typesetter syntax and diagnostic prerequisite

Can the existing pinned SwiftUIMath parser's structured error codes be used
without SwiftUI/fonts, and does its actual syntax tree honor TeX percent comments
under LF/CRLF/CR? Copy only exact Foundation-only syntax/helpers and original
parser/atom-list tests, replacing the unused outer SwiftUI View namespace with
an empty enum. No font, display provider, renderer or native product executes.
Do not introduce a competing TeX validator or patch a .build checkout.
