import AudioToolbox
import Defaults
import Foundation
import Testing

@testable import Tastko

// MARK: - SoundServiceTests
@MainActor
struct SoundServiceTests {
    private let suiteName = "SoundServiceTests-\(UUID().uuidString)"
    private var preference: Defaults.Key<ButtonSound> {
        Defaults.Key("buttonSound", default: .keyClick, suite: UserDefaults(suiteName: suiteName)!)
    }

    // MARK: - Sound Effects
    @Test func keyPressResolvesToAccessibilityKeyboardSound() {
        let url = ButtonSound.keyClick.fileURL!

        #expect(url.lastPathComponent == "SoundPressKey.aiff")
        #expect(url.path == expectedKeyPressSoundPath)
    }

    // MARK: - Playback
    @Test func playCreatesSoundIDOnceAndReusesIt() {
        let soundPlayer = FakeSystemSoundPlayer(soundID: 42)
        let service = SoundService(soundPlayer: soundPlayer, preference: preference)

        service.play(.keyPress)
        service.play(.keyPress)

        #expect(soundPlayer.createdURLs == [ButtonSound.keyClick.fileURL!])
        #expect(soundPlayer.playedSoundIDs == [42, 42])
        #expect(soundPlayer.disposedSoundIDs.isEmpty)
    }

    @Test func deinitDisposesLoadedSoundIDs() {
        let soundPlayer = FakeSystemSoundPlayer(soundID: 42)

        do {
            let service = SoundService(soundPlayer: soundPlayer, preference: preference)
            service.play(.keyPress)
        }

        #expect(soundPlayer.disposedSoundIDs == [42])
    }

    @Test func playDoesNothingWhenSoundIDCannotBeCreated() {
        let soundPlayer = FakeSystemSoundPlayer(soundID: nil)
        let service = SoundService(soundPlayer: soundPlayer, preference: preference)

        service.play(.keyPress)

        #expect(soundPlayer.createdURLs == [ButtonSound.keyClick.fileURL!])
        #expect(soundPlayer.playedSoundIDs.isEmpty)
        #expect(soundPlayer.disposedSoundIDs.isEmpty)
    }

    // MARK: - Preferences
    @Test func noneSkipsCreatingAndPlayingSound() {
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        Defaults[preference] = .none
        let soundPlayer = FakeSystemSoundPlayer(soundID: 42)
        let service = SoundService(soundPlayer: soundPlayer, preference: preference)

        service.play(.keyPress)

        #expect(soundPlayer.createdURLs.isEmpty)
        #expect(soundPlayer.playedSoundIDs.isEmpty)
    }

    @Test func changingSoundTakesEffectImmediatelyAndReusesEachCachedSound() {
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let soundPlayer = FakeSystemSoundPlayer(soundID: 42)
        let service = SoundService(soundPlayer: soundPlayer, preference: preference)

        service.play(.keyPress)
        Defaults[preference] = .cherryMXBlue
        service.play(.keyPress)
        Defaults[preference] = .none
        service.play(.keyPress)
        Defaults[preference] = .keyClick
        service.play(.keyPress)

        #expect(
            soundPlayer.createdURLs == [
                ButtonSound.keyClick.fileURL!, ButtonSound.cherryMXBlue.fileURL!,
            ]
        )
        #expect(soundPlayer.playedSoundIDs == [42, 43, 42])
    }

    @Test func newServiceReadsSavedSoundChoice() {
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        Defaults[preference] = .topre
        let soundPlayer = FakeSystemSoundPlayer(soundID: 42)
        let service = SoundService(soundPlayer: soundPlayer, preference: preference)

        service.play(.keyPress)

        #expect(soundPlayer.createdURLs == [ButtonSound.topre.fileURL!])
    }

    @Test(arguments: ["unknown", "pop", "tink", "glass", "ping"])
    func removedOrUnknownSavedChoiceFallsBackToOriginalClick(rawValue: String) {
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        UserDefaults(suiteName: suiteName)!.set(rawValue, forKey: "buttonSound")
        let soundPlayer = FakeSystemSoundPlayer(soundID: 42)
        let service = SoundService(soundPlayer: soundPlayer, preference: preference)

        service.play(.keyPress)

        #expect(soundPlayer.createdURLs == [ButtonSound.keyClick.fileURL!])
    }

    @Test(arguments: ButtonSound.allCases.filter { $0 != .none && $0 != .custom })
    func builtInSoundsCanBeLoaded(sound: ButtonSound) throws {
        let url = try #require(sound.fileURL)
        var soundID = SystemSoundID()
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        #expect(status == kAudioServicesNoError)
        if status == kAudioServicesNoError {
            AudioServicesDisposeSystemSoundID(soundID)
        }
    }

    private let expectedKeyPressSoundPath =
        "/System/Library/Input Methods/Assistive Control.app/Contents/Resources/SoundPressKey.aiff"
}

// MARK: - FakeSystemSoundPlayer
final class FakeSystemSoundPlayer: SystemSoundPlaying {
    private let soundID: SystemSoundID?

    private(set) var createdURLs: [URL] = []
    private(set) var playedSoundIDs: [SystemSoundID] = []
    private(set) var disposedSoundIDs: [SystemSoundID] = []

    // MARK: - Initialization
    init(soundID: SystemSoundID?) {
        self.soundID = soundID
    }

    // MARK: - SystemSoundPlaying
    func createSoundID(for url: URL) -> SystemSoundID? {
        createdURLs.append(url)

        return soundID.map { $0 + SystemSoundID(createdURLs.count - 1) }
    }

    func play(_ soundID: SystemSoundID) {
        playedSoundIDs.append(soundID)
    }

    func dispose(_ soundID: SystemSoundID) {
        disposedSoundIDs.append(soundID)
    }
}
