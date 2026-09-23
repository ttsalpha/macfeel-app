import SwiftUI

struct LevelPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Panel(title: "Level", symbol: "level", isOn: $model.levelEnabled) {
            if let error = model.motionError {
                Text(error.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            reading
        }
    }

    /// Laid out in full before the first reading, so nothing shifts when it lands.
    private var reading: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Readout(
                    value: model.tilt?.magnitude
                        .formatted(.number.precision(.fractionLength(1))) ?? "–",
                    unit: "°",
                    placement: .attached,
                    muted: model.tilt == nil
                )
                Text(axes)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        model.tilt == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary)
                    )
            }
            Spacer(minLength: 0)
            Bubble(tilt: model.tilt)
                .frame(width: 66, height: 66)
                // Only the dial glides, else the numeric transition nudges the
                // line below. Keyed on tilt: magnitude misses a roll/pitch swing.
                .animation(.smooth(duration: 0.25), value: model.tilt)
        }
    }

    private var axes: String {
        guard let tilt = model.tilt else { return "roll –  pitch –" }
        return "roll \(signed(tilt.roll))  pitch \(signed(tilt.pitch))"
    }

    private func signed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
    }
}

/// A circular spirit level. The bubble sits where the high side is, matching a
/// real one: it floats away from whichever edge is lower.
private struct Bubble: View {
    /// Nil before the first reading: a bubble at dead centre would read as "level".
    let tilt: TiltEstimator.Tilt?

    /// Tilt that pushes the bubble to the rim. Beyond a few degrees a desk is
    /// obviously off, so a wider range would waste the whole dial.
    private let fullScale = 5.0
    /// Within this the surface counts as flat, and the bubble turns green.
    private let tolerance = 0.3

    private var isLevel: Bool { (tilt?.magnitude ?? .infinity) < tolerance }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2
            let bubbleRadius = side * 0.17
            let travel = radius - bubbleRadius - 2

            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.5))
                Circle()
                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
                Circle()
                    .strokeBorder(.secondary.opacity(0.35), lineWidth: 1)
                    .frame(width: bubbleRadius * 2.4, height: bubbleRadius * 2.4)

                if let tilt {
                    Circle()
                        .fill(isLevel ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                        .frame(width: bubbleRadius * 2, height: bubbleRadius * 2)
                        .offset(x: clamped(tilt.roll) * travel, y: clamped(tilt.pitch) * travel)
                        .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
        }
    }

    /// Normalised to -1...1 so the bubble stops at the rim instead of leaving it.
    private func clamped(_ degrees: Double) -> Double {
        max(-1, min(1, degrees / fullScale))
    }
}
