import Foundation

/// One frame from the trackpad, already reduced to what the scale needs.
///
/// Summarised in the callback rather than handed over as a list of contacts,
/// because that callback runs on every frame and nothing downstream ever looks
/// at an individual finger.
struct TrackpadFrame: Sendable {
    var contactCount: Int
    /// Combined force of every contact, in grams.
    var grams: Double
}

/// Streams force off the built-in Force Touch trackpad.
///
/// MultitouchSupport contact callbacks are plain C function pointers with no
/// context parameter, so the running sensor is parked in a global the trampoline
/// reads. Only one sensor is ever started at a time.
@MainActor
final class TrackpadForceSensor {
    private var device: MultitouchSupport.DeviceRef?
    private var handler: ((TrackpadFrame) -> Void)?

    static func isPresent() -> Bool {
        guard MultitouchSupport.shared.isAvailable else { return false }
        return MultitouchSupport.shared.makeDefaultDevice() != nil
    }

    func start(onFrame: @escaping (TrackpadFrame) -> Void) throws {
        guard MultitouchSupport.shared.isAvailable,
            let device = MultitouchSupport.shared.makeDefaultDevice()
        else { throw SensorError.notPresent }

        stop()
        handler = onFrame
        self.device = device
        activeSensor = self

        MultitouchSupport.shared.register(device, callback: contactTrampoline)
        MultitouchSupport.shared.start(device)
    }

    func stop() {
        if let device {
            MultitouchSupport.shared.stop(device)
        }
        device = nil
        handler = nil
        if activeSensor === self { activeSensor = nil }
    }

    fileprivate func deliver(_ frame: TrackpadFrame) {
        handler?(frame)
    }
}

/// Written and read only from the main actor; the C trampoline hops there before
/// touching it.
private nonisolated(unsafe) weak var activeSensor: TrackpadForceSensor?

private let contactTrampoline: MultitouchSupport.ContactCallback = { _, touches, count, _, _ in
    // A frame with no touches is the lift-off signal and must be delivered, not
    // skipped. Dropping it leaves the last reading frozen on screen.
    var grams = 0.0
    if let touches, count > 0 {
        for index in 0..<Int(count) {
            grams += MTTouch.pressure(at: touches.advanced(by: index * MTTouch.stride))
        }
    }

    let frame = TrackpadFrame(contactCount: Int(max(0, count)), grams: grams)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            activeSensor?.deliver(frame)
        }
    }
    return 0
}
