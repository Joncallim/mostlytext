import Foundation

public extension FileEncodingMetadata {
    /// A short name for menus, the status bar and error messages. Unicode
    /// encodings use their conventional names; the rest use the OS name.
    var displayName: String {
        let base = switch encoding {
        case .utf8: "UTF-8"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        default: String.localizedName(of: encoding)
        }
        return bom == .none ? base : String(localized: "\(base) with BOM", bundle: .module)
    }
}
