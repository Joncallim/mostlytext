import Foundation
import LocalResourceAccess
import Preview

/// Supplies Textual only the bytes admitted for this immutable load. URL parsing is lexical and happens before any
/// filesystem access; an absolute, remote or authority-bearing URL cannot borrow the document's folder grant.
enum PreviewResourceImageProvider {
    static func loader(for context: PreviewResourceLoad?) -> PreviewResourceImageLoader {
        #if DEBUG || RELEASE_PREVIEW_PROBE
            PreviewResourceDiagnostics.record("loader-created", context: context)
        #endif
        guard let context else { return PreviewResourceImageLoader() }
        return PreviewResourceImageLoader(provider: { url in
            #if DEBUG || RELEASE_PREVIEW_PROBE
                PreviewResourceDiagnostics.record("provider-entered", context: context)
            #endif
            guard !context.isRevoked, !Task.isCancelled else { throw PreviewResourceAdmissionError.revoked }
            let authored = url.relativeString
            guard let components = URLComponents(string: authored),
                  components.scheme == nil, components.host == nil,
                  components.user == nil, components.password == nil, components.port == nil
            else { throw ResourceReadError.invalidReference }
            let reference = try ResourceReference.parse(authored)
            let payload: PreviewResourcePayload
            do {
                payload = try await PreviewResourceAdmission.shared.read(reference, in: context)
            } catch {
                #if DEBUG || RELEASE_PREVIEW_PROBE
                    PreviewResourceDiagnostics.record("provider-read-error", context: context,
                                                      detail: String(reflecting: type(of: error)))
                #endif
                throw error
            }
            #if DEBUG || RELEASE_PREVIEW_PROBE
                PreviewResourceDiagnostics.record("provider-read-returned", context: context,
                                                  detail: "bytes=\(payload.snapshot.bytes.count)")
            #endif
            guard !context.isRevoked, !Task.isCancelled else { throw PreviewResourceAdmissionError.revoked }
            return PreviewImageBytes(data: payload.snapshot.bytes, reservation: payload)
        }, isLive: {
            let live = !context.isRevoked
            #if DEBUG || RELEASE_PREVIEW_PROBE
                PreviewResourceDiagnostics.record("loader-is-live", context: context, detail: "result=\(live)")
            #endif
            return live
        }, decodeBudget: context.imageDecodeBudget)
    }
}
