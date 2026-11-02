import CoreFoundation
import Foundation
import JSONSupport

/// Persists window-level workspace UI state (sidebar visibility, section expansion).
///
/// This is intentionally separate from user preferences (`AppSettings`, E13):
/// sidebar visibility is window state, not a user setting.
///
/// All implementations are accessed from the `@MainActor`-isolated `WorkspaceModel`.
@MainActor
public protocol WorkspaceStateStoring {
    var sidebarVisible: Bool { get set }
    var sidebarSectionExpanded: [String: Bool] { get set }
    var sidebarSectionOrder: [String] { get set }
}

/// UserDefaults-backed `WorkspaceStateStoring` implementation.
///
/// State is conceptually window-level, but because the backing store is a
/// shared `UserDefaults` suite it is shared across all windows in the same
/// process (last writer wins).
@MainActor
public struct WorkspaceStateStore: WorkspaceStateStoring {
    public static let defaultSuiteName = "com.joncallim.macdown2.workspace"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.defaultSuiteName) ?? UserDefaults.standard
    }

    public static func admitsInstallationPreferences(_ domain: [String: Any]) -> Bool {
        if let raw = domain[Keys.sidebarVisible] {
            guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        }
        for key in [Keys.sidebarSectionExpanded, Keys.sidebarSectionOrder] {
            guard let raw = domain[key] else { continue }
            guard let data = raw as? Data, data.count <= 1_048_576,
                  let text = String(data: data, encoding: .utf8),
                  case .valid = JSONParser.parse(text) else { return false }
            if key == Keys.sidebarSectionExpanded {
                guard (try? JSONDecoder().decode([String: Bool].self, from: data)) != nil else { return false }
            } else {
                guard (try? JSONDecoder().decode([String].self, from: data)) != nil else { return false }
            }
        }
        return true
    }

    public var sidebarVisible: Bool {
        get {
            // Default to visible on first launch, and also if a non-boolean
            // value somehow got stored (`bool(forKey:)` would silently coerce
            // that to `false` and hide the sidebar).
            if let value = defaults.object(forKey: Keys.sidebarVisible) as? Bool {
                return value
            }
            return true
        }
        set {
            defaults.set(newValue, forKey: Keys.sidebarVisible)
        }
    }

    public var sidebarSectionExpanded: [String: Bool] {
        get {
            guard let data = defaults.data(forKey: Keys.sidebarSectionExpanded),
                  let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
            else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.sidebarSectionExpanded)
            }
        }
    }

    public var sidebarSectionOrder: [String] {
        get {
            guard let data = defaults.data(forKey: Keys.sidebarSectionOrder),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.sidebarSectionOrder)
            }
        }
    }

    private enum Keys {
        static let sidebarVisible = "sidebarVisible"
        static let sidebarSectionExpanded = "sidebarSectionExpanded"
        static let sidebarSectionOrder = "sidebarSectionOrder"
    }
}
