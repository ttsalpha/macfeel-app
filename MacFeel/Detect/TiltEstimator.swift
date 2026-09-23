import Foundation

/// Turns raw accelerometer samples into a stable tilt reading.
///
/// A level wants the opposite of what slap detection wants. `ImpactDetector`
/// high-passes the signal to throw gravity away and keep the transients; here
/// gravity *is* the measurement, so each axis is collected over the publish
/// window and reduced to its median, and every bump is what gets discarded.
struct TiltEstimator {
    struct Tilt: Sendable, Equatable {
        /// Degrees the left and right edges differ by. Positive tips right.
        let roll: Double
        /// Degrees the near and far edges differ by. Positive tips away.
        let pitch: Double

        /// Total tilt off horizontal, for the bubble's distance from centre.
        var magnitude: Double { (roll * roll + pitch * pitch).squareRoot() }
    }

    private var x = MedianWindow()
    private var y = MedianWindow()
    private var z = MedianWindow()

    mutating func append(_ sample: MotionSample) {
        x.append(sample.x)
        y.append(sample.y)
        z.append(sample.z)
    }

    /// Nil when no samples arrived, which the caller should read as "no news"
    /// rather than "flat".
    mutating func drain() -> Tilt? {
        guard let gx = x.drain(), let gy = y.drain(), let gz = z.drain() else { return nil }
        // Resting flat, this Mac reads gravity almost entirely on -Z, so -Z is
        // the reference the other two axes are measured against.
        let vertical = -gz
        return Tilt(
            roll: atan2(gx, vertical) * 180 / .pi,
            pitch: atan2(gy, vertical) * 180 / .pi
        )
    }

    mutating func reset() {
        x.reset()
        y.reset()
        z.reset()
    }
}
