import Foundation
import IOKit.hid

struct MotionSample: Sendable {
    var x: Double
    var y: Double
    var z: Double
    var timestamp: TimeInterval
}

/// Accelerometer exposed by `AppleSPUHIDDevice` on Apple Silicon MacBooks
/// (Bosch BMI286).
///
/// Verified on Mac16,12: vendor `0x05AC`, product `0x8104`, primary usage page
/// `0xFF00`, usage `3`. Usage `9` on the same device is the gyroscope, in the
/// same format. Reports are 22 bytes carrying three little-endian `int32` axes
/// at byte offsets 6, 10 and 14, in Q16 fixed point: divide by 65536 for g.
///
/// The device carries `motionRestrictedService = Yes`, so opening it requires
/// Input Monitoring.
final class MotionSensor {
    private enum HID {
        static let vendorApple = 0x05AC
        static let productSPU = 0x8104
        static let usagePageVendor = 0xFF00
        static let usageAccelerometer = 3
        static let reportLength = 22
        static let axisOffsets = (x: 6, y: 10, z: 14)
        /// Q16 fixed point.
        static let scale = 65536.0
    }

    private var device: IOHIDDevice?
    /// Roomier than the 22 bytes this device sends, so a longer report from
    /// some other model is truncated rather than overrunning.
    private var buffer = [UInt8](repeating: 0, count: 4096)
    private var handler: ((MotionSample) -> Void)?

    private static func copyDevice() -> IOHIDDevice? {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: HID.vendorApple,
            kIOHIDProductIDKey: HID.productSPU,
            kIOHIDPrimaryUsagePageKey: HID.usagePageVendor,
            kIOHIDPrimaryUsageKey: HID.usageAccelerometer,
        ]
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }
        return devices.first
    }

    static func isPresent() -> Bool { copyDevice() != nil }

    func start(onSample: @escaping (MotionSample) -> Void) throws {
        guard let device = Self.copyDevice() else { throw SensorError.notPresent }
        stop()
        SPUSensors.wake()

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw SensorError.from(open: result) }

        handler = onSample
        self.device = device

        let context = Unmanaged.passUnretained(self).toOpaque()
        buffer.withUnsafeMutableBufferPointer { raw in
            IOHIDDeviceRegisterInputReportCallback(
                device,
                raw.baseAddress!,
                raw.count,
                Self.reportCallback,
                context
            )
        }
        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    func stop() {
        guard let device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil
        handler = nil
    }

    deinit { stop() }

    private static let reportCallback: IOHIDReportCallback = {
        context,
        _,
        _,
        _,
        _,
        report,
        length in
        guard let context, length >= HID.reportLength else { return }
        let sensor = Unmanaged<MotionSensor>.fromOpaque(context).takeUnretainedValue()
        sensor.handler?(decode(report))
    }

    private static func decode(_ report: UnsafeMutablePointer<UInt8>) -> MotionSample {
        func axis(at offset: Int) -> Double {
            var raw: Int32 = 0
            withUnsafeMutableBytes(of: &raw) { destination in
                destination.copyBytes(
                    from: UnsafeRawBufferPointer(start: report + offset, count: 4)
                )
            }
            return Double(Int32(littleEndian: raw)) / HID.scale
        }
        return MotionSample(
            x: axis(at: HID.axisOffsets.x),
            y: axis(at: HID.axisOffsets.y),
            z: axis(at: HID.axisOffsets.z),
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }
}
