import Foundation
import Observation

/// The packs on disk, kept level with the CDN in the background.
///
/// What the last run downloaded loads first, so sound works offline. A failed
/// fetch backs off rather than polls.
@MainActor
@Observable
final class PackLibrary {
    private(set) var packs: [SoundPack] = []
    /// True only on a first run with nothing cached, when the panel has
    /// nothing to show.
    private(set) var isLoading = false

    private static let firstRetry = Duration.seconds(30)
    private static let longestRetry = Duration.seconds(30 * 60)
    /// Stops opening and closing the panel from becoming a request a click.
    private static let retryGap: TimeInterval = 30
    /// The app can sit in the menu bar for weeks, so a panel opened long after
    /// launch is worth one manifest check.
    private static let staleAfter: TimeInterval = 6 * 60 * 60

    private let store = PackStore()
    private var syncTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryDelay = PackLibrary.firstRetry
    private var lastAttempt = Date.distantPast

    init() {
        packs = store.cached()
    }

    func sync() {
        retryTask?.cancel()
        retryTask = nil
        guard syncTask == nil else { return }

        isLoading = packs.isEmpty
        lastAttempt = .now
        syncTask = Task {
            do {
                packs = try await store.sync()
                retryDelay = Self.firstRetry
            } catch {
                scheduleRetry()
            }
            isLoading = false
            syncTask = nil
        }
    }

    /// Called when the panel opens. Cheaper than a timer, and someone who has
    /// just reconnected usually looks here next.
    func refresh() {
        let gap = packs.isEmpty ? Self.retryGap : Self.staleAfter
        guard Date.now.timeIntervalSince(lastAttempt) > gap else { return }
        sync()
    }

    private func scheduleRetry() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.longestRetry)
        retryTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            sync()
        }
    }
}
