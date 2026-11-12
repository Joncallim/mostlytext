import Foundation

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
