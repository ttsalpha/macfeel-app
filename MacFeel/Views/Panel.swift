import SwiftUI

/// Shared chrome so every instrument reads as part of one set.
///
/// The title row doubles as the control: a disclosure chevron rather than a
/// switch, because five switches stacked down a narrow panel dominate it and
/// read heavier than the numbers they gate. Collapsing a section also stops its
/// sensor, so the chevron carries the same meaning the switch did.
struct Panel<Content: View>: View {
    let title: String
    let symbol: String
    var isOn: Binding<Bool>?
    @ViewBuilder var content: Content

    private var isExpanded: Bool { isOn?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                content
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private var header: some View {
        Button {
            isOn?.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isExpanded ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                    )

                Spacer(minLength: 8)

                if isOn != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            // Inset lives inside the label, not on the card, so the target
            // runs to the card's edges instead of stopping short of them.
            .padding(14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isOn == nil)
    }
}

/// A measurement shown large enough to read at a glance.
struct Readout: View {
    enum UnitPlacement {
        /// A word set after the number, smaller and dimmed: "42 g", "69 lux".
        case trailing
        /// A symbol fused to the number at full size, which is the only correct
        /// way to set a degree sign. Baseline-aligning it as a separate smaller
        /// run leaves it floating low and undersized.
        case attached
    }

    let value: String
    let unit: String
    var placement: UnitPlacement = .trailing
    var muted = false

    private let numberFont = Font.system(size: 34, weight: .medium, design: .rounded)

    var body: some View {
        content
            .foregroundStyle(muted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
    }

    @ViewBuilder
    private var content: some View {
        switch placement {
        case .attached:
            Text(value + unit)
                .font(numberFont)
                .monospacedDigit()
                .contentTransition(.numericText())
        case .trailing:
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(numberFont)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
