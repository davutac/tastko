import AVFAudio
import Defaults
import Foundation

// MARK: - CustomButtonSoundStore
@MainActor
final class CustomButtonSoundStore {
    static let shared = CustomButtonSoundStore()

    /// Key sounds play on every press, so long clips are rejected.
    static let defaultMaximumDuration: TimeInterval = 1

    private let directory: URL
    private let preference: Defaults.Key<StoredButtonSound?>
    private let maximumDuration: TimeInterval

    // MARK: - Initialization
    init(
        directory: URL? = nil,
        preference: Defaults.Key<StoredButtonSound?>? = nil,
        maximumDuration: TimeInterval = CustomButtonSoundStore.defaultMaximumDuration
    ) {
        self.directory =
            directory
            ?? URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Tastko", directoryHint: .isDirectory)
            .appending(path: "ButtonSounds", directoryHint: .isDirectory)
        self.preference = preference ?? .customButtonSound
        self.maximumDuration = maximumDuration
    }

    // MARK: - Saved Sound
    var fileURL: URL? {
        guard let sound = Defaults[preference],
            !sound.fileName.isEmpty,
            sound.fileName != ".",
            sound.fileName != "..",
            sound.fileName == (sound.fileName as NSString).lastPathComponent
        else { return nil }
        return directory.appending(path: sound.fileName)
    }

    // MARK: - Import
    func importSound(from source: URL) throws {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { source.stopAccessingSecurityScopedResource() }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: UUID().uuidString)
            .appendingPathExtension(source.pathExtension)

        do {
            try fileManager.copyItem(at: source, to: destination)
            let player = try AVAudioPlayer(contentsOf: destination)
            guard player.prepareToPlay() else { throw ImportError.unreadableAudio }
            guard player.duration <= maximumDuration else {
                throw ImportError.tooLong(maximumDuration)
            }
        }
        catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }

        let previousURL = fileURL
        Defaults[preference] = StoredButtonSound(
            fileName: destination.lastPathComponent,
            displayName: source.lastPathComponent
        )
        if let previousURL {
            try? fileManager.removeItem(at: previousURL)
        }
    }

    // MARK: - Import Error
    enum ImportError: LocalizedError, Equatable {
        case unreadableAudio
        case tooLong(TimeInterval)

        var errorDescription: String? {
            switch self {
            case .unreadableAudio:
                "This file could not be read as audio. Choose a different sound file."
            case .tooLong(let maximum):
                "Key sounds can be at most \(Self.format(maximum)) long. Choose a shorter sound file."
            }
        }

        private static func format(_ seconds: TimeInterval) -> String {
            Duration.seconds(seconds).formatted(.units(width: .wide))
        }
    }
}
