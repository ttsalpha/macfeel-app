import Foundation

/// What this particular Mac can actually do. Every panel is gated on this, and
/// the UI distinguishes "your Mac lacks the hardware" from "the hardware is
/// there but locked behind a permission". Those need different affordances.
struct Capabilities: Sendable {
    var lidAngle = false
    var motion = false
    var trackpadForce = false
    var ambientLight = false

    var hasNoSensors: Bool { !lidAngle && !motion && !trackpadForce && !ambientLight }

    @MainActor
    static func probe() -> Capabilities {
        Capabilities(
            lidAngle: LidAngleSensor.isPresent(),
            motion: MotionSensor.isPresent(),
            trackpadForce: TrackpadForceSensor.isPresent(),
            ambientLight: AmbientLightSensor.isPresent()
        )
    }
}
