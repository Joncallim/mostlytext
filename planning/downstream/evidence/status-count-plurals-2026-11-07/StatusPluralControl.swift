import Darwin
import Foundation

@main
struct StatusPluralControl {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw ControlError.input }
        let root = URL(fileURLWithPath: "/Volumes/Fast SSD/CORTANA-Builds/status-count-plurals-20261107", isDirectory: true)
        let location = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).resolvingSymlinksInPath()
        guard location.deletingLastPathComponent() == root,
              location.pathExtension == "bundle", let bundle = Bundle(url: location)
        else { throw ControlError.input }
        guard bundle.localizedString(forKey: "%lld characters, %lld words",
                                     value: "MISSING_STATUS_PLURAL_RESOURCE", table: "Localizable")
            != "MISSING_STATUS_PLURAL_RESOURCE"
        else { throw ControlError.input }
        var rows: [[String: Any]] = []
        for characters in Int64(0)...Int64(2) {
            for words in Int64(0)...Int64(2) {
                let actual = String(localized: "\(characters) characters, \(words) words",
                                    bundle: bundle, locale: Locale(identifier: "en"))
                let expected = "\(characters) \(characters == 1 ? "character" : "characters"), "
                    + "\(words) \(words == 1 ? "word" : "words")"
                rows.append(["characters": characters, "words": words, "actual": actual,
                             "expected": expected, "passed": actual == expected])
            }
        }
        let failures = rows.filter { $0["passed"] as? Bool == false }.count
        let record: [String: Any] = ["scope": "Actual compiled private English resource resolution through Foundation; no app/native/owner defaults",
                                    "cases": rows, "total": rows.count, "failures": failures]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]))
        FileHandle.standardOutput.write(Data([10]))
        exit(failures == 0 ? 0 : 1)
    }
    enum ControlError: Error { case input }
}
