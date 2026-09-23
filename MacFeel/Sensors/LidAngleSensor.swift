import Foundation
import IOKit.hid

/// Hinge angle from the `las` HID sensor on Apple Silicon MacBooks.
///
/// Verified on Mac16,12 (M4 Air, macOS 27): vendor `0x05AC`, primary usage page
/// `0x20` (Sensors), primary usage `0x8A`. The angle arrives on element usage
/// `0x47F`, logical range 0...360, at a 8000µs report interval (125 Hz).
///
/// `motionRestrictedService = No` on this device, so no TCC permission applies.
final class LidAngleSensor {
    private enum HID {
        static let vendorApple = 0x05AC
        static let usagePageSensor = 0x20
        static let usageLidAngle = 0x8A
        static let elementUsageAngle = 0x47F
    }

    private var manager: IOHIDManager?
    private var handler: ((Double) -> Void)?

    static func isPresent() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matchingDictionary() as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return false
        }
        return !devices.isEmpty
    }

    private static func matchingDictionary() -> [String: Any] {
        [
            kIOHIDVendorIDKey: HID.vendorApple,
            kIOHIDPrimaryUsagePageKey: HID.usagePageSensor,
            kIOHIDPrimaryUsageKey: HID.usageLidAngle,
        ]
    }

    func start(onAngle: @escaping (Double) -> Void) throws {
        guard Self.isPresent() else { throw SensorError.notPresent }
        stop()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, Self.matchingDictionary() as CFDictionary)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw SensorError.from(open: result) }

        handler = onAngle
        self.manager = manager

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, Self.valueCallback, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        // The device only reports when the angle changes, so a lid sitting still
        // produces no callback at all and the reading would stay blank until the
        // user happened to move it. Seed from the element's current value.
        if let angle = currentAngle() { onAngle(angle) }
    }

    /// Reads the angle element directly rather than waiting for a report.
    private func currentAngle() -> Double? {
        guard let manager,
            let device = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first,
            let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement],
            let element = elements.first(where: {
                IOHIDElementGetUsagePage($0) == HID.usagePageSensor
                    && IOHIDElementGetUsage($0) == HID.elementUsageAngle
            })
        else { return nil }

        var slot: Unmanaged<IOHIDValue>?
        let result = withUnsafeMutablePointer(to: &slot) { pointer in
            pointer.withMemoryRebound(to: Unmanaged<IOHIDValue>.self, capacity: 1) {
                IOHIDDeviceGetValue(device, element, $0)
            }
        }
        guard result == kIOReturnSuccess, let value = slot?.takeUnretainedValue() else {
            return nil
        }
        return Double(IOHIDValueGetIntegerValue(value))
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        handler = nil
    }

    deinit { stop() }

    private static let valueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == HID.usagePageSensor,
            IOHIDElementGetUsage(element) == HID.elementUsageAngle
        else { return }

        let sensor = Unmanaged<LidAngleSensor>.fromOpaque(context).takeUnretainedValue()
        sensor.handler?(Double(IOHIDValueGetIntegerValue(value)))
    }
}
