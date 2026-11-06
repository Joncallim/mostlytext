import Foundation
let prefix = "mt117-svg-"
let value = prefix + "\u{301}x"
print("String prefix:", value.hasPrefix(prefix), "UTF8 prefix:", value.utf8.starts(with: prefix.utf8))
