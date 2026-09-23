import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MacFeel")
                    .font(.system(size: 15, weight: .semibold))
                Text(
                    "Your MacBook is also a scale, a protractor, a spirit level and a light meter. And it yelps when you slap it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text("Version \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            VStack(spacing: 2) {
                LinkRow(title: "Website", host: "macfeel.ttsalpha.com")
                LinkRow(title: "Made by", host: "ttsalpha.com")
            }
        }
        .padding(14)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

/// The whole row opens the link, not just the host text, so the target is the
/// full width rather than a few characters.
private struct LinkRow: View {
    let title: String
    let host: String

    @Environment(\.openURL) private var openURL
    @State private var isHovering = false

    var body: some View {
        Button {
            if let url = URL(string: "https://\(host)") { openURL(url) }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.callout)
                Spacer(minLength: 8)
                Text(host)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                .quaternary.opacity(isHovering ? 0.5 : 0),
                in: .rect(cornerRadius: 7)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
