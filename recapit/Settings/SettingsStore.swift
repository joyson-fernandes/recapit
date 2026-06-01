import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    let keychain: KeychainStore

    private enum Key {
        static let processingMode = "processingMode"
        static let asrProvider = "asrProvider"
        static let llmProvider = "llmProvider"
        static let diarizationProvider = "diarizationProvider"
        static let asrModel = "asrModel"
        static let llmModel = "llmModel"
        static let countdownSeconds = "countdownSeconds"
        static let keepAudio = "keepAudio"
        static let skipSystemAudio = "skipSystemAudio"
        static let autoJoinCalendarURLs = "autoJoinCalendarURLs"
        static let launchAtLogin = "launchAtLogin"
        static let watchedCalendars = "watchedCalendars"
        static let startHotkey = "startHotkey"
        static let stopHotkey = "stopHotkey"
        static let adhocHotkey = "adhocHotkey"
        static let micDeviceID = "micDeviceID"
        static let firstRunCompleted = "firstRunCompleted"
    }

    init(defaults: UserDefaults = .standard,
         keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    var processingMode: ProcessingMode {
        get { ProcessingMode(rawValue: defaults.string(forKey: Key.processingMode) ?? "") ?? .local }
        set { defaults.set(newValue.rawValue, forKey: Key.processingMode) }
    }

    var asrProvider: ASRProviderID {
        get { ASRProviderID(rawValue: defaults.string(forKey: Key.asrProvider) ?? "") ?? .whisperKit }
        set { defaults.set(newValue.rawValue, forKey: Key.asrProvider) }
    }

    var llmProvider: LLMProviderID {
        get { LLMProviderID(rawValue: defaults.string(forKey: Key.llmProvider) ?? "") ?? .ollama }
        set { defaults.set(newValue.rawValue, forKey: Key.llmProvider) }
    }

    var diarizationProvider: DiarizationProviderID {
        get { DiarizationProviderID(rawValue: defaults.string(forKey: Key.diarizationProvider) ?? "") ?? .pyannoteONNX }
        set { defaults.set(newValue.rawValue, forKey: Key.diarizationProvider) }
    }

    var asrModel: String {
        get { defaults.string(forKey: Key.asrModel) ?? "large-v3-turbo" }
        set { defaults.set(newValue, forKey: Key.asrModel) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Key.llmModel) ?? "llama3.1:8b" }
        set { defaults.set(newValue, forKey: Key.llmModel) }
    }

    var countdownSeconds: Int {
        get {
            let v = defaults.integer(forKey: Key.countdownSeconds)
            return v == 0 ? 30 : v
        }
        set { defaults.set(newValue, forKey: Key.countdownSeconds) }
    }

    var keepAudio: KeepAudio {
        get { KeepAudio(rawValue: defaults.string(forKey: Key.keepAudio) ?? "") ?? .never }
        set { defaults.set(newValue.rawValue, forKey: Key.keepAudio) }
    }

    var autoJoinCalendarURLs: Bool {
        get { defaults.object(forKey: Key.autoJoinCalendarURLs) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoJoinCalendarURLs) }
    }

    var skipSystemAudio: Bool {
        get { defaults.bool(forKey: Key.skipSystemAudio) }
        set { defaults.set(newValue, forKey: Key.skipSystemAudio) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var firstRunCompleted: Bool {
        get { defaults.bool(forKey: Key.firstRunCompleted) }
        set { defaults.set(newValue, forKey: Key.firstRunCompleted) }
    }

    var watchedCalendars: Set<String> {
        get { Set((defaults.array(forKey: Key.watchedCalendars) as? [String]) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.watchedCalendars) }
    }

    var startHotkey: KeyCombo? {
        get { decode(Key.startHotkey) ?? KeyCombo.defaultStart }
        set { encode(newValue, Key.startHotkey) }
    }

    var stopHotkey: KeyCombo? {
        get { decode(Key.stopHotkey) ?? KeyCombo.defaultStop }
        set { encode(newValue, Key.stopHotkey) }
    }

    var adhocHotkey: KeyCombo? {
        get { decode(Key.adhocHotkey) ?? KeyCombo.defaultAdHoc }
        set { encode(newValue, Key.adhocHotkey) }
    }

    private func decode(_ key: String) -> KeyCombo? {
        if defaults.bool(forKey: key + ".cleared") { return nil }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    private func encode(_ combo: KeyCombo?, _ key: String) {
        if let combo = combo {
            defaults.set(false, forKey: key + ".cleared")
            defaults.set(try? JSONEncoder().encode(combo), forKey: key)
        } else {
            defaults.set(true, forKey: key + ".cleared")
            defaults.removeObject(forKey: key)
        }
    }
}
