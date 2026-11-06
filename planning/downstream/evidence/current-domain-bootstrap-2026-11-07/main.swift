import Foundation
let expected = CommandLine.arguments[1]
guard Bundle.main.bundleIdentifier == expected else { fatalError("Fixture bundle identity unavailable") }
let old = UserDefaults(suiteName: expected)
let corrected = expected == Bundle.main.bundleIdentifier ? UserDefaults.standard : UserDefaults(suiteName: expected)
let unrelated = UserDefaults(suiteName: expected + ".separate")
let record: [String: Any] = ["identity": expected,
 "actual_bundle_identifier": Bundle.main.bundleIdentifier!,
 "old_current_domain_suite_available": old != nil,
 "corrected_is_standard": corrected === UserDefaults.standard,
 "unrelated_suite_available": unrelated != nil,
 "scope": "Foundation console only; no application launch or preference read/write"]
let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
print(String(decoding: bytes, as: UTF8.self))
guard old == nil, corrected === UserDefaults.standard, unrelated != nil else { fatalError("Platform counterexample not demonstrated") }
