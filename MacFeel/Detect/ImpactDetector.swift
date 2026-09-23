import Foundation

/// Turns the raw accelerometer stream into discrete "someone hit this Mac" events.
///
/// Structure and constants follow taigrr/apple-silicon-accelerometer, which is
/// tuned against this exact sensor. Three voters run on the same gravity-stripped
/// signal and an event fires when any of them trips: STA/LTA energy ratio, CUSUM
/// drift, and a peak-over-MAD spike test.
///
/// Two choices are worth knowing. STA/LTA runs at three timescales because one
/// window pair can only catch one shape of hit, the short pair seeing a sharp
/// slap and the long pair a slower thump. And each timescale latches on its own
/// on/off thresholds instead of a fixed refractory window, so the trigger arms
/// on a rising edge and stays armed until the ratio falls back, which is what
/// swallows the chassis ring-down.
final class ImpactDetector {
    struct Impact: Sendable {
        /// Dynamic acceleration magnitude in g, gravity removed. A light tap
        /// lands near 0.05, a hard slap above 0.5.
        let force: Double
        let timestamp: TimeInterval
    }

    /// 0 = only hard slaps register, 1 = a firm tap is enough.
    var sensitivity: Double = 0.5

    /// Sweeps from 0.12 g down to 0.01 g, bracketing the light tap either way.
    private var floorG: Double { 0.12 - 0.11 * sensitivity }
    /// Demanding two agreeing voters at low sensitivity is what keeps typing out.
    private var requiredAgreement: Int { sensitivity < 0.35 ? 2 : 1 }
    private let cooldown: TimeInterval = 0.5

    // Per axis, not on the magnitude: rotating the machine redistributes gravity
    // across the axes without changing its total, so high-passing the magnitude
    // would miss tilt entirely and leave it in the signal.
    private let highPassAlpha = 0.95
    private var previousInput = (x: 0.0, y: 0.0, z: 0.0)
    private var previousOutput = (x: 0.0, y: 0.0, z: 0.0)
    private var isPrimed = false

    // STA/LTA at three timescales, as exponential moving averages of energy.
    private var short = Timescale(sta: 3, lta: 100, on: 3.0, off: 1.5)
    private var medium = Timescale(sta: 15, lta: 500, on: 2.5, off: 1.3)
    private var long = Timescale(sta: 50, lta: 2000, on: 2.0, off: 1.2)

    private var cusumMean = 0.0
    private var cusumPositive = 0.0
    private var cusumNegative = 0.0
    private let cusumSlack = 0.0005
    private let cusumLimit = 0.01
    /// How fast the running mean follows the signal. Slow enough that a slap
    /// barely moves it, which is what leaves the slap visible to the sum.
    private let cusumMeanRate = 0.0001

    private static let windowSize = 200
    private var recent = RingBuffer(capacity: ImpactDetector.windowSize)
    /// Reused by `refreshRobustStats` so the sort costs no allocation.
    private var scratch = [Double](repeating: 0, count: ImpactDetector.windowSize)
    private var median = 0.0
    private var deviation = 1e-30
    private var samplesSinceStats = 0
    /// Samples between median refreshes.
    private let statsInterval = 8
    /// How far off the median a sample must land to read as a spike.
    private let peakSigmas = 2.0

    private var lastImpactAt: TimeInterval = -.infinity

    func process(_ sample: MotionSample) -> Impact? {
        guard let magnitude = dynamicMagnitude(of: sample) else { return nil }

        recent.append(magnitude)
        refreshRobustStats()

        var agreement = 0
        if trippedEnergy(magnitude) { agreement += 1 }
        if trippedCusum(magnitude) { agreement += 1 }
        if trippedPeak(magnitude) { agreement += 1 }

        guard agreement >= requiredAgreement,
            magnitude >= floorG,
            sample.timestamp - lastImpactAt > cooldown
        else { return nil }

        lastImpactAt = sample.timestamp
        return Impact(force: magnitude, timestamp: sample.timestamp)
    }

    func reset() {
        isPrimed = false
        previousInput = (0, 0, 0)
        previousOutput = (0, 0, 0)
        short.reset()
        medium.reset()
        long.reset()
        cusumMean = 0
        cusumPositive = 0
        cusumNegative = 0
        recent.removeAll()
        median = 0
        deviation = 1e-30
        samplesSinceStats = 0
        lastImpactAt = -.infinity
    }

