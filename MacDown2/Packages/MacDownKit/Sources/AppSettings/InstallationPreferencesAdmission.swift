import Foundation

public extension UserDefaultsAppSettingsStore {
    /// Admission before any whole-install settings model exists. Unknown
    /// standalone keys remain opaque; unreadable known blobs cannot be adopted.
    static func admitsInstallationPreferences(_ bytes: Data?) throws -> Bool {
        guard let domain = try InstallationPreferences.decode(bytes) else { return true }
        for key in Key.allCases {
            guard let object = domain[key.rawValue] else { continue }
            guard let data = object as? Data, key.decodes(data) else { return false }
        }
        return true
    }
}
