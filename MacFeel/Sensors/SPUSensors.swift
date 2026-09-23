import IOKit

/// The sensors behind Apple's SPU (accelerometer, gyroscope, ambient light) boot
/// powered down. Opening one succeeds and then not a single report arrives, which
/// is indistinguishable from a silently swallowed permission failure. Waking them
/// means writing three properties onto the `AppleSPUHIDDriver` services before any
/// device is opened.
enum SPUSensors {
    /// 10 ms puts the accelerometer at very close to 100 Hz, the rate the STA/LTA
    /// windows in `ImpactDetector` are counted for. The driver also accepts 1000,
    /// but then it streams near 800 Hz and everything downstream throws most of it
    /// away for no benefit.
    private static let reportIntervalMicroseconds = 10_000

    static func wake() {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("AppleSPUHIDDriver"),
                &iterator
            ) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            IORegistryEntrySetCFProperty(
                service,
                "SensorPropertyReportingState" as CFString,
                1 as CFNumber
            )
            IORegistryEntrySetCFProperty(
                service,
                "SensorPropertyPowerState" as CFString,
                1 as CFNumber
            )
            IORegistryEntrySetCFProperty(
                service,
                "ReportInterval" as CFString,
                reportIntervalMicroseconds as CFNumber
            )
            IOObjectRelease(service)
        }
    }
}
