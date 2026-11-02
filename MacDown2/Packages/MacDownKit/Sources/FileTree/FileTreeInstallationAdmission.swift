import CoreFoundation
import Foundation
import JSONSupport

public enum FileTreeInstallationAdmission {
    public static func admits(_ domain: [String: Any]) -> Bool {
        if let raw = domain["fileTree.filter"] {
            guard let data = raw as? Data, let fields = fields(data),
                  Set(fields.keys) == ["showsHiddenFiles", "supportedFilesOnly", "foldersFirst"],
                  (try? JSONDecoder().decode(FileTreeFilter.self, from: data)) != nil else { return false }
        }
        if let raw = domain["fileTree.opensOnSingleClick"] {
            guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        }
        for key in ["fileTree.recentRoots", "fileTree.recentFiles"] {
            guard let raw = domain[key] else { continue }
            guard let records = raw as? [Data], records.count <= 2048 else { return false }
            guard admitsRecords(records) else { return false }
        }
        return true
    }

    private static func admitsRecords(_ records: [Data]) -> Bool {
        for data in records {
            guard data.count <= 1_048_576 else { return false }
            // Legacy binary bookmarks remain opaque. Future structured
            // records may not silently lose members on a stale refresh.
            if let object = fields(data) {
                guard Set(object.keys).isSubset(of: ["bookmark", "lexicalURL", "fingerprint"]),
                      case .string = object["bookmark"]?.value,
                      case let .string(path) = object["lexicalURL"]?.value,
                      URL(string: path)?.isFileURL == true else { return false }
                if let fingerprint = object["fingerprint"], case let .object(members) = fingerprint.value {
                    guard Set(members.map(\.key)).isSubset(of: ["inode", "created"]) else { return false }
                }
            }
        }
        return true
    }

    private static func fields(_ data: Data) -> [String: JSONNode]? {
        guard let text = String(data: data, encoding: .utf8), case let .valid(node) = JSONParser.parse(text),
              case let .object(members) = node.value else { return nil }
        return Dictionary(uniqueKeysWithValues: members.map { ($0.key, $0.value) })
    }
}
