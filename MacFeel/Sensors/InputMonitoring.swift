import AppKit
import IOKit.hidsystem

/// Wraps the public Input Monitoring (`kTCCServiceListenEvent`) gate that guards
/// the accelerometer and gyroscope. The lid angle and ambient light sensors are
/// not motion-restricted and never hit this.
enum InputMonitoring {
    enum Status {
        case granted, denied, notDetermined
    }

    static var status: Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .notDetermined
        }
    }

    /// Prompts on first call. Once the user has answered, macOS remembers the
    /// decision and this returns immediately without showing anything.
    @discardableResult
    static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )!
        NSWorkspace.shared.open(url)
    }
}
