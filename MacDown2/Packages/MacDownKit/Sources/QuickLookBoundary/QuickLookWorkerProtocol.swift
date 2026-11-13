import Foundation

/// The same cap is applied by the source renderer, worker process, and XPC
/// consumer. This tiny transport module does not link the export renderer into
/// the app-host test bundle a second time.
public enum QuickLookSourceBudget {
    public static let maximumSourceBytes = 1 << 20
    public static let maximumHTMLBytes = maximumSourceBytes * 6 + 4096
}

/// Private transport between the Quick Look extension and its embedded,
/// sandbox-only worker service. The selected file travels as an open handle;
/// no document path, parent directory or authored markup crosses this seam.
@objc public protocol QuickLookWorkerProtocol {
    func renderSource(_ selectedFile: FileHandle,
                      withReply reply: @escaping (NSData?, NSNumber) -> Void)
}

public enum QuickLookWorkerStatus: Int {
    case complete = 0
    case refused = 1
    case timedOut = 2
    case failed = 3
}
