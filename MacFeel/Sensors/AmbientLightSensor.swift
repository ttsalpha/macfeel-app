import Foundation
import IOKit.hid

/// Ambient light from the `als` SPU sensor.
///
/// Verified on Mac16,12: usage page `0xFF00`, usage `4`. Reports are 122 bytes
/// and carry lux as a little-endian `float32` at byte offset 40, arriving around
/// 10 Hz. Not motion-restricted, so no permission applies.
final class AmbientLightSensor {
    private enum HID {
        static let usagePageVendor = 0xFF00
        static let usageAmbientLight = 4
        static let luxOffset = 40
    }

    private var device: IOHIDDevice?
    private var buffer = [UInt8](repeating: 0, count: 4096)
    private var handler: ((Double) -> Void)?

    private static var matchingDictionary: [String: Any] {
        [
            kIOHIDPrimaryUsagePageKey: HID.usagePageVendor,
            kIOHIDPrimaryUsageKey: HID.usageAmbientLight,
        ]
    }

    private static func copyDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matchingDictionary as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return nil
        }
        return devices.first
    }

    static func isPresent() -> Bool { copyDevice() != nil }

    func start(onLux: @escaping (Double) -> Void) throws {
        guard let device = Self.copyDevice() else { throw SensorError.notPresent }
        stop()
        SPUSensors.wake()

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw SensorError.from(open: result) }

        handler = onLux
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
        guard let context, length >= HID.luxOffset + 4 else { return }
        let sensor = Unmanaged<AmbientLightSensor>.fromOpaque(context).takeUnretainedValue()

        var bits: UInt32 = 0
        withUnsafeMutableBytes(of: &bits) { destination in
            destination.copyBytes(
                from: UnsafeRawBufferPointer(start: report + HID.luxOffset, count: 4)
            )
        }
        sensor.handler?(Double(Float(bitPattern: UInt32(littleEndian: bits))))
    }
}
