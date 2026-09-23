import SwiftUI

struct SlapPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Panel(title: "Slap", symbol: "hand.wave", isOn: $model.slapEnabled) {
            if model.inputMonitoring != .granted {
                PermissionNotice(status: model.inputMonitoring)
            } else if let error = model.motionError {
                Text(error.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if model.inputMonitoring == .granted {
                HStack(alignment: .firstTextBaseline) {
                    Readout(
                        value: "\(model.slapCount)",
                        unit: model.slapCount == 1 ? "hit" : "hits"
                    )
                    Spacer()
                    if let force = model.lastSlapForce {
                        Text("\(force.formatted(.number.precision(.fractionLength(2)))) g")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Sensitivity")
                            .font(.callout)
                        Spacer()
                        Text(sensitivityHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.sensitivity, in: 0...1)
                        .controlSize(.small)
                }

                HStack {
                    Toggle(isOn: $model.soundEnabled) {
                        Text("Sound")
                            .font(.callout)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    packPicker
                }
            }
        }
    }

    /// Nothing to list until the download lands, so the warning stands in for
    /// the picker while it retries.
    @ViewBuilder
    private var packPicker: some View {
        @Bindable var model = model

        if !model.packs.isEmpty {
            Picker("", selection: $model.soundPack) {
                ForEach(model.packs) { pack in
                    Text(pack.title).tag(pack.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .disabled(!model.soundEnabled)
        } else if model.packsLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .help("Sound packs couldn't be downloaded. MacFeel keeps trying.")
        }
    }

    private var sensitivityHint: String {
        switch model.sensitivity {
        case ..<0.3: "Firm slaps only"
        case ..<0.7: "Balanced"
        default: "Typing may trigger it"
        }
    }
}

/// Shown when macOS is withholding the accelerometer. Never appears on a Mac
/// that simply lacks the sensor, because that case is gated out one level up by
/// the capability check, and a Settings shortcut would be a dead end there.
private struct PermissionNotice: View {
    let status: InputMonitoring.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Slap detection needs Input Monitoring.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(status == .denied ? "Open Input Monitoring settings" : "Allow access") {
                if status == .denied {
                    InputMonitoring.openSettings()
                } else {
                    InputMonitoring.request()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if status == .denied {
                Text("Tick MacFeel in the list, then come back here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
