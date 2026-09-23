import SwiftUI

struct ScalePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Panel(title: "Trackpad Scale", symbol: "scalemass", isOn: $model.scaleEnabled) {
            if let error = model.scaleError {
                Text(error.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            reading
            steps
        }
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Readout(
                value: model.netGrams.formatted(.number.precision(.fractionLength(1))),
                unit: "g",
                muted: model.contactCount == 0
            )

            if model.contactCount > 0 {
                Text("\(model.contactCount) \(model.contactCount == 1 ? "finger" : "fingers")")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            Button("Zero") { model.tare() }
                .controlSize(.regular)
                .disabled(model.contactCount == 0)
                .help(
                    "Subtract whatever is on the trackpad right now, so the finger keeping contact doesn't count."
                )
        }
        .animation(.smooth(duration: 0.25), value: model.netGrams)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 4) {
            Step(number: 1, text: "Rest a finger on the trackpad, as lightly as you can.")
            Step(number: 2, text: "Press Zero.")
            Step(number: 3, text: "Lower the object on, keeping your finger in contact.")

            Text(
                "The trackpad reports force only while it senses a finger, so contact has to stay. Put paper between a metal object and the surface. Bare metal reads as a second finger."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 11, alignment: .trailing)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
