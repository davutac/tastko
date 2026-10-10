import Carbon
import Foundation
import Observation

// MARK: - KeyboardLanguage
struct KeyboardLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let languageCodes: [String]

    var shortTitle: String {
        guard let languageCode = languageCodes.first else {
            return name
        }

        return
            languageCode
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .uppercased() ?? languageCode.uppercased()
    }
}

// MARK: - KeyboardLanguageService
@Observable
@MainActor
final class KeyboardLanguageService {
    static let shared = KeyboardLanguageService()
    let keyLabels = KeyboardLayoutTranslator()

    private(set) var languages: [KeyboardLanguage] = []
    private(set) var selectedLanguageID: String?

    @ObservationIgnored
    private var inputSourcesByID: [String: TISInputSource] = [:]
    @ObservationIgnored
    private var notificationObservers: [NSObjectProtocol] = []

    var selectedLanguage: KeyboardLanguage? {
        guard let selectedLanguageID else {
            return nil
        }

        return languages.first { $0.id == selectedLanguageID }
    }

    // MARK: - Initialization
    init() {
        refresh()
        observeInputSourceChanges()
    }

    isolated deinit {
        notificationObservers.forEach(DistributedNotificationCenter.default().removeObserver)
    }

    // MARK: - Loading
    func refresh() {
        keyLabels.refresh()
        let sources = availableInputSources()

        inputSourcesByID = Dictionary(
            uniqueKeysWithValues: sources.compactMap { source in
                guard let id = source.stringValue(for: kTISPropertyInputSourceID) else {
                    return nil
                }

                return (id, source)
            }
        )

        languages = sources.compactMap(KeyboardLanguage.init(inputSource:))
        selectedLanguageID = currentInputSourceID()
    }

    func refreshSelectedLanguage() {
        keyLabels.refresh()
        let currentInputSourceID = currentInputSourceID()

        guard currentInputSourceID != selectedLanguageID else {
            return
        }

        selectedLanguageID = currentInputSourceID

        guard let currentInputSourceID else {
            return
        }

        guard !languages.contains(where: { $0.id == currentInputSourceID }) else {
            return
        }

        refresh()
    }

    // MARK: - Selection
    func selectLanguage(withID id: String) {
        guard id != selectedLanguageID, let inputSource = inputSourcesByID[id] else {
            return
        }

        let status = TISSelectInputSource(inputSource)

        if status == noErr {
            keyLabels.refresh()
            selectedLanguageID = id
        }
        else {
            refresh()
        }
    }

    func selectNextLanguage() {
        guard !languages.isEmpty else {
            refresh()
            return
        }

        guard
            let selectedLanguageID,
            let selectedIndex = languages.firstIndex(where: { $0.id == selectedLanguageID })
        else {
            selectLanguage(withID: languages[0].id)
            return
        }

        let nextIndex = languages.index(after: selectedIndex)
        let wrappedIndex = nextIndex == languages.endIndex ? languages.startIndex : nextIndex

        selectLanguage(withID: languages[wrappedIndex].id)
    }

    // MARK: - Input Sources
    private func availableInputSources() -> [TISInputSource] {
        let properties: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsEnabled: kCFBooleanTrue as Any,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue as Any,
        ]

        guard let unmanagedSources = TISCreateInputSourceList(properties as CFDictionary, false)
        else {
            return []
        }

        let sources = unmanagedSources.takeRetainedValue() as NSArray

        return sources.map { $0 as! TISInputSource }
    }

    private func currentInputSourceID() -> String? {
        TISCopyCurrentKeyboardInputSource()?
            .takeRetainedValue()
            .stringValue(for: kTISPropertyInputSourceID)
    }

    // MARK: - Notifications
    private func observeInputSourceChanges() {
        let notificationCenter = DistributedNotificationCenter.default()
        let selectedObserver = notificationCenter.addObserver(
            forName: .selectedKeyboardInputSourceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let service = self else {
                return
            }

            Task { @MainActor in
                service.refreshSelectedLanguage()
            }
        }
        let enabledObserver = notificationCenter.addObserver(
            forName: .enabledKeyboardInputSourcesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let service = self else {
                return
            }

            Task { @MainActor in
                service.refresh()
            }
        }

        notificationObservers = [selectedObserver, enabledObserver]
    }
}

// MARK: - Keyboard Notifications
extension Notification.Name {
    fileprivate static let selectedKeyboardInputSourceChanged = Notification.Name(
        kTISNotifySelectedKeyboardInputSourceChanged as String
    )
    fileprivate static let enabledKeyboardInputSourcesChanged = Notification.Name(
        kTISNotifyEnabledKeyboardInputSourcesChanged as String
    )
}

// MARK: - KeyboardLanguage Input Source
extension KeyboardLanguage {
    fileprivate init?(inputSource: TISInputSource) {
        guard let id = inputSource.stringValue(for: kTISPropertyInputSourceID) else {
            return nil
        }

        self.id = id
        self.name = inputSource.stringValue(for: kTISPropertyLocalizedName) ?? id
        self.languageCodes = inputSource.stringArrayValue(for: kTISPropertyInputSourceLanguages)
    }
}

// MARK: - TISInputSource Values
extension TISInputSource {
    fileprivate func stringValue(for property: CFString) -> String? {
        guard let value = TISGetInputSourceProperty(self, property) else {
            return nil
        }

        return unsafeBitCast(value, to: CFString.self) as String
    }

    fileprivate func stringArrayValue(for property: CFString) -> [String] {
        guard let value = TISGetInputSourceProperty(self, property) else {
            return []
        }

        let values = unsafeBitCast(value, to: CFArray.self) as NSArray

        return values.compactMap { $0 as? String }
    }
}
