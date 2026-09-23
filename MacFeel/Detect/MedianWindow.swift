import Foundation

enum Readouts {
    /// One cadence for every live figure in the app. Each sensor reports at its
    /// own rate, from 10 Hz for ambient light to 100 Hz for motion, but they all
    /// end up as numbers a person reads off the same panel. Publishing them on
    /// different clocks made the panel feel like four unrelated things.
    static let interval = Duration.milliseconds(250)
}

/// Collects samples between display updates and hands back their median.
///
/// Every sensor here reports far faster than a number is readable, and each one
/// dithers by a little even when nothing is happening. Publishing straight
/// through gives a figure that changes too fast to read. The median rather than
/// the mean because it also throws away single-sample spikes, which the raw
/// streams are full of.
struct MedianWindow {
    private var samples: [Double] = []

    mutating func append(_ sample: Double) {
        samples.append(sample)
    }

    /// Returns the median of everything collected since the last call and starts
    /// a fresh window. Nil when nothing arrived, which the caller should read as
    /// "no news" rather than "zero".
    mutating func drain() -> Double? {
        guard !samples.isEmpty else { return nil }
        samples.sort()
        let median = samples[samples.count / 2]
        samples.removeAll(keepingCapacity: true)
        return median
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}
