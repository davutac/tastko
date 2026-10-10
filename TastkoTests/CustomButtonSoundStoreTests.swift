import AVFAudio
import Defaults
import Foundation
import Testing

@testable import Tastko

// MARK: - CustomButtonSoundStoreTests
@MainActor
struct CustomButtonSoundStoreTests {
    private let suiteName = "CustomButtonSoundStoreTests-\(UUID().uuidString)"
    private let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    private var preference: Defaults.Key<StoredButtonSound?> {
        Defaults.Key("customButtonSound", suite: UserDefaults(suiteName: suiteName)!)
    }
    private var selection: Defaults.Key<ButtonSound> {
        Defaults.Key("buttonSound", default: .keyClick, suite: UserDefaults(suiteName: suiteName)!)
    }

    // MARK: - Import Persistence
    @Test func importedCopySurvivesOriginalRemovalAndStoreRecreation() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appending(path: "My Click.wav")
        try FileManager.default.copyItem(at: #require(ButtonSound.cherryMXBlue.fileURL), to: source)
        let storageDirectory = directory.appending(path: "Saved")
        let store = CustomButtonSoundStore(directory: storageDirectory, preference: preference)
        let service = SoundService(preference: selection, customSoundStore: store)

        try service.importButtonSound(from: source)
        try FileManager.default.removeItem(at: source)
        let reopenedStore = CustomButtonSoundStore(
            directory: storageDirectory,
            preference: preference
        )
        let savedURL = try #require(reopenedStore.fileURL)

        #expect(savedURL != source)
        #expect(Defaults[selection] == .custom)
        #expect(Defaults[preference]?.displayName == "My Click.wav")
        #expect(try AVAudioPlayer(contentsOf: savedURL).prepareToPlay())
    }

    // MARK: - Replacement
    @Test func replacementRemovesPreviousCopyAndPreservesSource() throws {
        defer { cleanUp() }
        let store = CustomButtonSoundStore(directory: directory, preference: preference)
        let source = try #require(ButtonSound.cherryMXBlue.fileURL)
        try store.importSound(from: source)
        let previousURL = try #require(store.fileURL)

        try store.importSound(from: #require(ButtonSound.topre.fileURL))
        let newURL = try #require(store.fileURL)

        #expect(newURL != previousURL)
        #expect(!FileManager.default.fileExists(atPath: previousURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - Import Failure
    @Test(arguments: ["", ".", "..", "../outside.wav"])
    func replacementIgnoresInvalidSavedFileName(fileName: String) throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existingFile = directory.appending(path: "outside.wav")
        try Data("keep".utf8).write(to: existingFile)
        let store = CustomButtonSoundStore(
            directory: directory.appending(path: "Saved"),
            preference: preference
        )
        Defaults[preference] = StoredButtonSound(fileName: fileName, displayName: "Invalid")

        #expect(store.fileURL == nil)
        try store.importSound(from: #require(ButtonSound.cherryMXBlue.fileURL))

        #expect(try Data(contentsOf: existingFile) == Data("keep".utf8))
        #expect(try AVAudioPlayer(contentsOf: #require(store.fileURL)).prepareToPlay())
    }

    @Test func invalidAudioKeepsSavedSoundAndRemovesFailedCopy() throws {
        defer { cleanUp() }
        let storageDirectory = directory.appending(path: "Saved")
        let store = CustomButtonSoundStore(directory: storageDirectory, preference: preference)
        try store.importSound(from: #require(ButtonSound.cherryMXBlue.fileURL))
        let originalSound = Defaults[preference]
        Defaults[selection] = .topre
        let service = SoundService(preference: selection, customSoundStore: store)
        let source = directory.appending(path: "Invalid.wav")
        try Data("not audio".utf8).write(to: source)

        #expect(throws: (any Error).self) {
            try service.importButtonSound(from: source)
        }

        #expect(Defaults[preference] == originalSound)
        #expect(Defaults[selection] == .topre)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: storageDirectory.path).count == 1
        )
    }

    @Test func soundLongerThanTheLimitIsRejectedAndKeepsSavedSound() throws {
        defer { cleanUp() }
        let storageDirectory = directory.appending(path: "Saved")
        let source = try #require(ButtonSound.cherryMXBlue.fileURL)
        try CustomButtonSoundStore(directory: storageDirectory, preference: preference)
            .importSound(from: source)
        let originalSound = Defaults[preference]
        let duration = try AVAudioPlayer(contentsOf: source).duration
        let store = CustomButtonSoundStore(
            directory: storageDirectory,
            preference: preference,
            maximumDuration: duration / 2
        )

        #expect(throws: CustomButtonSoundStore.ImportError.tooLong(duration / 2)) {
            try store.importSound(from: #require(ButtonSound.topre.fileURL))
        }

        #expect(Defaults[preference] == originalSound)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: storageDirectory.path).count == 1
        )
        #expect(CustomButtonSoundStore.defaultMaximumDuration >= 1)
    }

    // MARK: - Cleanup
    private func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
