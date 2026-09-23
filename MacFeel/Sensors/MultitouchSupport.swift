import Foundation

/// Reads the one field of the framework's touch struct this app needs.
///
/// Fields are read at fixed byte offsets rather than through a mirrored Swift
/// struct: Swift makes no layout guarantee, and `@convention(c)` will not accept
/// a Swift struct in the callback signature anyway.
enum MTTouch {
    /// Byte stride of the framework's touch struct.
    static let stride = 96
    /// Force on the pad, already expressed in grams by the framework. Older
    /// reverse-engineered headers label this slot `int zero1` and skip it; it is
    /// a float, and it is what a scale should read.
    private static let pressureOffset = 52

    static func pressure(at base: UnsafeRawPointer) -> Double {
        Double(base.loadUnaligned(fromByteOffset: pressureOffset, as: Float.self))
    }
}

/// Runtime binding to `MultitouchSupport.framework`.
///
/// Resolved with `dlopen`/`dlsym` rather than linked, so a future macOS that
/// moves or drops this private framework degrades to "trackpad unavailable"
/// instead of refusing to launch the app.
final class MultitouchSupport: @unchecked Sendable {
    typealias DeviceRef = UnsafeMutableRawPointer
    /// Touches arrive as a raw buffer; see `MTTouch.stride`.
    typealias ContactCallback =
        @convention(c) (DeviceRef?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32

    static let shared = MultitouchSupport()

    private let createDefault: (@convention(c) () -> DeviceRef?)?
    private let registerContactCallback: (@convention(c) (DeviceRef, ContactCallback) -> Void)?
    private let deviceStart: (@convention(c) (DeviceRef, Int32) -> Void)?
    private let deviceStop: (@convention(c) (DeviceRef) -> Void)?

    private init() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        let handle = dlopen(path, RTLD_LAZY)

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        createDefault = symbol("MTDeviceCreateDefault", as: (@convention(c) () -> DeviceRef?).self)
        registerContactCallback = symbol(
            "MTRegisterContactFrameCallback",
            as: (@convention(c) (DeviceRef, ContactCallback) -> Void).self
        )
        deviceStart = symbol("MTDeviceStart", as: (@convention(c) (DeviceRef, Int32) -> Void).self)
        deviceStop = symbol("MTDeviceStop", as: (@convention(c) (DeviceRef) -> Void).self)
    }

    var isAvailable: Bool {
        createDefault != nil && registerContactCallback != nil
            && deviceStart != nil && deviceStop != nil
    }

    func makeDefaultDevice() -> DeviceRef? { createDefault?() }

    func register(_ device: DeviceRef, callback: ContactCallback) {
        registerContactCallback?(device, callback)
    }

    func start(_ device: DeviceRef) { deviceStart?(device, 0) }

    func stop(_ device: DeviceRef) { deviceStop?(device) }
}
