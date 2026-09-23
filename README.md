<h1 align="center">
  <img src="MacFeel/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="150" alt=""><br>
  MacFeel
</h1>

Your MacBook is also a scale, a protractor, a spirit level and a light meter. And it yelps when you
slap it. MacFeel is the menu bar app that lets you use any of that.

## Requirements

- An Apple Silicon MacBook. Desktop Macs have none of these sensors, and the app says so.
- macOS 14 or later. Every hardware detail below was verified on macOS 27, Mac16,12 (M4 Air).
- Xcode with the macOS SDK. Swift 6, arm64 only.

## Instruments

| Panel          | Reads                           | Source                                                | Permission       |
| -------------- | ------------------------------- | ----------------------------------------------------- | ---------------- |
| Lid Angle      | Hinge angle, degrees            | `las` HID sensor, 125 Hz                              | —                |
| Slap           | Hit count and impact force, g   | Accelerometer (BMI286) on `AppleSPUHIDDevice`, 100 Hz | Input Monitoring |
| Level          | Roll and pitch on a bubble dial | Same accelerometer, gravity kept rather than stripped | Input Monitoring |
| Trackpad Scale | Weight, grams                   | MultitouchSupport force frames                        | —                |
| Light Meter    | Illuminance, lux                | `als` SPU sensor, 10 Hz                               | —                |

Each panel is gated on a hardware probe, and collapsing one stops its sensor.

## Permissions

Only the accelerometer is TCC-restricted (`kTCCServiceListenEvent`), so Slap and Level prompt for
**Input Monitoring** on first start; the other three panels are unaffected. Granting it in Settings
takes effect the next time the popover opens, no relaunch.

## Build and run

```sh
xcodebuild -project MacFeel.xcodeproj -scheme MacFeel -configuration Debug \
  -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/MacFeel-*/Build/Products/Debug/MacFeel.app
```

Or open `MacFeel.xcodeproj` and run. It is an agent app (`LSUIElement`): no Dock icon, no window,
just the status item popover, which opens on launch.

## Layout

```
MacFeel/
  AppDelegate.swift     Status item and popover; SwiftUI's MenuBarExtra can't be opened from code
  AppModel.swift        All sensor state, persistence, and the shared publish tick
  Capability.swift      Per-Mac hardware probe every panel is gated on
  Detect/               ImpactDetector (slap), TiltEstimator (level), MedianWindow
  Sensors/              IOKit HID and MultitouchSupport wrappers, plus the TCC gate
  Output/               SoundBoard, PackLibrary and PackStore (downloaded clips), Haptics
  Views/                One file per panel, over a shared Panel and Readout
```

## Sensor notes

- The SPU sensors (accelerometer, gyroscope, ambient light) boot powered down: opening one succeeds
  and then reports nothing, which looks exactly like a swallowed permission failure. `SPUSensors`
  wakes them through `AppleSPUHIDDriver` before any device is opened.
- Every figure publishes on one 250 ms tick, as a median. Sensors run from 10 Hz to 100 Hz, and
  reading them on separate clocks made the panel feel like unrelated parts.
- Impact detection follows
  [taigrr/apple-silicon-accelerometer](https://github.com/taigrr/apple-silicon-accelerometer), tuned
  against this exact sensor: three voters (STA/LTA at three timescales, CUSUM, peak over MAD) on a
  gravity-stripped signal.
- The trackpad reports force only while it senses a finger, so the scale needs contact kept and a
  tare taken.

## Sound

Nothing ships in the bundle. Packs live on the CDN, indexed by a manifest, and the app downloads
them in the background. Sound is off by default.

A clip's name is its only identity, so don't edit one in place. Add a new index, or purge that path
on the CDN.

## Formatting

```sh
xcrun swift-format -i -r MacFeel
```

## License

[MIT](LICENSE) by [ttsalpha](https://ttsalpha.com)
