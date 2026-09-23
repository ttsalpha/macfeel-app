import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    /// The popover swaps its whole body rather than opening a second window,
    /// so About stays inside the panel the user already has open.
    @State private var showingAbout = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if showingAbout {
                AboutView()
            } else {
                instruments
            }
        }
        .frame(width: 360)
    }

    private var instruments: some View {
        VStack(spacing: 12) {
            if model.capabilities.lidAngle { LidAnglePanel() }
            if model.capabilities.motion {
                SlapPanel()
                LevelPanel()
            }
            if model.capabilities.trackpadForce { ScalePanel() }
            if model.capabilities.ambientLight { LightPanel() }
            if model.capabilities.hasNoSensors { unsupported }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if showingAbout {
                action("chevron.left", help: "Back") { showingAbout = false }
            }

            Text(showingAbout ? "About" : "MacFeel")
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                if !showingAbout {
                    action("info.circle", help: "About") { showingAbout = true }
                }
                action("escape", help: "Quit (⌘Q)") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Fixed box per glyph, so icons of different widths stay evenly spaced.
    private func action(
        _ symbol: String,
        help: String,
        run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var unsupported: some View {
        VStack(spacing: 6) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No supported sensors on this Mac")
                .font(.callout.weight(.medium))
            Text("MacFeel needs an Apple Silicon MacBook. Desktop Macs have none of these sensors.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
    }
}
