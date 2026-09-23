import Foundation
import IOKit

enum SensorError: Error, Equatable {
    /// This Mac has no such sensor. Nothing the user can do.
    case notPresent
    /// The sensor exists but macOS withheld it pending Input Monitoring.
    case permissionDenied
    case openFailed(IOReturn)

    var userMessage: String {
        switch self {
        case .notPresent:
            "This Mac doesn't have this sensor."
        case .permissionDenied:
            "Needs Input Monitoring permission."
        case .openFailed(let code):
            "Couldn't open the sensor (IOReturn \(String(code, radix: 16)))."
        }
    }

    /// Distinguishes a TCC refusal from a genuine failure so the UI can offer
    /// the Settings shortcut only when it would actually help.
    static func from(open result: IOReturn) -> SensorError {
        switch result {
        case kIOReturnNotPermitted, kIOReturnNotPrivileged, kIOReturnNotOpen:
            .permissionDenied
        default:
            .openFailed(result)
        }
    }
}