    /// First-order IIR high pass on each axis, then the vector magnitude.
    /// Returns nil for the very first sample, which only primes the filter.
    private func dynamicMagnitude(of sample: MotionSample) -> Double? {
        guard isPrimed else {
            previousInput = (sample.x, sample.y, sample.z)
            isPrimed = true
            return nil
        }

        let x = highPassAlpha * (previousOutput.x + sample.x - previousInput.x)
        let y = highPassAlpha * (previousOutput.y + sample.y - previousInput.y)
        let z = highPassAlpha * (previousOutput.z + sample.z - previousInput.z)
        previousInput = (sample.x, sample.y, sample.z)
        previousOutput = (x, y, z)

        return (x * x + y * y + z * z).squareRoot()
    }

    private func trippedEnergy(_ magnitude: Double) -> Bool {
        let energy = magnitude * magnitude
        // Every timescale has to advance even once one of them has tripped, so
        // the three results are taken before they are combined. `||` here would
        // short-circuit and leave the later averages stuck on stale energy.
        let sharp = short.advance(energy: energy)
        let middling = medium.advance(energy: energy)
        let slow = long.advance(energy: energy)
        return sharp || middling || slow
    }

    private func trippedCusum(_ magnitude: Double) -> Bool {
        cusumMean += cusumMeanRate * (magnitude - cusumMean)
        cusumPositive = max(0, cusumPositive + magnitude - cusumMean - cusumSlack)
        cusumNegative = max(0, cusumNegative - magnitude + cusumMean - cusumSlack)

        if cusumPositive > cusumLimit {
            cusumPositive = 0
            return true
        }
        if cusumNegative > cusumLimit {
            cusumNegative = 0
            return true
        }
        return false
    }

    private func trippedPeak(_ magnitude: Double) -> Bool {
        guard recent.isFull else { return false }
        return abs(magnitude - median) / deviation > peakSigmas
    }

    /// The median and spread are refreshed periodically while the comparison
    /// against them runs on every sample, so the spike test stays responsive
    /// without sorting the whole window a hundred times a second.
    private func refreshRobustStats() {
        samplesSinceStats += 1
        guard samplesSinceStats >= statsInterval, recent.isFull else { return }
        samplesSinceStats = 0

        let live = recent.copyUnordered(into: &scratch)
        scratch[..<live].sort()
        median = scratch[live / 2]

        for offset in 0..<live { scratch[offset] = abs(scratch[offset] - median) }
        scratch[..<live].sort()
        // 1.4826 rescales the median absolute deviation to match a standard
        // deviation for normally distributed noise.
        deviation = 1.4826 * scratch[live / 2] + 1e-30
    }
}

/// One STA/LTA pair: a short and a long exponential average of energy, with the
/// latch that arms on a rising ratio and disarms once it falls back.
private struct Timescale {
    private let staWindow: Double
    private let ltaWindow: Double
    private let triggerOn: Double
    private let triggerOff: Double

    private var sta = 0.0
    /// Seeded away from zero so the very first ratio is finite.
    private var lta = 1e-10
    private var armed = false

    init(sta: Double, lta: Double, on: Double, off: Double) {
        staWindow = sta
        ltaWindow = lta
        triggerOn = on
        triggerOff = off
    }

    /// Advances both averages and reports whether this sample armed the latch.
    mutating func advance(energy: Double) -> Bool {
        sta += (energy - sta) / staWindow
        lta += (energy - lta) / ltaWindow
        let ratio = sta / (lta + 1e-30)

        if ratio > triggerOn, !armed {
            armed = true
            return true
        } else if ratio < triggerOff {
            armed = false
        }
        return false
    }

    mutating func reset() {
        sta = 0
        lta = 1e-10
        armed = false
    }
}

/// Fixed-capacity sliding window, oldest sample dropped as new ones arrive.
/// Distinct from `MedianWindow`, which empties itself on every publish.
private struct RingBuffer {
    private var storage: [Double]
    private var index = 0
    private var count = 0

    init(capacity: Int) {
        storage = [Double](repeating: 0, count: capacity)
    }

    var isFull: Bool { count == storage.count }

    mutating func append(_ value: Double) {
        storage[index] = value
        index = (index + 1) % storage.count
        count = min(count + 1, storage.count)
    }

    mutating func removeAll() {
        index = 0
        count = 0
    }

    /// Copies the live samples into `destination` in unspecified order and
    /// returns how many were written. The only consumer reduces them to a
    /// median, which does not depend on order, so insertion order is not
    /// reconstructed.
    func copyUnordered(into destination: inout [Double]) -> Int {
        for offset in 0..<count { destination[offset] = storage[offset] }
        return count
    }
}
