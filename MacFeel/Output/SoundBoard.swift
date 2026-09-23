import AVFoundation

/// Plays a reaction clip when the Mac gets hit, out of whatever pack it is
/// handed. Keeps no catalogue of its own.
@MainActor
final class SoundBoard {
    /// Enough voices to overlap a fast run of hits without cutting the tail off
    /// the previous one, while still bounding how much can pile up.
    private let voiceLimit = 6
    private let previewIntensity = 0.15
    private var voices: [AVAudioPlayer] = []

    func play(_ pack: SoundPack, force: Double) {
        guard !pack.clips.isEmpty else { return }

        // 0.05 g is the softest hit worth reacting to, 0.8 g anything that
        // should read as maximum.
        let intensity = min(1, max(0, (force - 0.05) / 0.75))

        let url =
            pack.isIntensityRamp
            ? pack.clips[Int(intensity * Double(pack.clips.count - 1))]
            : pack.clips.randomElement()!

        emit(url, intensity: intensity)
    }

    /// Shuffles even a ramp pack, which a fixed-force preview would otherwise
    /// walk to the same clip every time.
    func preview(_ pack: SoundPack) {
        guard let url = pack.clips.randomElement() else { return }
        emit(url, intensity: previewIntensity)
    }

    private func emit(_ url: URL, intensity: Double) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = Float(0.35 + 0.65 * intensity)
        player.prepareToPlay()
        player.play()

        voices.removeAll { !$0.isPlaying }
        voices.append(player)
        if voices.count > voiceLimit { voices.removeFirst() }
    }
}
