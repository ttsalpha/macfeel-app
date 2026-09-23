import SwiftUI

struct LightPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Panel(title: "Light Meter", symbol: "sun.max", isOn: $model.lightEnabled) {
            reading
        }
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let lux = model.lux {
                Readout(
                    value: lux.formatted(.number.precision(.fractionLength(lux < 10 ? 1 : 0))),
                    unit: "lux"
                )
                Spacer(minLength: 0)
                Text(Self.describe(lux))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let error = model.lightError {
                Text(error.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Readout(value: "–", unit: "lux", muted: true)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.lux)
    }

    /// Rough bands from photography and lighting references, enough to tell the
    /// reading is sane without pretending to more precision than it has.
    private static func describe(_ lux: Double) -> String {
        switch lux {
        case ..<5: "Dark"
        case ..<50: "Dim"
        case ..<200: "Indoors"
        case ..<1000: "Bright room"
        case ..<10000: "Overcast"
        default: "Daylight"
        }
    }
}
