import AVFAudio
import AudioToolbox
import Defaults
import Foundation

// MARK: - SoundEffect
nonisolated enum SoundEffect: Hashable, Sendable {
    case keyPress
}

// MARK: - SystemSoundPlaying
nonisolated protocol SystemSoundPlaying {
    func createSoundID(for url: URL) -> SystemSoundID?
    func play(_ soundID: SystemSoundID)
    func dispose(_ soundID: SystemSoundID)
}

// MARK: - SoundService
@MainActor
final class SoundService {
    static let shared = SoundService()

    private let soundPlayer: any SystemSoundPlaying
    private let preference: Defaults.Key<ButtonSound>
    private let customSoundStore: CustomButtonSoundStore
    private var soundIDs: [ButtonSound: SystemSoundID] = [:]
    private var customPlayer: AVAudioPlayer?

    // MARK: - Initialization
    init(
        soundPlayer: any SystemSoundPlaying = AudioToolboxSystemSoundPlayer(),
        preference: Defaults.Key<ButtonSound>? = nil,
        customSoundStore: CustomButtonSoundStore? = nil
    ) {
        self.soundPlayer = soundPlayer
        self.preference = preference ?? .buttonSound
        self.customSoundStore = customSoundStore ?? .shared
    }

    isolated deinit {
        soundIDs.values.forEach(soundPlayer.dispose)
    }

    // MARK: - Import
    func importButtonSound(from url: URL) throws {
        try customSoundStore.importSound(from: url)
        Defaults[preference] = .custom
    }

    // MARK: - Playback
    func play(_ effect: SoundEffect) {
        switch effect {
        case .keyPress:
            playButtonSound(Defaults[preference])
        }
    }

    // MARK: - Button Sound Playback
    private func playButtonSound(_ sound: ButtonSound) {
        if sound == .custom {
            playCustomSound()
            return
        }

        guard let soundID = soundID(for: sound) else {
            return
        }

        soundPlayer.play(soundID)
    }

    // MARK: - Custom Playback
    private func playCustomSound() {
        guard let url = customSoundStore.fileURL else { return }

        if customPlayer?.url != url {
            customPlayer = try? AVAudioPlayer(contentsOf: url)
            customPlayer?.prepareToPlay()
        }

        customPlayer?.currentTime = 0
        customPlayer?.play()
    }

    // MARK: - Sound Cache
    private func soundID(for sound: ButtonSound) -> SystemSoundID? {
        if let cachedSoundID = soundIDs[sound] {
            return cachedSoundID
        }

        guard let url = sound.fileURL,
            let soundID = soundPlayer.createSoundID(for: url)
        else {
            return nil
        }

        soundIDs[sound] = soundID

        return soundID
    }
}

// MARK: - AudioToolboxSystemSoundPlayer
nonisolated private struct AudioToolboxSystemSoundPlayer: SystemSoundPlaying {
    func createSoundID(for url: URL) -> SystemSoundID? {
        var soundID = SystemSoundID()
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)

        guard status == kAudioServicesNoError else {
            return nil
        }

        return soundID
    }

    func play(_ soundID: SystemSoundID) {
        AudioServicesPlaySystemSound(soundID)
    }

    func dispose(_ soundID: SystemSoundID) {
        AudioServicesDisposeSystemSoundID(soundID)
    }
}
