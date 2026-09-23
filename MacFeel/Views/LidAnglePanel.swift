import SwiftUI

struct LidAnglePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Panel(title: "Lid Angle", symbol: "angle", isOn: $model.lidEnabled) {
            reading
        }
    }

    private var reading: some View {
        HStack(alignment: .center, spacing: 12) {
            if let angle = model.lidAngle {
                Readout(
                    value: angle.formatted(.number.precision(.fractionLength(0))),
                    unit: "°",
                    placement: .attached
                )
                Spacer(minLength: 0)
                HingeGauge(angle: angle)
                    .frame(width: 96, height: 58)
            } else if let error = model.lidError {
                Text(error.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Readout(value: "–", unit: "°", placement: .attached, muted: true)
                Spacer(minLength: 0)
                Text("Try moving the lid")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.lidAngle)
    }
}

/// Side-on view of the hinge: a fixed deck, the lid drawn at the measured angle,
/// and a faint sweep showing the travel it can cover.
private struct HingeGauge: View {
    let angle: Double

    /// Headroom past a MacBook's ~135° hard stop so the drawing never clips even
    /// if the sensor reports slightly beyond it.
    private let maxAngle = 150.0

    var body: some View {
        Canvas { context, size in
            let inset = 5.0
            // The deck runs right from the hinge, the lid swings up and to the
            // left. Solve the arm length so the widest pose still fits the canvas
            // in both directions rather than letting it run off the edge.
            let leftReach = abs(cos(Angle(degrees: maxAngle).radians))
            let arm = min(
                (size.width - 2 * inset) / (1 + leftReach),
                size.height - 2 * inset
            )
            let pivot = CGPoint(x: inset + leftReach * arm, y: size.height - inset)

            // Canvas y grows downward, so the lid's travel is a negative sweep.
            var travel = Path()
            travel.addArc(
                center: pivot,
                radius: arm * 0.4,
                startAngle: .degrees(-135),
                endAngle: .zero,
                clockwise: false
            )
            context.stroke(
                travel,
                with: .color(.secondary.opacity(0.22)),
                style: .init(lineWidth: 1.5, lineCap: .round, dash: [2, 3])
            )

            var deck = Path()
            deck.move(to: pivot)
            deck.addLine(to: CGPoint(x: pivot.x + arm, y: pivot.y))
            context.stroke(
                deck,
                with: .color(.secondary.opacity(0.55)),
                style: .init(lineWidth: 4, lineCap: .round)
            )

            let radians = Angle(degrees: angle).radians
            let tip = CGPoint(
                x: pivot.x + arm * cos(radians),
                y: pivot.y - arm * sin(radians)
            )
            var lid = Path()
            lid.move(to: pivot)
            lid.addLine(to: tip)
            context.stroke(
                lid,
                with: .color(.accentColor),
                style: .init(lineWidth: 4, lineCap: .round)
            )

            let hinge = CGRect(x: pivot.x - 2.5, y: pivot.y - 2.5, width: 5, height: 5)
            context.fill(Path(ellipseIn: hinge), with: .color(.accentColor))
        }
    }
}
