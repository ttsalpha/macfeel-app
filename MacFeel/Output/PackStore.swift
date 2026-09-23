import Foundation

/// A pack the app can play, with its clips already on disk.
struct SoundPack: Identifiable, Sendable {
    let id: String
    let title: String
    /// A ramp pack is recorded as one, so a harder hit should reach further up
    /// it. The rest are unrelated one-liners and read better shuffled.
    let isIntensityRamp: Bool
    let clips: [URL]
}

/// The CDN's index of what exists and what it is called.
private struct Manifest: Decodable {
    struct Pack: Decodable, Equatable {
        let id: String
        let title: String
        let intensityRamp: Bool
        let clips: [String]
    }

    let packs: [Pack]

    /// Names from the manifest end up as path components, and a repeated id
    /// would both collide on disk and break the picker, so both are dropped
    /// here rather than trusted downstream.
    var usable: [Pack] {
        var seen: Set<String> = []
        return packs.compactMap { pack in
            guard Self.isName(pack.id), seen.insert(pack.id).inserted else { return nil }
            let clips = pack.clips.filter(Self.isName)
            guard !clips.isEmpty else { return nil }
            return Pack(
                id: pack.id,
                title: pack.title,
                intensityRamp: pack.intensityRamp,
                clips: clips
            )
        }
    }

    private static func isName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }
}

/// Downloads the sound packs into Application Support. Clips are hosted rather
/// than bundled so new ones ship without an app update.
struct PackStore: Sendable {
    enum Failure: Error {
        case badStatus(Int)
    }

    private static let remote = URL(string: "https://cdn.ttsalpha.com/macfeel/packs/")!
    private static let parallelDownloads = 4

    private let root = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "MacFeel", directoryHint: .isDirectory)
        .appending(path: "packs", directoryHint: .isDirectory)

    private var manifestFile: URL { root.appending(path: "manifest.json") }

    /// What the last run left on disk.
    func cached() -> [SoundPack] {
        playable(stored()?.usable ?? [])
    }

    /// Fetches the manifest, downloads whatever it lists that isn't here yet,
    /// and returns what can be played.
    func sync() async throws -> [SoundPack] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let data = try await fetch(Self.remote.appending(path: "manifest.json"), revalidating: true)
        let listed = try JSONDecoder().decode(Manifest.self, from: data).usable

        // A clip name is the only identity a file has, so a pack whose entry
        // changed is refetched whole. The rest keep what they already have.
        let known = stored()?.usable ?? []
        let stale = Set(
            listed.filter { pack in known.first { $0.id == pack.id } != pack }.map(\.id)
        )

        try await download(listed, replacing: stale)

        if data != (try? Data(contentsOf: manifestFile)) {
            prune(to: listed)
            // Written last: a manifest on disk means its clips are too.
            try data.write(to: manifestFile, options: .atomic)
        }
        return playable(listed)
    }

    private func stored() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestFile) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func download(_ packs: [Manifest.Pack], replacing stale: Set<String>) async throws {
        let files = FileManager.default
        var jobs: [(remote: URL, local: URL)] = []

        for pack in packs {
            let directory = root.appending(path: pack.id, directoryHint: .isDirectory)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            let replacing = stale.contains(pack.id)

            for clip in pack.clips {
                let local = directory.appending(path: clip)
                if !replacing, files.fileExists(atPath: local.path(percentEncoded: false)) {
                    continue
                }
                jobs.append((Self.remote.appending(path: "\(pack.id)/\(clip)"), local))
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, job) in jobs.enumerated() {
                if index >= Self.parallelDownloads { try await group.next() }
                group.addTask { try await save(job.remote, to: job.local) }
            }
            try await group.waitForAll()
        }
    }

    /// Drops clips and packs the manifest no longer lists.
    private func prune(to packs: [Manifest.Pack]) {
        let files = FileManager.default
        let wanted = Dictionary(
            packs.map { ($0.id, Set($0.clips)) },
            uniquingKeysWith: { a, _ in a }
        )

        let entries =
            (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent != manifestFile.lastPathComponent {
            guard let clips = wanted[entry.lastPathComponent] else {
                try? files.removeItem(at: entry)
                continue
            }
            let stored =
                (try? files.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
            for clip in stored where !clips.contains(clip.lastPathComponent) {
                try? files.removeItem(at: clip)
            }
        }
    }

    /// Only the clips actually on disk, so a half-finished download isn't
    /// offered.
    private func playable(_ packs: [Manifest.Pack]) -> [SoundPack] {
        let files = FileManager.default
        return packs.compactMap { pack in
            let clips = pack.clips
                .map { root.appending(path: "\(pack.id)/\($0)") }
                .filter { files.fileExists(atPath: $0.path(percentEncoded: false)) }
            guard !clips.isEmpty else { return nil }

            return SoundPack(
                id: pack.id,
                title: pack.title,
                isIntensityRamp: pack.intensityRamp,
                clips: clips
            )
        }
    }

    private func save(_ remote: URL, to local: URL) async throws {
        let data = try await fetch(remote, revalidating: false)
        try data.write(to: local, options: .atomic)
    }

    private func fetch(_ url: URL, revalidating: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        // A clip is written to disk here, so a second copy in URLCache is dead
        // weight. The manifest is small enough to be worth the ETag.
        request.cachePolicy =
            revalidating ? .reloadRevalidatingCacheData : .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.badStatus(http.statusCode)
        }
        return data
    }
}
