import Foundation

/// An exact installed face that the ordinary family-based editor resolver can
/// reproduce. Callers supply observed identities, never a nearest-family guess.
public struct LegacyResolvedFont: Sendable, Equatable {
    public let postScriptName: String
    public let descriptor: FontDescriptor

    public init?(request: LegacyPreferenceReport.FontRequest, installedName: String,
                 installedFamily: String, installedSize: Double,
                 familyResolvedName: String, familyResolvedSize: Double) {
        guard request.postScriptName.utf8.elementsEqual(installedName.utf8),
              installedName.utf8.elementsEqual(familyResolvedName.utf8),
              request.size.isFinite, request.size > 0, request.size <= FontDescriptor.maximumSupportedSize,
              request.size == installedSize, installedSize == familyResolvedSize,
              !installedFamily.isEmpty, installedFamily.utf8.count <= 4096,
              !installedFamily.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        postScriptName = installedName
        descriptor = FontDescriptor(familyName: installedFamily, size: installedSize)
    }

    func matches(_ source: LegacyPreferenceSnapshot) -> Bool {
        LegacyPreferenceReport(snapshot: source).entries.contains {
            guard case let .requiresExactInstalledFont(request) = $0.disposition else { return false }
            return request.postScriptName.utf8.elementsEqual(postScriptName.utf8) && request.size == descriptor.size
        }
    }
}
