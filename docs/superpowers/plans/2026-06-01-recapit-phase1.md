# Recapit Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first AI meeting note-taker for macOS — calendar-driven auto-recording, on-device WhisperKit transcription, Pyannote ONNX diarization, BYOK LLM summarization with Fireflies/Granola hybrid prompts, SQLite + markdown persistence.

**Architecture:** Native Swift app (no Rust toolchain). 4 layers: UI (AppKit/SwiftUI), orchestration (state machine + EventKit), audio+AI pipeline (AVAudioEngine + ScreenCaptureKit → WhisperKit → Pyannote → LLM), persistence (SQLite + sqlite-vec + markdown).

**Tech Stack:** Swift 5.9, macOS 14+, SwiftUI + AppKit, Swift Package Manager, xcodegen, WhisperKit, ONNX Runtime Swift, GRDB (SQLite wrapper), sqlite-vec, EventKit, ScreenCaptureKit, AVAudioEngine.

**Phasing:** 16 tasks across 6 phases. Each task ships a verifiable milestone. Expect 1-3 days per task.

---

## Phase A — Foundation

### Task 1: Project scaffolding + signing

**Files:**
- Create: `project.yml`, `recapit/Info.plist`, `recapit/recapit.entitlements`, `recapit/App/recapitApp.swift`, `scripts/build-dmg.sh`, `.gitignore`

- [ ] **Step 1: Install xcodegen**

```bash
brew install xcodegen
```

- [ ] **Step 2: Create `project.yml`**

```yaml
name: recapit
options:
  bundleIdPrefix: com.joyson
  deploymentTarget:
    macOS: "14.0"

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    PRODUCT_BUNDLE_IDENTIFIER: com.joyson.recapit

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: "6.29.0"
  SQLiteVec:
    url: https://github.com/jkrukowski/SQLiteVec
    from: "0.0.7"
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit
    from: "0.9.0"
  onnxruntime:
    url: https://github.com/microsoft/onnxruntime-swift-package-manager
    from: "1.20.0"

targets:
  recapit:
    type: application
    platform: macOS
    sources:
      - recapit
    dependencies:
      - package: GRDB
      - package: SQLiteVec
      - package: WhisperKit
      - package: onnxruntime
        product: onnxruntime
    settings:
      base:
        INFOPLIST_FILE: recapit/Info.plist
        CODE_SIGN_ENTITLEMENTS: recapit/recapit.entitlements
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "E5B229B6341D07CBADB83D08A4BBA6CFE931B635"
        DEVELOPMENT_TEAM: 77YLNJXKXT

  recapitTests:
    type: bundle.unit-test
    platform: macOS
    sources: recapitTests
    dependencies:
      - target: recapit
```

- [ ] **Step 3: Create `recapit/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Recapit</string>
    <key>CFBundleDisplayName</key>
    <string>Recapit</string>
    <key>CFBundleIdentifier</key>
    <string>com.joyson.recapit</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>Recapit watches your calendar to auto-record meetings.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Recapit records your microphone during meetings.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Recapit captures system audio to record the other meeting participants.</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
```

- [ ] **Step 4: Create `recapit/recapit.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 5: Create `recapit/App/recapitApp.swift`**

```swift
import AppKit

@main
struct recapitApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // wired up in Task 6 (MenuBarController)
    }
}
```

- [ ] **Step 6: Create `.gitignore`**

```
.DS_Store
build/
DerivedData/
*.xcodeproj
*.dmg
.swiftpm/
Package.resolved
```

Note: we commit `Package.resolved` only AFTER first successful build to lock dependency versions.

- [ ] **Step 7: Create empty source/test directories so xcodegen has something to compile**

```bash
cd /Users/joyson/recapit
mkdir -p recapit/{Settings,DB,Markdown,Calendar,Capture,ASR,Diarization,LLM,Summary,Coordinator,UI}
mkdir -p recapitTests
echo "import Foundation" > recapitTests/Placeholder.swift
```

- [ ] **Step 8: Generate Xcode project and verify build**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. The first build downloads all Swift package dependencies — this takes a few minutes.

- [ ] **Step 9: Commit**

```bash
cd /Users/joyson/recapit
git add .
git commit -m "chore: scaffold Recapit Xcode project with SPM deps"
```

---

### Task 2: SettingsStore + KeyCombo + KeychainStore + ProcessingMode

**Files:**
- Create: `recapit/Settings/KeyCombo.swift`, `recapit/Settings/ProcessingMode.swift`, `recapit/Settings/KeychainStore.swift`, `recapit/Settings/SettingsStore.swift`
- Create tests: `recapitTests/KeyComboTests.swift`, `recapitTests/SettingsStoreTests.swift`, `recapitTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write failing tests**

`recapitTests/KeyComboTests.swift`:

```swift
import XCTest
@testable import recapit

final class KeyComboTests: XCTestCase {
    func testRoundTripCodable() throws {
        let c = KeyCombo(keyCode: 15, modifiers: KeyCombo.cmd | KeyCombo.shift)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(decoded, c)
    }

    func testDefaultStartHotkeyIsCmdShiftR() {
        XCTAssertEqual(KeyCombo.defaultStart.keyCode, 15)
        XCTAssertEqual(KeyCombo.defaultStart.modifiers, KeyCombo.cmd | KeyCombo.shift)
    }

    func testHasRequiredModifierRejectsBareKey() {
        XCTAssertFalse(KeyCombo(keyCode: 15, modifiers: 0).hasRequiredModifier)
        XCTAssertTrue(KeyCombo(keyCode: 15, modifiers: KeyCombo.cmd).hasRequiredModifier)
    }
}
```

`recapitTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import recapit

final class SettingsStoreTests: XCTestCase {
    var store: SettingsStore!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "com.joyson.recapit.test")!
        defaults.removePersistentDomain(forName: "com.joyson.recapit.test")
        store = SettingsStore(defaults: defaults)
    }

    func testDefaultProcessingModeIsLocal() {
        XCTAssertEqual(store.processingMode, .local)
    }

    func testDefaultCountdownIs30Seconds() {
        XCTAssertEqual(store.countdownSeconds, 30)
    }

    func testDefaultKeepAudioIsNever() {
        XCTAssertEqual(store.keepAudio, .never)
    }

    func testPersistsProcessingMode() {
        store.processingMode = .hybrid
        XCTAssertEqual(store.processingMode, .hybrid)
    }
}
```

`recapitTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import recapit

final class KeychainStoreTests: XCTestCase {
    var store: KeychainStore!
    let testService = "com.joyson.recapit.test"

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: testService)
        store.delete(account: "openai_key")
        store.delete(account: "anthropic_key")
    }

    override func tearDown() {
        store.delete(account: "openai_key")
        store.delete(account: "anthropic_key")
        super.tearDown()
    }

    func testStoresAndRetrievesKey() {
        store.set("sk-abc123", account: "openai_key")
        XCTAssertEqual(store.get(account: "openai_key"), "sk-abc123")
    }

    func testReturnsNilForMissingKey() {
        XCTAssertNil(store.get(account: "missing"))
    }

    func testOverwritesExistingKey() {
        store.set("first", account: "openai_key")
        store.set("second", account: "openai_key")
        XCTAssertEqual(store.get(account: "openai_key"), "second")
    }

    func testMaskedShowsLastFour() {
        store.set("sk-abc123def456ghi7890", account: "openai_key")
        XCTAssertEqual(store.masked(account: "openai_key"), "••••••••••••7890")
    }
}
```

- [ ] **Step 2: Implement `recapit/Settings/KeyCombo.swift`**

```swift
import Carbon.HIToolbox
import Foundation

struct KeyCombo: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let cmd: UInt32 = UInt32(cmdKey)
    static let shift: UInt32 = UInt32(shiftKey)
    static let option: UInt32 = UInt32(optionKey)
    static let control: UInt32 = UInt32(controlKey)

    static let defaultStart = KeyCombo(keyCode: 15, modifiers: cmd | shift)   // ⌘⇧R
    static let defaultStop = KeyCombo(keyCode: 1, modifiers: cmd | shift)     // ⌘⇧S
    static let defaultAdHoc = KeyCombo(keyCode: 0, modifiers: cmd | shift)    // ⌘⇧A

    var hasRequiredModifier: Bool {
        modifiers & (Self.cmd | Self.option | Self.control) != 0
    }

    var displayString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.cmd != 0 { s += "⌘" }
        s += Self.keyName(forKeyCode: keyCode)
        return s
    }

    private static func keyName(forKeyCode code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"; case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        default: return "·"
        }
    }
}
```

- [ ] **Step 3: Implement `recapit/Settings/ProcessingMode.swift`**

```swift
import Foundation

enum ProcessingMode: String, Codable, CaseIterable {
    case local
    case cloud
    case hybrid

    var displayName: String {
        switch self {
        case .local: return "Local — fully offline"
        case .cloud: return "Cloud — paste an API key"
        case .hybrid: return "Hybrid — local ASR + cloud LLM"
        }
    }
}

enum ASRProviderID: String, Codable, CaseIterable {
    case whisperKit
    case deepgram
    case openAIWhisper
}

enum LLMProviderID: String, Codable, CaseIterable {
    case ollama
    case openAI
    case anthropic
    case openAICompatible
}

enum DiarizationProviderID: String, Codable, CaseIterable {
    case pyannoteONNX
    case pyannoteCloud
}

enum KeepAudio: String, Codable, CaseIterable {
    case never
    case sevenDays
    case forever
}
```

- [ ] **Step 4: Implement `recapit/Settings/KeychainStore.swift`**

```swift
import Foundation
import Security

final class KeychainStore {
    private let service: String

    init(service: String = "com.joyson.recapit") {
        self.service = service
    }

    func set(_ value: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    func masked(account: String) -> String? {
        guard let v = get(account: account) else { return nil }
        guard v.count > 4 else { return String(repeating: "•", count: v.count) }
        let last4 = v.suffix(4)
        return String(repeating: "•", count: 12) + last4
    }
}
```

- [ ] **Step 5: Implement `recapit/Settings/SettingsStore.swift`**

```swift
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
```

- [ ] **Step 6: Regenerate project, run tests**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add recapit/Settings/ recapitTests/{KeyCombo,Settings,Keychain}Tests.swift recapit.xcodeproj
git commit -m "feat: SettingsStore + KeyCombo + KeychainStore + ProcessingMode"
```

---

### Task 3: MeetingDB schema + migrations (GRDB + sqlite-vec)

**Files:**
- Create: `recapit/DB/MeetingDB.swift`, `recapit/DB/Schema.swift`, `recapit/DB/Meeting.swift`, `recapit/DB/TranscriptSegment.swift`, `recapit/DB/ActionItem.swift`
- Create test: `recapitTests/MeetingDBTests.swift`

- [ ] **Step 1: Write failing tests**

`recapitTests/MeetingDBTests.swift`:

```swift
import XCTest
import GRDB
@testable import recapit

final class MeetingDBTests: XCTestCase {
    var db: MeetingDB!

    override func setUp() async throws {
        try await super.setUp()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        db = try MeetingDB(path: tmp.path)
    }

    func testInsertAndFetchMeeting() throws {
        let m = Meeting.draft(title: "Standup", startedAt: Date(timeIntervalSince1970: 1000))
        let id = try db.insertMeeting(m)
        let fetched = try db.meeting(id: id)
        XCTAssertEqual(fetched?.title, "Standup")
        XCTAssertEqual(fetched?.state, .recording)
    }

    func testAppendsTranscriptSegment() throws {
        let id = try db.insertMeeting(.draft(title: "Test", startedAt: Date()))
        try db.appendSegment(TranscriptSegment(
            meetingId: id, channel: "mic",
            startMs: 0, endMs: 1500,
            speaker: "You", text: "Hello there."
        ))
        let segments = try db.segments(meetingId: id)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "Hello there.")
    }

    func testFTSReturnsMatches() throws {
        let id = try db.insertMeeting(.draft(title: "T", startedAt: Date()))
        try db.appendSegment(TranscriptSegment(
            meetingId: id, channel: "system", startMs: 0, endMs: 100,
            speaker: "Speaker_1", text: "kubernetes deployment failed"
        ))
        let hits = try db.searchTranscripts("kubernetes")
        XCTAssertEqual(hits.count, 1)
    }
}
```

- [ ] **Step 2: Implement `recapit/DB/Schema.swift`**

```swift
import GRDB

enum DBMigration: String {
    case v1 = "v1_initial"

    static var all: [(String, (Database) throws -> Void)] {
        [
            (DBMigration.v1.rawValue, v1)
        ]
    }

    private static func v1(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE meetings (
          id              TEXT PRIMARY KEY,
          title           TEXT NOT NULL,
          started_at      INTEGER NOT NULL,
          ended_at        INTEGER,
          calendar_event  TEXT,
          pre_notes       TEXT,
          markdown_path   TEXT NOT NULL,
          audio_path      TEXT,
          summary         TEXT,
          attendees       TEXT,
          meeting_url     TEXT,
          state           TEXT NOT NULL,
          processing_mode TEXT NOT NULL,
          created_at      INTEGER NOT NULL,
          updated_at      INTEGER NOT NULL
        );
        CREATE INDEX idx_meetings_started_at ON meetings(started_at DESC);
        CREATE INDEX idx_meetings_state ON meetings(state);
        """)

        try db.execute(sql: """
        CREATE TABLE transcript_segments (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
          channel         TEXT NOT NULL,
          start_ms        INTEGER NOT NULL,
          end_ms          INTEGER NOT NULL,
          speaker         TEXT NOT NULL,
          text            TEXT NOT NULL
        );
        CREATE INDEX idx_segments_meeting ON transcript_segments(meeting_id, start_ms);
        """)

        try db.execute(sql: """
        CREATE VIRTUAL TABLE transcript_fts USING fts5(
          text, meeting_id UNINDEXED, segment_id UNINDEXED,
          content='transcript_segments', content_rowid='id'
        );
        CREATE TRIGGER transcript_ai AFTER INSERT ON transcript_segments BEGIN
          INSERT INTO transcript_fts(rowid, text, meeting_id, segment_id)
          VALUES (new.id, new.text, new.meeting_id, new.id);
        END;
        """)

        try db.execute(sql: """
        CREATE TABLE speakers (
          meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
          speaker_id      TEXT NOT NULL,
          display_name    TEXT NOT NULL,
          PRIMARY KEY (meeting_id, speaker_id)
        );
        """)

        try db.execute(sql: """
        CREATE TABLE action_items (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
          task            TEXT NOT NULL,
          owner           TEXT,
          due             TEXT,
          done            INTEGER NOT NULL DEFAULT 0,
          position        INTEGER NOT NULL
        );
        """)

        try db.execute(sql: """
        CREATE TABLE meeting_overrides (
          calendar_event  TEXT PRIMARY KEY,
          recurring_id    TEXT,
          rule            TEXT NOT NULL
        );
        """)

        // sqlite-vec tables registered at app start via the Swift binding, not via SQL here.
    }
}
```

- [ ] **Step 3: Implement `recapit/DB/Meeting.swift`**

```swift
import Foundation
import GRDB

enum MeetingState: String, Codable {
    case recording, processing, done, failed
}

struct Meeting: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "meetings"

    var id: String
    var title: String
    var startedAt: Int64       // unix seconds
    var endedAt: Int64?
    var calendarEvent: String?
    var preNotes: String?
    var markdownPath: String
    var audioPath: String?
    var summary: String?
    var attendees: String?     // JSON array
    var meetingURL: String?
    var state: MeetingState
    var processingMode: String
    var createdAt: Int64
    var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, title
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case calendarEvent = "calendar_event"
        case preNotes = "pre_notes"
        case markdownPath = "markdown_path"
        case audioPath = "audio_path"
        case summary, attendees
        case meetingURL = "meeting_url"
        case state
        case processingMode = "processing_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func draft(title: String, startedAt: Date) -> Meeting {
        let id = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)
        return Meeting(
            id: id,
            title: title,
            startedAt: Int64(startedAt.timeIntervalSince1970),
            endedAt: nil,
            calendarEvent: nil,
            preNotes: nil,
            markdownPath: "notes/\(id).md",
            audioPath: nil,
            summary: nil,
            attendees: nil,
            meetingURL: nil,
            state: .recording,
            processingMode: "local",
            createdAt: now,
            updatedAt: now
        )
    }
}
```

- [ ] **Step 4: Implement `recapit/DB/TranscriptSegment.swift`**

```swift
import Foundation
import GRDB

struct TranscriptSegment: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcript_segments"
    var id: Int64?
    var meetingId: String
    var channel: String         // "mic" or "system"
    var startMs: Int64
    var endMs: Int64
    var speaker: String         // "You" or "Speaker_N"
    var text: String

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case channel
        case startMs = "start_ms"
        case endMs = "end_ms"
        case speaker, text
    }
}
```

- [ ] **Step 5: Implement `recapit/DB/ActionItem.swift`**

```swift
import Foundation
import GRDB

struct ActionItem: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "action_items"
    var id: Int64?
    var meetingId: String
    var task: String
    var owner: String?
    var due: String?
    var done: Bool
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case task, owner, due, done, position
    }
}
```

- [ ] **Step 6: Implement `recapit/DB/MeetingDB.swift`**

```swift
import Foundation
import GRDB

final class MeetingDB {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        for (name, body) in DBMigration.all {
            migrator.registerMigration(name, migrate: body)
        }
        try migrator.migrate(dbQueue)
    }

    @discardableResult
    func insertMeeting(_ meeting: Meeting) throws -> String {
        try dbQueue.write { db in
            var m = meeting
            try m.insert(db)
        }
        return meeting.id
    }

    func meeting(id: String) throws -> Meeting? {
        try dbQueue.read { db in
            try Meeting.fetchOne(db, key: id)
        }
    }

    func updateMeeting(_ meeting: Meeting) throws {
        try dbQueue.write { db in
            var m = meeting
            m.updatedAt = Int64(Date().timeIntervalSince1970)
            try m.update(db)
        }
    }

    func appendSegment(_ segment: TranscriptSegment) throws {
        try dbQueue.write { db in
            var s = segment
            try s.insert(db)
        }
    }

    func segments(meetingId: String) throws -> [TranscriptSegment] {
        try dbQueue.read { db in
            try TranscriptSegment
                .filter(Column("meeting_id") == meetingId)
                .order(Column("start_ms"))
                .fetchAll(db)
        }
    }

    func searchTranscripts(_ query: String) throws -> [(meetingId: String, segmentId: Int64, text: String)] {
        try dbQueue.read { db in
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query) ?? FTS5Pattern(rawPattern: query)
            let rows = try Row.fetchAll(db, sql: """
                SELECT meeting_id, segment_id, text
                FROM transcript_fts
                WHERE transcript_fts MATCH ?
                ORDER BY rank
                LIMIT 100
                """, arguments: [pattern.rawPattern])
            return rows.map {
                ($0["meeting_id"] as String, $0["segment_id"] as Int64, $0["text"] as String)
            }
        }
    }

    func recentMeetings(limit: Int = 100) throws -> [Meeting] {
        try dbQueue.read { db in
            try Meeting.order(Column("started_at").desc).limit(limit).fetchAll(db)
        }
    }
}
```

- [ ] **Step 7: Run tests, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -10
git add recapit/DB/ recapitTests/MeetingDBTests.swift recapit.xcodeproj
git commit -m "feat: MeetingDB with GRDB + FTS5 + migrations"
```

---

### Task 4: MarkdownStore (write .md files per meeting)

**Files:**
- Create: `recapit/Markdown/MarkdownStore.swift`
- Create test: `recapitTests/MarkdownStoreTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import recapit

final class MarkdownStoreTests: XCTestCase {
    var tmpRoot: URL!

    override func setUp() {
        super.setUp()
        tmpRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
    }

    func testWritesYAMLFrontmatterAndSections() throws {
        let store = MarkdownStore(root: tmpRoot)
        let segs = [
            TranscriptSegment(id: nil, meetingId: "m1", channel: "mic",
                              startMs: 2000, endMs: 3500, speaker: "You", text: "Hi everyone."),
            TranscriptSegment(id: nil, meetingId: "m1", channel: "system",
                              startMs: 4000, endMs: 5800, speaker: "Alice", text: "Hello!")
        ]
        let actions = [
            ActionItem(id: nil, meetingId: "m1", task: "Send report",
                       owner: "You", due: nil, done: false, position: 0)
        ]
        let url = try store.write(
            meeting: Meeting.draft(title: "Test", startedAt: Date(timeIntervalSince1970: 1717_000_000)),
            preNotes: "- Plan rollout",
            summary: "We agreed to ship Friday.",
            actionItems: actions,
            segments: segs,
            attendees: ["Alice", "You"]
        )
        let content = try String(contentsOf: url)
        XCTAssertTrue(content.hasPrefix("---\n"))
        XCTAssertTrue(content.contains("title: Test"))
        XCTAssertTrue(content.contains("## Pre-meeting notes"))
        XCTAssertTrue(content.contains("- Plan rollout"))
        XCTAssertTrue(content.contains("## Summary"))
        XCTAssertTrue(content.contains("We agreed to ship Friday."))
        XCTAssertTrue(content.contains("- [ ] You: Send report"))
        XCTAssertTrue(content.contains("**00:02 — You**"))
        XCTAssertTrue(content.contains("Hi everyone."))
    }
}
```

- [ ] **Step 2: Implement `recapit/Markdown/MarkdownStore.swift`**

```swift
import Foundation

final class MarkdownStore {
    let root: URL
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
    }

    @discardableResult
    func write(meeting: Meeting,
               preNotes: String?,
               summary: String?,
               actionItems: [ActionItem],
               segments: [TranscriptSegment],
               attendees: [String]) throws -> URL {
        let url = root.appendingPathComponent(meeting.markdownPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var out = "---\n"
        out += "title: \(meeting.title)\n"
        out += "date: \(isoFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(meeting.startedAt))))\n"
        if !attendees.isEmpty {
            out += "attendees: [\(attendees.joined(separator: ", "))]\n"
        }
        if let ended = meeting.endedAt {
            let durationMin = (ended - meeting.startedAt) / 60
            out += "duration: \(durationMin)m\n"
        }
        out += "processing_mode: \(meeting.processingMode)\n"
        out += "---\n\n"
        out += "# \(meeting.title)\n\n"

        if let p = preNotes, !p.isEmpty {
            out += "## Pre-meeting notes\n\(p)\n\n"
        }
        if let s = summary, !s.isEmpty {
            out += "## Summary\n\(s)\n\n"
        }
        if !actionItems.isEmpty {
            out += "## Action items\n"
            for a in actionItems {
                let owner = a.owner.map { "\($0): " } ?? ""
                out += "- [\(a.done ? "x" : " ")] \(owner)\(a.task)\n"
            }
            out += "\n"
        }
        if !segments.isEmpty {
            out += "## Transcript\n"
            for s in segments {
                let mm = (s.startMs / 1000) / 60
                let ss = (s.startMs / 1000) % 60
                let ts = String(format: "%02d:%02d", mm, ss)
                out += "**\(ts) — \(s.speaker)**\n\(s.text)\n\n"
            }
        }

        try out.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -8
git add recapit/Markdown/ recapitTests/MarkdownStoreTests.swift recapit.xcodeproj
git commit -m "feat: MarkdownStore writes per-meeting .md with frontmatter"
```

---

## Phase B — Calendar + UI shell

### Task 5: CalendarMonitor + MeetingClassifier

**Files:**
- Create: `recapit/Calendar/CalendarMonitor.swift`, `recapit/Calendar/MeetingClassifier.swift`
- Create test: `recapitTests/MeetingClassifierTests.swift`

- [ ] **Step 1: Write failing tests for `MeetingClassifier`**

```swift
import XCTest
@testable import recapit

final class MeetingClassifierTests: XCTestCase {
    func testDetectsZoomURL() {
        let r = MeetingClassifier.classify(
            title: "Sync",
            notes: "Join: https://us02web.zoom.us/j/123456",
            location: nil,
            url: nil,
            attendeeCount: 1
        )
        XCTAssertEqual(r.isMeeting, true)
        XCTAssertEqual(r.detectedURL, URL(string: "https://us02web.zoom.us/j/123456"))
    }

    func testDetectsGoogleMeetURL() {
        let r = MeetingClassifier.classify(
            title: "Standup",
            notes: nil, location: "https://meet.google.com/abc-defg-hij",
            url: nil, attendeeCount: 1
        )
        XCTAssertEqual(r.isMeeting, true)
        XCTAssertNotNil(r.detectedURL)
    }

    func testDetectsTeamsURL() {
        let r = MeetingClassifier.classify(
            title: "Meeting", notes: nil, location: nil,
            url: URL(string: "https://teams.microsoft.com/l/meetup-join/abc"),
            attendeeCount: 0
        )
        XCTAssertEqual(r.isMeeting, true)
    }

    func testHonoursAttendeeCount() {
        let r = MeetingClassifier.classify(
            title: "Lunch", notes: nil, location: nil, url: nil, attendeeCount: 2
        )
        XCTAssertEqual(r.isMeeting, true)
    }

    func testIgnoresSolo() {
        let r = MeetingClassifier.classify(
            title: "Focus block", notes: nil, location: nil, url: nil, attendeeCount: 0
        )
        XCTAssertEqual(r.isMeeting, false)
    }
}
```

- [ ] **Step 2: Implement `recapit/Calendar/MeetingClassifier.swift`**

```swift
import Foundation

struct ClassifyResult {
    let isMeeting: Bool
    let detectedURL: URL?
}

enum MeetingClassifier {
    private static let urlPattern = #"(?i)https?://[^\s]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|whereby\.com|webex\.com|gotomeet|join\.me|hangouts\.google\.com)[^\s]*"#

    static func classify(title: String?, notes: String?, location: String?, url: URL?, attendeeCount: Int) -> ClassifyResult {
        let haystack = [notes ?? "", location ?? "", url?.absoluteString ?? "", title ?? ""].joined(separator: " ")
        if let detected = firstMatch(in: haystack) {
            return ClassifyResult(isMeeting: true, detectedURL: detected)
        }
        if attendeeCount >= 2 {
            return ClassifyResult(isMeeting: true, detectedURL: nil)
        }
        return ClassifyResult(isMeeting: false, detectedURL: nil)
    }

    private static func firstMatch(in s: String) -> URL? {
        guard let re = try? NSRegularExpression(pattern: urlPattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range),
              let r = Range(m.range, in: s) else { return nil }
        return URL(string: String(s[r]))
    }
}
```

- [ ] **Step 3: Implement `recapit/Calendar/CalendarMonitor.swift`**

```swift
import Foundation
import EventKit

struct UpcomingMeeting: Identifiable, Equatable {
    let id: String           // EventKit identifier
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String
    let attendeeNames: [String]
    let meetingURL: URL?
}

protocol CalendarMonitorDelegate: AnyObject {
    func calendarMonitor(_ monitor: CalendarMonitor, didUpdateUpcoming: [UpcomingMeeting])
    func calendarMonitor(_ monitor: CalendarMonitor, meetingStartingSoon: UpcomingMeeting)
    func calendarMonitor(_ monitor: CalendarMonitor, meetingNow: UpcomingMeeting)
}

final class CalendarMonitor {
    weak var delegate: CalendarMonitorDelegate?
    private let store = EKEventStore()
    private let settings: SettingsStore
    private var timer: Timer?
    private var alreadyNotifiedSoon = Set<String>()
    private var alreadyNotifiedNow = Set<String>()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func requestAccess() async -> Bool {
        do {
            if #available(macOS 14.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await withCheckedThrowingContinuation { cont in
                    store.requestAccess(to: .event) { granted, error in
                        if let e = error { cont.resume(throwing: e) } else { cont.resume(returning: granted) }
                    }
                }
            }
        } catch {
            return false
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let calendars = store.calendars(for: .event).filter { settings.watchedCalendars.isEmpty || settings.watchedCalendars.contains($0.calendarIdentifier) }
        let now = Date()
        let end = now.addingTimeInterval(24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = store.events(matching: predicate)

        var upcoming: [UpcomingMeeting] = []
        for ev in events {
            let classify = MeetingClassifier.classify(
                title: ev.title,
                notes: ev.notes,
                location: ev.location,
                url: ev.url,
                attendeeCount: (ev.attendees?.count ?? 1) - 1
            )
            guard classify.isMeeting else { continue }
            let m = UpcomingMeeting(
                id: ev.eventIdentifier,
                title: ev.title ?? "Untitled",
                startDate: ev.startDate,
                endDate: ev.endDate,
                calendarTitle: ev.calendar.title,
                attendeeNames: (ev.attendees ?? []).compactMap { $0.name },
                meetingURL: classify.detectedURL
            )
            upcoming.append(m)
        }

        delegate?.calendarMonitor(self, didUpdateUpcoming: upcoming)

        for m in upcoming {
            let secondsUntil = m.startDate.timeIntervalSinceNow
            if secondsUntil <= 60 && secondsUntil > -10 && !alreadyNotifiedSoon.contains(m.id) {
                alreadyNotifiedSoon.insert(m.id)
                delegate?.calendarMonitor(self, meetingStartingSoon: m)
            }
            if secondsUntil <= 0 && secondsUntil > -30 && !alreadyNotifiedNow.contains(m.id) {
                alreadyNotifiedNow.insert(m.id)
                delegate?.calendarMonitor(self, meetingNow: m)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -8
git add recapit/Calendar/ recapitTests/MeetingClassifierTests.swift recapit.xcodeproj
git commit -m "feat: CalendarMonitor + MeetingClassifier"
```

---

### Task 6: MenuBarController + minimal PopoverView (idle state)

**Files:**
- Create: `recapit/UI/MenuBarController.swift`, `recapit/UI/PopoverView.swift`, `recapit/UI/PopoverViewModel.swift`
- Modify: `recapit/App/recapitApp.swift` — wire it up

- [ ] **Step 1: Implement `recapit/UI/PopoverViewModel.swift`**

```swift
import Foundation
import Combine

@MainActor
final class PopoverViewModel: ObservableObject {
    @Published var upcoming: [UpcomingMeeting] = []
    @Published var recentMeetings: [Meeting] = []
    @Published var currentRecording: Meeting? = nil
    @Published var isProcessing: Bool = false

    func updateUpcoming(_ items: [UpcomingMeeting]) { upcoming = items }
    func updateRecent(_ items: [Meeting]) { recentMeetings = items }
}
```

- [ ] **Step 2: Implement `recapit/UI/PopoverView.swift`**

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var vm: PopoverViewModel
    let onCaptureNow: () -> Void
    let onOpenMainWindow: () -> Void
    let onJoin: (UpcomingMeeting) -> Void
    let onStop: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let r = vm.currentRecording {
                recordingCard(meeting: r)
                Divider()
            } else if vm.isProcessing {
                processingCard
                Divider()
            }
            upcomingList
            if !vm.recentMeetings.isEmpty {
                Divider()
                recentList
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Recapit").font(.headline)
            Spacer()
            Button(action: onCaptureNow) {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                    Text("Capture Now").font(.callout)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.37, green: 0.36, blue: 0.90))
            .controlSize(.small)
        }
        .padding(10)
    }

    private func recordingCard(meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .shadow(color: .red.opacity(0.7), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title).font(.callout).fontWeight(.semibold)
                Text("Recording · 03:42").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button("Stop") { onStop() }.controlSize(.small)
        }
        .padding(10)
    }

    private var processingCard: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.6)
            Text("Summarising…").font(.callout)
        }
        .padding(10)
    }

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UPCOMING TODAY")
                .font(.caption2).foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 8)
            if vm.upcoming.isEmpty {
                Text("No meetings in the next 24 hours.")
                    .font(.callout).foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            } else {
                ForEach(vm.upcoming) { m in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(m.title).font(.callout)
                            Text(m.startDate.formatted(date: .omitted, time: .shortened) + " · " + m.calendarTitle)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if m.meetingURL != nil {
                            Button("Join") { onJoin(m) }
                                .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT")
                .font(.caption2).foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 8)
            ForEach(vm.recentMeetings.prefix(3), id: \.id) { m in
                Button(action: { onOpenMainWindow() }) {
                    HStack {
                        Text(m.title).font(.callout)
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(m.startedAt))
                                .formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenMainWindow) {
                Text("Open Library").font(.caption)
            }.buttonStyle(.plain).foregroundColor(.accentColor)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape").foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(8)
    }
}
```

- [ ] **Step 3: Implement `recapit/UI/MenuBarController.swift`**

```swift
import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var clickOutsideMonitor: Any?
    let viewModel = PopoverViewModel()

    var onOpenMainWindow: () -> Void = {}
    var onSettings: () -> Void = {}
    var onCaptureNow: () -> Void = {}
    var onStop: () -> Void = {}
    var onJoin: (UpcomingMeeting) -> Void = { _ in }

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Recapit")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(toggle)
            button.target = self
        }
    }

    private func setupPopover() {
        let view = PopoverView(
            vm: viewModel,
            onCaptureNow: { [weak self] in self?.close(); self?.onCaptureNow() },
            onOpenMainWindow: { [weak self] in self?.close(); self?.onOpenMainWindow() },
            onJoin: { [weak self] m in self?.close(); self?.onJoin(m) },
            onStop: { [weak self] in self?.onStop() },
            onSettings: { [weak self] in self?.close(); self?.onSettings() }
        )
        let hosting = NSHostingController(rootView: view)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = .preferredContentSize
        }
        popover.contentViewController = hosting
        popover.behavior = .applicationDefined
        popover.animates = false
    }

    func setRecordingIcon(_ recording: Bool) {
        let name = recording ? "record.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Recapit")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func toggle() {
        if popover.isShown { close() } else { open() }
    }

    private func open() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func close() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
        popover.performClose(nil)
    }
}
```

- [ ] **Step 4: Wire up in `recapit/App/recapitApp.swift`**

```swift
import AppKit

@main
struct recapitApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
    }
}
```

- [ ] **Step 5: Build, run, verify icon appears**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
open ~/Library/Developer/Xcode/DerivedData/recapit-*/Build/Products/Debug/Recapit.app
```

Expected: menu bar icon appears (waveform.circle symbol). Click → empty popover with "Capture Now" button.

- [ ] **Step 6: Commit**

```bash
git add recapit/UI/{MenuBarController,PopoverView,PopoverViewModel}.swift recapit/App/recapitApp.swift recapit.xcodeproj
git commit -m "feat: MenuBarController + PopoverView idle state"
```

---

### Task 7: FirstRunWizard (permissions, mode, calendars)

**Files:**
- Create: `recapit/UI/FirstRunWizard.swift`

- [ ] **Step 1: Implement the wizard**

```swift
import SwiftUI
import AVFoundation
import EventKit
import ScreenCaptureKit

@MainActor
final class FirstRunWizardController {
    private let settings: SettingsStore
    private let calendarMonitor: CalendarMonitor
    private var window: NSWindow?

    init(settings: SettingsStore, calendarMonitor: CalendarMonitor) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
    }

    func showIfNeeded() {
        guard !settings.firstRunCompleted else { return }
        let view = FirstRunWizard(settings: settings,
                                  calendarMonitor: calendarMonitor,
                                  onClose: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Welcome to Recapit"
        w.setContentSize(NSSize(width: 520, height: 420))
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func close() {
        settings.firstRunCompleted = true
        window?.close()
        window = nil
    }
}

struct FirstRunWizard: View {
    @ObservedObject var settingsObserver: SettingsObserver
    let settings: SettingsStore
    let calendarMonitor: CalendarMonitor
    let onClose: () -> Void

    init(settings: SettingsStore, calendarMonitor: CalendarMonitor, onClose: @escaping () -> Void) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
        self.onClose = onClose
        self.settingsObserver = SettingsObserver(settings: settings)
    }

    @State private var step = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 12)

            Group {
                switch step {
                case 0: permissionsStep
                case 1: modeStep
                default: calendarStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step < 2 { Button("Next") { step += 1 }.keyboardShortcut(.defaultAction) }
                else { Button("Get started") { onClose() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }
            .padding(16)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions").font(.title2).bold()
            Text("Recapit needs three permissions. We'll request them one at a time.")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(name: "Calendar", description: "Detect upcoming meetings.") {
                    _ = await calendarMonitor.requestAccess()
                }
                permissionRow(name: "Microphone", description: "Record your voice.") {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                }
                permissionRow(name: "Screen Recording", description: "Capture system audio (other participants).") {
                    _ = try? await SCShareableContent.current
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private func permissionRow(name: String, description: String, request: @escaping () async -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).font(.callout).fontWeight(.medium)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Grant") {
                Task { await request() }
            }.controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing mode").font(.title2).bold()
            Text("Where should transcription and summaries run?").foregroundColor(.secondary)
            ForEach(ProcessingMode.allCases, id: \.self) { mode in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: settingsObserver.processingMode == mode ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName).font(.callout).fontWeight(.medium)
                        Text(modeBlurb(mode)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.secondary.opacity(settingsObserver.processingMode == mode ? 0.12 : 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { settingsObserver.processingMode = mode }
            }
            Spacer()
        }
        .padding(16)
    }

    private func modeBlurb(_ m: ProcessingMode) -> String {
        switch m {
        case .local: return "All processing on your Mac. No data leaves the machine. Slowest first run (model download)."
        case .cloud: return "Send audio to cloud providers (Deepgram, OpenAI, Anthropic). Fastest, highest quality."
        case .hybrid: return "Local transcription, cloud summarisation. Cheapest cloud setup."
        }
    }

    private var calendarStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendars to watch").font(.title2).bold()
            Text("Recapit polls these calendars every 30 seconds.").foregroundColor(.secondary)
            Text("You can change this later in Settings.").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

@MainActor
final class SettingsObserver: ObservableObject {
    @Published var processingMode: ProcessingMode {
        didSet { settings.processingMode = processingMode }
    }
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        self.processingMode = settings.processingMode
    }
}
```

- [ ] **Step 2: Wire into AppDelegate**

Replace `applicationDidFinishLaunching` body in `recapit/App/recapitApp.swift`:

```swift
    private var menuBar: MenuBarController?
    private var settings: SettingsStore!
    private var calendarMonitor: CalendarMonitor!
    private var firstRun: FirstRunWizardController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        calendarMonitor = CalendarMonitor(settings: settings)
        menuBar = MenuBarController()
        firstRun = FirstRunWizardController(settings: settings, calendarMonitor: calendarMonitor)
        firstRun.showIfNeeded()
        calendarMonitor.start()
    }
```

- [ ] **Step 3: Build, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
git add recapit/UI/FirstRunWizard.swift recapit/App/recapitApp.swift recapit.xcodeproj
git commit -m "feat: FirstRunWizard for permissions + mode + calendars"
```

---

### Task 8: MainWindow + LibrarySidebar + ReaderPane (read-only)

**Files:**
- Create: `recapit/UI/MainWindow.swift`, `recapit/UI/LibrarySidebar.swift`, `recapit/UI/ReaderPane.swift`

- [ ] **Step 1: Implement `recapit/UI/ReaderPane.swift`**

```swift
import SwiftUI

struct ReaderPane: View {
    let meeting: Meeting?
    let segments: [TranscriptSegment]
    let actionItems: [ActionItem]

    var body: some View {
        if let m = meeting {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(m)
                    if let p = m.preNotes, !p.isEmpty {
                        section(label: "PRE-MEETING NOTES") {
                            Text(p).font(.callout)
                        }
                    }
                    if let s = m.summary, !s.isEmpty {
                        section(label: "SUMMARY") {
                            Text(s).font(.callout).textSelection(.enabled)
                        }
                    }
                    if !actionItems.isEmpty {
                        section(label: "ACTION ITEMS") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(actionItems, id: \.id) { a in
                                    HStack {
                                        Image(systemName: a.done ? "checkmark.square" : "square")
                                        Text(a.owner.map { "**\($0)** — " }.flatMap { "\($0)" } ?? "")
                                            + Text(a.task)
                                    }.font(.callout)
                                }
                            }
                        }
                    }
                    section(label: "TRANSCRIPT") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(segments, id: \.id) { s in
                                let ts = String(format: "%02d:%02d", (s.startMs/1000)/60, (s.startMs/1000)%60)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(ts) — \(s.speaker)").font(.caption).foregroundColor(.secondary)
                                    Text(s.text).font(.callout).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        } else {
            VStack {
                Image(systemName: "waveform").font(.system(size: 48)).foregroundColor(.secondary)
                Text("Select a meeting").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ m: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.title).font(.title2).bold()
            Text(Date(timeIntervalSince1970: TimeInterval(m.startedAt))
                .formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func section<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }
}
```

- [ ] **Step 2: Implement `recapit/UI/LibrarySidebar.swift`**

```swift
import SwiftUI

struct LibrarySidebar: View {
    let meetings: [Meeting]
    @Binding var selectedId: String?

    var body: some View {
        List(selection: $selectedId) {
            ForEach(groupedMeetings(), id: \.label) { group in
                Section(group.label) {
                    ForEach(group.items, id: \.id) { m in
                        VStack(alignment: .leading) {
                            Text(m.title).font(.callout)
                            Text(Date(timeIntervalSince1970: TimeInterval(m.startedAt))
                                    .formatted(date: .omitted, time: .shortened))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .tag(m.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func groupedMeetings() -> [(label: String, items: [Meeting])] {
        let cal = Calendar.current
        var today: [Meeting] = []
        var yesterday: [Meeting] = []
        var thisWeek: [Meeting] = []
        var older: [Meeting] = []
        for m in meetings {
            let d = Date(timeIntervalSince1970: TimeInterval(m.startedAt))
            if cal.isDateInToday(d) { today.append(m) }
            else if cal.isDateInYesterday(d) { yesterday.append(m) }
            else if cal.isDate(d, equalTo: Date(), toGranularity: .weekOfYear) { thisWeek.append(m) }
            else { older.append(m) }
        }
        var out: [(String, [Meeting])] = []
        if !today.isEmpty { out.append(("TODAY", today)) }
        if !yesterday.isEmpty { out.append(("YESTERDAY", yesterday)) }
        if !thisWeek.isEmpty { out.append(("THIS WEEK", thisWeek)) }
        if !older.isEmpty { out.append(("OLDER", older)) }
        return out
    }
}
```

- [ ] **Step 3: Implement `recapit/UI/MainWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    private let db: MeetingDB
    private var window: NSWindow?

    init(db: MeetingDB) { self.db = db }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = MainWindow(db: db)
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Recapit"
        w.setContentSize(NSSize(width: 960, height: 620))
        w.styleMask = [.titled, .resizable, .closable, .miniaturizable]
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct MainWindow: View {
    let db: MeetingDB
    @State private var meetings: [Meeting] = []
    @State private var selectedId: String?
    @State private var segments: [TranscriptSegment] = []
    @State private var actionItems: [ActionItem] = []

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(meetings: meetings, selectedId: $selectedId)
                .frame(minWidth: 220)
        } detail: {
            ReaderPane(
                meeting: meetings.first { $0.id == selectedId },
                segments: segments,
                actionItems: actionItems
            )
        }
        .onAppear { reload() }
        .onChange(of: selectedId) { _, newId in
            guard let id = newId else { return }
            segments = (try? db.segments(meetingId: id)) ?? []
            actionItems = []
        }
    }

    private func reload() {
        meetings = (try? db.recentMeetings()) ?? []
        if selectedId == nil { selectedId = meetings.first?.id }
    }
}
```

- [ ] **Step 4: Wire into AppDelegate (add `MainWindowController` and connect to MenuBarController)**

Modify `applicationDidFinishLaunching`:

```swift
    private var mainWindow: MainWindowController?
    private var db: MeetingDB!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        let recapitDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Recapit")
        try? FileManager.default.createDirectory(at: recapitDir, withIntermediateDirectories: true)
        let dbPath = recapitDir.appendingPathComponent("recapit.sqlite").path
        db = try? MeetingDB(path: dbPath)

        calendarMonitor = CalendarMonitor(settings: settings)
        menuBar = MenuBarController()
        mainWindow = MainWindowController(db: db)
        menuBar?.onOpenMainWindow = { [weak self] in self?.mainWindow?.show() }

        firstRun = FirstRunWizardController(settings: settings, calendarMonitor: calendarMonitor)
        firstRun.showIfNeeded()
        calendarMonitor.start()
    }
```

- [ ] **Step 5: Build, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
git add recapit/UI/{MainWindow,LibrarySidebar,ReaderPane}.swift recapit/App/recapitApp.swift recapit.xcodeproj
git commit -m "feat: MainWindow with LibrarySidebar + ReaderPane"
```

---

## Phase C — Audio capture

### Task 9: AudioCaptureEngine — microphone channel

**Files:**
- Create: `recapit/Capture/AudioChunk.swift`, `recapit/Capture/AudioCaptureEngine.swift`

- [ ] **Step 1: Implement `recapit/Capture/AudioChunk.swift`**

```swift
import Foundation

enum AudioChannel: String {
    case mic
    case system
}

struct AudioChunk {
    let channel: AudioChannel
    let startMs: Int64           // ms since meeting start
    let durationMs: Int64
    let samples: [Float]         // 16 kHz mono Float32
}
```

- [ ] **Step 2: Implement `recapit/Capture/AudioCaptureEngine.swift` — mic only**

```swift
import AVFoundation
import Foundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCapture(_ engine: AudioCaptureEngine, chunk: AudioChunk)
    func audioCaptureDidFail(_ engine: AudioCaptureEngine, error: Error)
}

final class AudioCaptureEngine: NSObject {
    weak var delegate: AudioCaptureDelegate?
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private var startDate: Date?
    private var isRunning = false

    override init() {
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        super.init()
    }

    func startMic() throws {
        guard !isRunning else { return }
        let input = engine.inputNode

        // Enable hardware AEC / noise suppression
        if input.canPerformInputOutputUsingVoiceProcessingIOUnit {
            try input.setVoiceProcessingEnabled(true)
        }

        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        startDate = Date()
        isRunning = true

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.process(buffer: buffer, time: time)
        }
        try engine.start()
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        startDate = nil
    }

    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let converter = converter, let start = startDate else { return }
        let outBufCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        ) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outBufCapacity) else { return }

        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || outBuffer.frameLength == 0 { return }

        let frameCount = Int(outBuffer.frameLength)
        let ptr = outBuffer.floatChannelData![0]
        let samples = Array(UnsafeBufferPointer(start: ptr, count: frameCount))

        let elapsed = Date().timeIntervalSince(start)
        let durationMs = Int64(Double(frameCount) / outputFormat.sampleRate * 1000)
        let startMs = max(0, Int64(elapsed * 1000) - durationMs)

        let chunk = AudioChunk(channel: .mic, startMs: startMs, durationMs: durationMs, samples: samples)
        delegate?.audioCapture(self, chunk: chunk)
    }
}
```

- [ ] **Step 3: Smoke test by adding "Capture Now" → start mic, log RMS**

Add a temporary handler in `AppDelegate`:

```swift
    private var capture: AudioCaptureEngine?

    func smokeTestStartMic() {
        capture = AudioCaptureEngine()
        capture?.delegate = self
        do { try capture?.startMic() } catch { print("mic error: \(error)") }
    }
```

Conform `AppDelegate` to `AudioCaptureDelegate`:

```swift
extension AppDelegate: AudioCaptureDelegate {
    func audioCapture(_ engine: AudioCaptureEngine, chunk: AudioChunk) {
        let rms = sqrt(chunk.samples.reduce(0) { $0 + $1 * $1 } / Float(chunk.samples.count))
        NSLog("mic chunk @ %lld ms, %d samples, rms %.4f", chunk.startMs, chunk.samples.count, rms)
    }
    func audioCaptureDidFail(_ engine: AudioCaptureEngine, error: Error) {
        NSLog("mic fail: %@", String(describing: error))
    }
}
```

Wire `menuBar?.onCaptureNow = { [weak self] in self?.smokeTestStartMic() }`.

- [ ] **Step 4: Build, install, test**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
open ~/Library/Developer/Xcode/DerivedData/recapit-*/Build/Products/Debug/Recapit.app
```

Open Console.app, filter `Recapit`. Click Capture Now → speak → expect log lines with `rms > 0.01` while speaking.

- [ ] **Step 5: Commit**

```bash
git add recapit/Capture/ recapit/App/recapitApp.swift recapit.xcodeproj
git commit -m "feat: AudioCaptureEngine — mic channel via AVAudioEngine"
```

---

### Task 10: AudioCaptureEngine — system audio via ScreenCaptureKit

**Files:**
- Modify: `recapit/Capture/AudioCaptureEngine.swift`

- [ ] **Step 1: Extend `AudioCaptureEngine` with system audio**

Add to the class:

```swift
import ScreenCaptureKit

extension AudioCaptureEngine: SCStreamDelegate, SCStreamOutput {
    func startSystem() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw NSError(domain: "AudioCapture", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No display"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Drive ScreenCaptureKit minimally — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 10)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio,
                                    sampleHandlerQueue: DispatchQueue(label: "recapit.scstream"))
        try await stream.startCapture()
        self.scStream = stream
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        processSystemAudio(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        delegate?.audioCaptureDidFail(self, error: error)
    }

    private func processSystemAudio(_ buffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(buffer),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                          lengthAtOffsetOut: &lengthAtOffset,
                                          totalLengthOut: &totalLength,
                                          dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let pointer = dataPointer else { return }

        // Source format from ScreenCaptureKit is 48 kHz / 2ch / Float32 interleaved
        let frameCount = totalLength / (MemoryLayout<Float>.size * 2)
        var monoSamples = [Float](repeating: 0, count: frameCount)
        let floats = pointer.withMemoryRebound(to: Float.self, capacity: frameCount * 2) { $0 }
        for i in 0..<frameCount {
            monoSamples[i] = (floats[i * 2] + floats[i * 2 + 1]) * 0.5
        }

        // Downsample 48k → 16k (simple decimation by 3)
        var resampled = [Float]()
        resampled.reserveCapacity(frameCount / 3)
        var idx = 0
        while idx < frameCount {
            resampled.append(monoSamples[idx])
            idx += 3
        }

        guard let start = startDate else { return }
        let durationMs = Int64(Double(resampled.count) / 16_000 * 1000)
        let elapsed = Int64(Date().timeIntervalSince(start) * 1000)
        let startMs = max(0, elapsed - durationMs)

        let chunk = AudioChunk(channel: .system, startMs: startMs,
                               durationMs: durationMs, samples: resampled)
        delegate?.audioCapture(self, chunk: chunk)
    }
}
```

Add private property: `private var scStream: SCStream?`

And in `stop()`:

```swift
    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        Task { try? await scStream?.stopCapture() }
        scStream = nil
        isRunning = false
        startDate = nil
    }
```

Add `import CoreMedia` at top.

- [ ] **Step 2: Update smoke test to start both channels**

```swift
    func smokeTestStartMic() {
        capture = AudioCaptureEngine()
        capture?.delegate = self
        do {
            try capture?.startMic()
            Task { try? await self.capture?.startSystem() }
        } catch { print("capture error: \(error)") }
    }
```

- [ ] **Step 3: Build + grant Screen Recording permission**

```bash
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
open ~/Library/Developer/Xcode/DerivedData/recapit-*/Build/Products/Debug/Recapit.app
```

Grant Screen Recording permission in System Settings when prompted. Play music or a YouTube video — verify Console shows `system` channel chunks with rms > 0.

- [ ] **Step 4: Commit**

```bash
git add recapit/Capture/AudioCaptureEngine.swift recapit.xcodeproj
git commit -m "feat: system audio via ScreenCaptureKit, 48k→16k mono"
```

---

### Task 11: ChunkBuffer actor (orders, batches, emits 30s windows)

**Files:**
- Create: `recapit/Capture/ChunkBuffer.swift`
- Create test: `recapitTests/ChunkBufferTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import recapit

final class ChunkBufferTests: XCTestCase {
    func testEmits30sWindowWith5sOverlap() async {
        let buffer = ChunkBuffer()
        var emitted = [(channel: AudioChannel, startMs: Int64, endMs: Int64)]()
        await buffer.setHandler { (channel, startMs, samples) in
            emitted.append((channel, startMs, startMs + Int64(samples.count) * 1000 / 16_000))
        }
        // Push 35s of mic audio in 1-second chunks
        for i in 0..<35 {
            let samples = [Float](repeating: 0.1, count: 16_000)
            await buffer.append(AudioChunk(channel: .mic,
                                           startMs: Int64(i * 1000),
                                           durationMs: 1000,
                                           samples: samples))
        }
        await buffer.flush()
        XCTAssertGreaterThanOrEqual(emitted.count, 1)
        XCTAssertEqual(emitted.first?.startMs, 0)
        XCTAssertGreaterThanOrEqual(emitted.first!.endMs - emitted.first!.startMs, 25_000)
    }
}
```

- [ ] **Step 2: Implement `recapit/Capture/ChunkBuffer.swift`**

```swift
import Foundation

actor ChunkBuffer {
    private let windowSeconds: Int = 30
    private let overlapSeconds: Int = 5
    private let sampleRate: Int = 16_000

    private var micBuffer: [Float] = []
    private var micStartMs: Int64 = 0
    private var systemBuffer: [Float] = []
    private var systemStartMs: Int64 = 0

    private var handler: ((AudioChannel, Int64, [Float]) -> Void)?

    func setHandler(_ h: @escaping (AudioChannel, Int64, [Float]) -> Void) {
        handler = h
    }

    func append(_ chunk: AudioChunk) {
        switch chunk.channel {
        case .mic:
            if micBuffer.isEmpty { micStartMs = chunk.startMs }
            micBuffer.append(contentsOf: chunk.samples)
            maybeEmit(channel: .mic)
        case .system:
            if systemBuffer.isEmpty { systemStartMs = chunk.startMs }
            systemBuffer.append(contentsOf: chunk.samples)
            maybeEmit(channel: .system)
        }
    }

    func flush() {
        if !micBuffer.isEmpty { handler?(.mic, micStartMs, micBuffer); micBuffer = [] }
        if !systemBuffer.isEmpty { handler?(.system, systemStartMs, systemBuffer); systemBuffer = [] }
    }

    private func maybeEmit(channel: AudioChannel) {
        let buf: [Float]
        let start: Int64
        switch channel {
        case .mic: buf = micBuffer; start = micStartMs
        case .system: buf = systemBuffer; start = systemStartMs
        }
        let needed = windowSeconds * sampleRate
        guard buf.count >= needed else { return }
        let window = Array(buf.prefix(needed))
        handler?(channel, start, window)
        let keep = overlapSeconds * sampleRate
        let kept = Array(buf.suffix(buf.count - (needed - keep)))
        let advance = (needed - keep) * 1000 / sampleRate
        switch channel {
        case .mic:    micBuffer = kept;    micStartMs = start + Int64(advance)
        case .system: systemBuffer = kept; systemStartMs = start + Int64(advance)
        }
    }
}
```

- [ ] **Step 3: Run tests, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -8
git add recapit/Capture/ChunkBuffer.swift recapitTests/ChunkBufferTests.swift recapit.xcodeproj
git commit -m "feat: ChunkBuffer actor — 30s windows, 5s overlap"
```

---

## Phase D — Transcription + Diarization

### Task 12: ASRProvider protocol + WhisperKitProvider

**Files:**
- Create: `recapit/ASR/ASRProvider.swift`, `recapit/ASR/WhisperKitProvider.swift`, `recapit/ASR/TranscriptDeduper.swift`
- Create test: `recapitTests/TranscriptDeduperTests.swift`

- [ ] **Step 1: Write failing test for `TranscriptDeduper`**

```swift
import XCTest
@testable import recapit

final class TranscriptDeduperTests: XCTestCase {
    func testMergesOverlappingChunks() {
        let dedup = TranscriptDeduper()
        dedup.add("Hello there how are you doing today")
        let merged = dedup.add("how are you doing today my friend")
        XCTAssertEqual(merged, "Hello there how are you doing today my friend")
    }

    func testNoOverlapAppendsClean() {
        let dedup = TranscriptDeduper()
        dedup.add("First chunk.")
        let merged = dedup.add("Completely new.")
        XCTAssertEqual(merged, "First chunk. Completely new.")
    }
}
```

- [ ] **Step 2: Implement `recapit/ASR/TranscriptDeduper.swift`**

```swift
import Foundation

final class TranscriptDeduper {
    private var accumulated: String = ""
    private let overlapWords: Int = 30

    @discardableResult
    func add(_ newText: String) -> String {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if accumulated.isEmpty {
            accumulated = trimmed
            return accumulated
        }
        let prevTail = Array(accumulated.split(separator: " ").suffix(overlapWords))
        let newHead = Array(trimmed.split(separator: " ").prefix(overlapWords))
        let overlapLen = longestCommonSubsequenceTail(prevTail, newHead)
        if overlapLen == 0 {
            accumulated += " " + trimmed
        } else {
            let newWords = trimmed.split(separator: " ").dropFirst(overlapLen)
            if !newWords.isEmpty {
                accumulated += " " + newWords.joined(separator: " ")
            }
        }
        return accumulated
    }

    /// Longest run from end of `a` matching prefix of `b`.
    private func longestCommonSubsequenceTail<E: Equatable>(_ a: [E], _ b: [E]) -> Int {
        var best = 0
        let aLen = a.count
        let bLen = b.count
        for k in 1...min(aLen, bLen) {
            if Array(a.suffix(k)) == Array(b.prefix(k)) { best = k }
        }
        return best
    }
}
```

- [ ] **Step 3: Implement `recapit/ASR/ASRProvider.swift`**

```swift
import Foundation

struct ASRResult {
    let text: String
    let segments: [(startMs: Int64, endMs: Int64, text: String)]
}

protocol ASRProvider {
    func transcribe(samples: [Float], language: String?) async throws -> ASRResult
}

enum ASRError: Error {
    case modelNotLoaded
    case backendFailure(String)
}
```

- [ ] **Step 4: Implement `recapit/ASR/WhisperKitProvider.swift`**

```swift
import Foundation
import WhisperKit

final class WhisperKitProvider: ASRProvider {
    private var pipe: WhisperKit?
    private let modelName: String

    init(modelName: String) {
        self.modelName = modelName
    }

    func load() async throws {
        if pipe != nil { return }
        pipe = try await WhisperKit(model: modelName)
    }

    func transcribe(samples: [Float], language: String? = "en") async throws -> ASRResult {
        try await load()
        guard let pipe = pipe else { throw ASRError.modelNotLoaded }
        let options = DecodingOptions(language: language, withoutTimestamps: false)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let combinedText = results.map(\.text).joined(separator: " ")
        var segs: [(Int64, Int64, String)] = []
        for r in results {
            for s in r.segments {
                segs.append((Int64(s.start * 1000), Int64(s.end * 1000), s.text))
            }
        }
        return ASRResult(text: combinedText, segments: segs)
    }
}
```

- [ ] **Step 5: Run tests, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -8
git add recapit/ASR/ recapitTests/TranscriptDeduperTests.swift recapit.xcodeproj
git commit -m "feat: ASRProvider protocol + WhisperKitProvider + TranscriptDeduper"
```

---

### Task 13: DiarizationProvider + PyannoteProvider (ONNX Runtime)

**Files:**
- Create: `recapit/Diarization/DiarizationProvider.swift`, `recapit/Diarization/PyannoteProvider.swift`
- Add resource: `Resources/pyannote-segmentation-3.0.onnx` (downloaded at first run, not in repo)

Note: this task wires the API. The actual Pyannote ONNX model files (~30 MB total) are downloaded at first run from HuggingFace and cached under `~/Recapit/models/`. We don't bundle them in the app.

- [ ] **Step 1: Implement `recapit/Diarization/DiarizationProvider.swift`**

```swift
import Foundation

struct DiarizationSegment {
    let startMs: Int64
    let endMs: Int64
    let speakerId: String
}

protocol DiarizationProvider {
    func diarize(samples: [Float], startMs: Int64) async throws -> [DiarizationSegment]
}

enum DiarizationError: Error {
    case modelNotAvailable
    case inferenceFailure(String)
}
```

- [ ] **Step 2: Implement `recapit/Diarization/PyannoteProvider.swift`**

```swift
import Foundation
import onnxruntime_objc

final class PyannoteProvider: DiarizationProvider {
    private var session: ORTSession?
    private let modelURL: URL
    private let env: ORTEnv

    init() throws {
        env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let modelsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Recapit/models")
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        modelURL = modelsDir.appendingPathComponent("pyannote-segmentation-3.0.onnx")
    }

    func ensureModelDownloaded() async throws {
        if FileManager.default.fileExists(atPath: modelURL.path) { return }
        // Download from HuggingFace mirror; user can replace URL in Settings.
        let url = URL(string: "https://huggingface.co/pyannote/segmentation-3.0/resolve/main/pytorch_model.onnx")!
        let (tmpURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tmpURL, to: modelURL)
    }

    private func loadSession() throws -> ORTSession {
        if let s = session { return s }
        let opts = try ORTSessionOptions()
        try opts.setIntraOpNumThreads(2)
        let s = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)
        session = s
        return s
    }

    func diarize(samples: [Float], startMs: Int64) async throws -> [DiarizationSegment] {
        try await ensureModelDownloaded()
        let session = try loadSession()

        // Pyannote-segmentation-3.0 expects [1, 1, T] float32 at 16 kHz, 10s window.
        // For a 30s chunk we slide 3 windows. Simplification: take the first 10s,
        // return a single "Speaker_1" label for the whole chunk.
        // Full implementation: per-window inference + speaker change detection +
        // CAM++ embedding clustering.
        // Phase 1 ships the heuristic version; clustering arrives in v1.1.
        let durationMs = Int64(Double(samples.count) / 16.0)
        return [DiarizationSegment(startMs: startMs, endMs: startMs + durationMs, speakerId: "Speaker_1")]
    }
}
```

(The TODO inline above is documented in the spec as v1.1 work — Phase 1 ships with the single-speaker heuristic so the rest of the pipeline can be wired. Real Pyannote inference + CAM++ clustering lands as Task 13.5 below if time permits, or v1.1.)

- [ ] **Step 3: Wire into pipeline — speaker labelling**

Add a stub helper `recapit/Diarization/SpeakerLabeler.swift`:

```swift
import Foundation

enum SpeakerLabeler {
    /// Map mic samples → "You", system channel → diarized labels.
    static func label(channel: AudioChannel, segments: [DiarizationSegment]) -> [DiarizationSegment] {
        if channel == .mic {
            return segments.map { DiarizationSegment(startMs: $0.startMs, endMs: $0.endMs, speakerId: "You") }
        }
        return segments
    }
}
```

- [ ] **Step 4: Build, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
git add recapit/Diarization/ recapit.xcodeproj
git commit -m "feat: DiarizationProvider protocol + Pyannote ONNX stub (single-speaker heuristic) + SpeakerLabeler"
```

---

## Phase E — LLM + Summary

### Task 14: LLMProvider protocol + 4 concrete providers

**Files:**
- Create: `recapit/LLM/LLMProvider.swift`, `recapit/LLM/OllamaProvider.swift`, `recapit/LLM/OpenAIProvider.swift`, `recapit/LLM/AnthropicProvider.swift`, `recapit/LLM/OpenAICompatibleProvider.swift`
- Create test: `recapitTests/LLMProviderTests.swift`

- [ ] **Step 1: Write failing test using URLProtocol mock**

```swift
import XCTest
@testable import recapit

final class LLMProviderTests: XCTestCase {
    override class func setUp() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
    }

    func testOllamaCompleteRoundtrip() async throws {
        MockURLProtocol.responses = [
            "/api/generate": ("{\"response\":\"Summary here\",\"done\":true}", 200)
        ]
        let provider = OllamaProvider(baseURL: URL(string: "http://localhost:11434")!)
        let r = try await provider.complete("Test prompt", json: false, model: "llama3.1:8b")
        XCTAssertEqual(r, "Summary here")
    }
}

final class MockURLProtocol: URLProtocol {
    static var responses: [String: (String, Int)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        let (body, code) = Self.responses[path] ?? ("", 404)
        let resp = HTTPURLResponse(url: request.url!, statusCode: code,
                                   httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2: Implement `recapit/LLM/LLMProvider.swift`**

```swift
import Foundation

protocol LLMProvider {
    func complete(_ prompt: String, json: Bool, model: String) async throws -> String
    func embed(_ texts: [String], model: String) async throws -> [[Float]]
}

enum LLMError: Error, LocalizedError {
    case http(Int, String)
    case decode(String)
    case noKey

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decode(let msg): return "Decode error: \(msg)"
        case .noKey: return "API key not set"
        }
    }
}
```

- [ ] **Step 3: Implement `recapit/LLM/OllamaProvider.swift`**

```swift
import Foundation

final class OllamaProvider: LLMProvider {
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        if json {
            body["format"] = "json"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTP(response, data: data)
        struct Response: Decodable { let response: String }
        return try JSONDecoder().decode(Response.self, from: data).response
    }

    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        var out: [[Float]] = []
        for text in texts {
            let url = baseURL.appendingPathComponent("api/embeddings")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": text])
            let (data, resp) = try await URLSession.shared.data(for: req)
            try checkHTTP(resp, data: data)
            struct R: Decodable { let embedding: [Float] }
            out.append(try JSONDecoder().decode(R.self, from: data).embedding)
        }
        return out
    }

    private func checkHTTP(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
```

- [ ] **Step 4: Implement `recapit/LLM/OpenAIProvider.swift`**

```swift
import Foundation

final class OpenAIProvider: LLMProvider {
    let apiKey: String
    let baseURL: URL

    init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        let url = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]]
        ]
        if json {
            body["response_format"] = ["type": "json_object"]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        struct R: Decodable {
            struct Choice: Decodable { struct M: Decodable { let content: String }; let message: M }
            let choices: [Choice]
        }
        return try JSONDecoder().decode(R.self, from: data).choices.first?.message.content ?? ""
    }

    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        let url = baseURL.appendingPathComponent("embeddings")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "input": texts]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        struct R: Decodable { struct D: Decodable { let embedding: [Float] }; let data: [D] }
        return try JSONDecoder().decode(R.self, from: data).data.map(\.embedding)
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let h = resp as? HTTPURLResponse else { return }
        if h.statusCode >= 400 {
            throw LLMError.http(h.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
```

- [ ] **Step 5: Implement `recapit/LLM/AnthropicProvider.swift`**

```swift
import Foundation

final class AnthropicProvider: LLMProvider {
    let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        struct R: Decodable {
            struct C: Decodable { let text: String? }
            let content: [C]
        }
        return try JSONDecoder().decode(R.self, from: data).content.compactMap(\.text).joined()
    }

    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        // Anthropic has no embedding API at this writing. Recommend OpenAI for embeddings.
        throw LLMError.http(501, "Anthropic does not provide embeddings — switch embedding provider to OpenAI or Ollama in Settings.")
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        guard let h = resp as? HTTPURLResponse else { return }
        if h.statusCode >= 400 {
            throw LLMError.http(h.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
```

- [ ] **Step 6: Implement `recapit/LLM/OpenAICompatibleProvider.swift`**

```swift
import Foundation

final class OpenAICompatibleProvider: LLMProvider {
    private let inner: OpenAIProvider
    init(apiKey: String, baseURL: URL) {
        self.inner = OpenAIProvider(apiKey: apiKey, baseURL: baseURL)
    }
    func complete(_ prompt: String, json: Bool, model: String) async throws -> String {
        try await inner.complete(prompt, json: json, model: model)
    }
    func embed(_ texts: [String], model: String) async throws -> [[Float]] {
        try await inner.embed(texts, model: model)
    }
}
```

- [ ] **Step 7: Run tests, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -8
git add recapit/LLM/ recapitTests/LLMProviderTests.swift recapit.xcodeproj
git commit -m "feat: LLMProvider abstraction with Ollama/OpenAI/Anthropic/OpenAICompatible"
```

---

### Task 15: SummaryEngine — 3 passes with prompts

**Files:**
- Create: `recapit/Summary/SummaryPrompts.swift`, `recapit/Summary/SummaryEngine.swift`, `recapit/Summary/ActionItemExtractor.swift`

- [ ] **Step 1: Implement `recapit/Summary/SummaryPrompts.swift`**

```swift
import Foundation

enum SummaryPrompts {
    static func summary(transcript: String, preNotes: String?) -> String {
        let trimmed = preNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = trimmed, !p.isEmpty {
            return granolaStyle(transcript: transcript, preNotes: p)
        }
        return firefliesStyle(transcript: transcript)
    }

    static func actionItems(transcript: String) -> String {
        """
        Extract action items from this meeting transcript. Return strict JSON
        matching this schema:

        {
          "action_items": [{
            "task": "string (the thing to do)",
            "owner": "string (the person responsible) | null",
            "due": "string (ISO date) | null"
          }]
        }

        If no action items, return {"action_items": []}.

        Transcript:
        \(transcript)
        """
    }

    private static func firefliesStyle(transcript: String) -> String {
        """
        You are summarising a meeting transcript. Output Markdown with these exact sections:

        ## Overview
        One paragraph, max 3 sentences. The "what happened in this meeting" elevator pitch.

        ## Key points
        Bullet list of the most important things discussed, in chronological order.

        ## Decisions
        Things the participants agreed on or decided. If none, write "No explicit decisions made."

        ## Outline
        Sectioned by topic shift. Each section: bold title + 2-4 bullets.

        Transcript:
        \(transcript)
        """
    }

    private static func granolaStyle(transcript: String, preNotes: String) -> String {
        """
        You are filling in the user's pre-meeting notes with what was actually
        discussed in the meeting. Output Markdown that mirrors the user's bullet
        structure exactly, with their original text preserved verbatim and the
        actual discussion folded under each bullet as nested points (2 spaces
        of indent for the nested points).

        Be concise. If a bullet was not discussed, write "(not discussed)"
        under it. Do NOT invent content.

        Pre-meeting notes:
        \(preNotes)

        Transcript:
        \(transcript)
        """
    }
}
```

- [ ] **Step 2: Implement `recapit/Summary/ActionItemExtractor.swift`**

```swift
import Foundation

enum ActionItemExtractor {
    struct Decoded: Decodable {
        struct Item: Decodable {
            let task: String
            let owner: String?
            let due: String?
        }
        let action_items: [Item]
    }

    static func parse(_ json: String) -> [ActionItem]? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(Decoded.self, from: data) else { return nil }
        return decoded.action_items.enumerated().map { (idx, item) in
            ActionItem(
                id: nil,
                meetingId: "",                       // filled by caller
                task: item.task,
                owner: item.owner,
                due: item.due,
                done: false,
                position: idx
            )
        }
    }
}
```

- [ ] **Step 3: Implement `recapit/Summary/SummaryEngine.swift`**

```swift
import Foundation

final class SummaryEngine {
    let llm: LLMProvider
    let db: MeetingDB
    let markdown: MarkdownStore
    let summaryModel: String
    let embeddingModel: String

    init(llm: LLMProvider, db: MeetingDB, markdown: MarkdownStore,
         summaryModel: String, embeddingModel: String) {
        self.llm = llm
        self.db = db
        self.markdown = markdown
        self.summaryModel = summaryModel
        self.embeddingModel = embeddingModel
    }

    func process(meetingId: String) async throws {
        guard var meeting = try db.meeting(id: meetingId) else { return }
        meeting.state = .processing
        try db.updateMeeting(meeting)

        let segments = try db.segments(meetingId: meetingId)
        let transcript = segments.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")

        // Pass 1 — Summary
        let summaryPrompt = SummaryPrompts.summary(transcript: transcript, preNotes: meeting.preNotes)
        let summary = try await llm.complete(summaryPrompt, json: false, model: summaryModel)
        meeting.summary = summary
        try db.updateMeeting(meeting)

        // Pass 2 — Action items
        let actionsPrompt = SummaryPrompts.actionItems(transcript: transcript)
        let actionsJSON = try await llm.complete(actionsPrompt, json: true, model: summaryModel)
        let actions = (ActionItemExtractor.parse(actionsJSON) ?? []).map { item in
            var i = item; i.meetingId = meetingId; return i
        }
        for var a in actions {
            try db.dbQueue.write { try a.insert($0) }
        }

        // Pass 3 — Embeddings (best-effort, log on failure)
        do {
            let texts = segments.map(\.text)
            let _ = try await llm.embed(texts, model: embeddingModel)
            // sqlite-vec storage wired in Task 16
        } catch {
            NSLog("Embedding pass failed: %@", String(describing: error))
        }

        // Write markdown
        try markdown.write(
            meeting: meeting,
            preNotes: meeting.preNotes,
            summary: meeting.summary,
            actionItems: actions,
            segments: segments,
            attendees: (try? JSONDecoder().decode([String].self,
                       from: Data((meeting.attendees ?? "[]").utf8))) ?? []
        )

        meeting.state = .done
        try db.updateMeeting(meeting)
    }
}
```

- [ ] **Step 4: Commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
git add recapit/Summary/ recapit.xcodeproj
git commit -m "feat: SummaryEngine with 3-pass pipeline + hybrid Fireflies/Granola prompts"
```

---

### Task 16: Embeddings storage via sqlite-vec

**Files:**
- Create: `recapit/DB/EmbeddingStore.swift`

- [ ] **Step 1: Implement `recapit/DB/EmbeddingStore.swift`**

```swift
import Foundation
import GRDB
import SQLiteVec

final class EmbeddingStore {
    let db: MeetingDB
    private static var initialized = false

    init(db: MeetingDB) throws {
        self.db = db
        if !Self.initialized {
            try SQLiteVec.initialize()
            Self.initialized = true
        }
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS embeddings_768
                USING vec0(meeting_id TEXT, segment_id INTEGER, embedding FLOAT[768]);
                """)
            try dbConn.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS embeddings_1536
                USING vec0(meeting_id TEXT, segment_id INTEGER, embedding FLOAT[1536]);
                """)
        }
    }

    func upsert(meetingId: String, segmentId: Int64, embedding: [Float]) throws {
        let table = embedding.count == 768 ? "embeddings_768"
                  : embedding.count == 1536 ? "embeddings_1536"
                  : nil
        guard let table = table else { return }
        let blob = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO \(table)(meeting_id, segment_id, embedding) VALUES (?, ?, ?)
                """, arguments: [meetingId, segmentId, blob])
        }
    }

    func search(query: [Float], limit: Int = 20) throws -> [(meetingId: String, segmentId: Int64, distance: Float)] {
        let table = query.count == 768 ? "embeddings_768"
                 : query.count == 1536 ? "embeddings_1536"
                 : nil
        guard let table = table else { return [] }
        let blob = query.withUnsafeBufferPointer { Data(buffer: $0) }
        return try db.dbQueue.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT meeting_id, segment_id, distance
                FROM \(table)
                WHERE embedding MATCH ?
                ORDER BY distance
                LIMIT ?
                """, arguments: [blob, limit])
            return rows.map {
                ($0["meeting_id"] as String, $0["segment_id"] as Int64, $0["distance"] as Float)
            }
        }
    }
}
```

- [ ] **Step 2: Wire into `SummaryEngine.process()` — replace the embeddings block**

In `recapit/Summary/SummaryEngine.swift`, replace the `// Pass 3` block with:

```swift
        // Pass 3 — Embeddings
        do {
            let segs = try db.segments(meetingId: meetingId)
            let texts = segs.map(\.text)
            let embeddings = try await llm.embed(texts, model: embeddingModel)
            let store = try EmbeddingStore(db: db)
            for (seg, emb) in zip(segs, embeddings) {
                if let sid = seg.id {
                    try store.upsert(meetingId: meetingId, segmentId: sid, embedding: emb)
                }
            }
        } catch {
            NSLog("Embedding pass failed: %@", String(describing: error))
        }
```

- [ ] **Step 3: Build, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
git add recapit/DB/EmbeddingStore.swift recapit/Summary/SummaryEngine.swift recapit.xcodeproj
git commit -m "feat: EmbeddingStore with sqlite-vec — 768 + 1536 dim tables"
```

---

## Phase F — Coordinator + final UI

### Task 17: RecordingCoordinator state machine

**Files:**
- Create: `recapit/Coordinator/RecordingCoordinator.swift`

- [ ] **Step 1: Implement the coordinator**

```swift
import Foundation
import AppKit

@MainActor
protocol RecordingCoordinatorDelegate: AnyObject {
    func coordinator(_ c: RecordingCoordinator, didChangeState: RecordingCoordinator.State)
    func coordinator(_ c: RecordingCoordinator, recordingMeeting: Meeting)
    func coordinator(_ c: RecordingCoordinator, finishedMeeting: Meeting)
}

@MainActor
final class RecordingCoordinator: AudioCaptureDelegate {
    enum State: String { case idle, countdown, recording, processing }

    weak var delegate: RecordingCoordinatorDelegate?
    private(set) var state: State = .idle { didSet { delegate?.coordinator(self, didChangeState: state) } }
    private(set) var currentMeeting: Meeting?

    let db: MeetingDB
    let markdown: MarkdownStore
    let settings: SettingsStore
    let captureEngine = AudioCaptureEngine()
    let chunkBuffer = ChunkBuffer()
    let asr: ASRProvider
    let summaryEngine: () -> SummaryEngine

    private var countdownTimer: Timer?

    init(db: MeetingDB, markdown: MarkdownStore, settings: SettingsStore,
         asr: ASRProvider, summaryEngineFactory: @escaping () -> SummaryEngine) {
        self.db = db
        self.markdown = markdown
        self.settings = settings
        self.asr = asr
        self.summaryEngine = summaryEngineFactory
        captureEngine.delegate = self
        Task { await chunkBuffer.setHandler { [weak self] channel, startMs, samples in
            Task { await self?.transcribeWindow(channel: channel, startMs: startMs, samples: samples) }
        } }
    }

    func startCountdown(title: String, calendarEventId: String? = nil,
                        meetingURL: URL? = nil) {
        guard state == .idle else { return }
        state = .countdown
        let m = Meeting.draft(title: title, startedAt: Date().addingTimeInterval(TimeInterval(settings.countdownSeconds)))
        currentMeeting = m
        let seconds = settings.countdownSeconds
        var remaining = seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            remaining -= 1
            if remaining <= 0 {
                t.invalidate()
                Task { await self?.beginRecording(meetingURL: meetingURL) }
            }
        }
    }

    func cancelCountdown() {
        guard state == .countdown else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        currentMeeting = nil
        state = .idle
    }

    func startAdhoc() {
        startCountdown(title: "Untitled meeting · \(DateFormatter.iso.string(from: Date()))")
    }

    private func beginRecording(meetingURL: URL?) async {
        guard var meeting = currentMeeting else { return }
        meeting.startedAt = Int64(Date().timeIntervalSince1970)
        meeting.state = .recording
        try? db.insertMeeting(meeting)
        currentMeeting = meeting
        state = .recording
        delegate?.coordinator(self, recordingMeeting: meeting)

        if let url = meetingURL, settings.autoJoinCalendarURLs {
            NSWorkspace.shared.open(url)
        }

        do {
            try captureEngine.startMic()
            if !settings.skipSystemAudio {
                try await captureEngine.startSystem()
            }
        } catch {
            NSLog("capture start failed: %@", String(describing: error))
            state = .idle
        }
    }

    func stop() async {
        guard state == .recording, var meeting = currentMeeting else { return }
        captureEngine.stop()
        await chunkBuffer.flush()
        meeting.endedAt = Int64(Date().timeIntervalSince1970)
        meeting.state = .processing
        try? db.updateMeeting(meeting)
        state = .processing
        delegate?.coordinator(self, finishedMeeting: meeting)

        do {
            try await summaryEngine().process(meetingId: meeting.id)
        } catch {
            NSLog("summary failed: %@", String(describing: error))
        }
        state = .idle
        currentMeeting = nil
    }

    // MARK: - AudioCaptureDelegate
    nonisolated func audioCapture(_ engine: AudioCaptureEngine, chunk: AudioChunk) {
        Task { await self.chunkBuffer.append(chunk) }
    }
    nonisolated func audioCaptureDidFail(_ engine: AudioCaptureEngine, error: Error) {
        NSLog("audio capture failure: %@", String(describing: error))
    }

    private func transcribeWindow(channel: AudioChannel, startMs: Int64, samples: [Float]) async {
        guard let meetingId = currentMeeting?.id else { return }
        do {
            let result = try await asr.transcribe(samples: samples, language: "en")
            for seg in result.segments {
                let segment = TranscriptSegment(
                    id: nil, meetingId: meetingId, channel: channel.rawValue,
                    startMs: startMs + seg.startMs, endMs: startMs + seg.endMs,
                    speaker: channel == .mic ? "You" : "Speaker_1",
                    text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try db.appendSegment(segment)
            }
        } catch {
            NSLog("ASR window failed: %@", String(describing: error))
        }
    }
}

private extension DateFormatter {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
git add recapit/Coordinator/ recapit.xcodeproj
git commit -m "feat: RecordingCoordinator state machine"
```

---

### Task 18: CountdownNotification + AppDelegate wiring

**Files:**
- Create: `recapit/UI/CountdownNotification.swift`
- Modify: `recapit/App/recapitApp.swift`

- [ ] **Step 1: Implement `recapit/UI/CountdownNotification.swift`**

```swift
import Foundation
import UserNotifications

@MainActor
final class CountdownNotification: NSObject, UNUserNotificationCenterDelegate {
    static let joinActionId = "JOIN_RECORD"
    static let skipActionId = "SKIP"
    static let categoryId = "MEETING_SOON"

    var onJoin: ((String) -> Void)?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let join = UNNotificationAction(identifier: Self.joinActionId, title: "Join + Record", options: [.foreground])
        let skip = UNNotificationAction(identifier: Self.skipActionId, title: "Skip", options: [])
        let cat = UNNotificationCategory(identifier: Self.categoryId, actions: [join, skip],
                                          intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(meeting: UpcomingMeeting) {
        let content = UNMutableNotificationContent()
        content.title = meeting.title
        content.body = "Starts in 1 minute"
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["meetingId": meeting.id]
        content.sound = .default
        let req = UNNotificationRequest(identifier: "meeting.\(meeting.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["meetingId"] as? String ?? ""
        if response.actionIdentifier == Self.joinActionId {
            Task { @MainActor in self.onJoin?(id) }
        }
        completionHandler()
    }
}
```

- [ ] **Step 2: Wire the full pipeline in `recapit/App/recapitApp.swift`**

Replace `AppDelegate` body with:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate, CalendarMonitorDelegate, RecordingCoordinatorDelegate {
    private var menuBar: MenuBarController?
    private var settings: SettingsStore!
    private var calendarMonitor: CalendarMonitor!
    private var firstRun: FirstRunWizardController!
    private var mainWindow: MainWindowController?
    private var db: MeetingDB!
    private var markdown: MarkdownStore!
    private var coordinator: RecordingCoordinator!
    private var countdown: CountdownNotification!
    private var asr: ASRProvider!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        let recapitDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Recapit")
        try? FileManager.default.createDirectory(at: recapitDir, withIntermediateDirectories: true)
        db = try! MeetingDB(path: recapitDir.appendingPathComponent("recapit.sqlite").path)
        markdown = MarkdownStore(root: recapitDir)
        calendarMonitor = CalendarMonitor(settings: settings)
        calendarMonitor.delegate = self

        asr = WhisperKitProvider(modelName: settings.asrModel)

        coordinator = RecordingCoordinator(
            db: db, markdown: markdown, settings: settings, asr: asr,
            summaryEngineFactory: { [weak self] in
                guard let self else { fatalError() }
                let llm: LLMProvider = OllamaProvider()  // override per settings.llmProvider
                return SummaryEngine(llm: llm, db: self.db, markdown: self.markdown,
                                     summaryModel: self.settings.llmModel,
                                     embeddingModel: "nomic-embed-text")
            }
        )
        coordinator.delegate = self

        menuBar = MenuBarController()
        mainWindow = MainWindowController(db: db)
        menuBar?.onOpenMainWindow = { [weak self] in self?.mainWindow?.show() }
        menuBar?.onCaptureNow = { [weak self] in self?.coordinator?.startAdhoc() }
        menuBar?.onStop = { [weak self] in Task { await self?.coordinator?.stop() } }
        menuBar?.onJoin = { [weak self] m in
            self?.coordinator?.startCountdown(title: m.title, calendarEventId: m.id, meetingURL: m.meetingURL)
        }

        countdown = CountdownNotification()
        countdown.configure()
        countdown.onJoin = { [weak self] _ in
            guard let upcoming = self?.menuBar?.viewModel.upcoming.first else { return }
            self?.coordinator?.startCountdown(title: upcoming.title,
                                              calendarEventId: upcoming.id,
                                              meetingURL: upcoming.meetingURL)
        }

        firstRun = FirstRunWizardController(settings: settings, calendarMonitor: calendarMonitor)
        firstRun.showIfNeeded()
        calendarMonitor.start()
    }

    // MARK: - CalendarMonitorDelegate
    func calendarMonitor(_ monitor: CalendarMonitor, didUpdateUpcoming items: [UpcomingMeeting]) {
        Task { @MainActor in menuBar?.viewModel.updateUpcoming(items) }
    }
    func calendarMonitor(_ monitor: CalendarMonitor, meetingStartingSoon m: UpcomingMeeting) {
        Task { @MainActor in countdown.post(meeting: m) }
    }
    func calendarMonitor(_ monitor: CalendarMonitor, meetingNow m: UpcomingMeeting) {
        Task { @MainActor in
            coordinator.startCountdown(title: m.title, calendarEventId: m.id, meetingURL: m.meetingURL)
        }
    }

    // MARK: - RecordingCoordinatorDelegate
    func coordinator(_ c: RecordingCoordinator, didChangeState state: RecordingCoordinator.State) {
        menuBar?.setRecordingIcon(state == .recording)
        Task { @MainActor in
            menuBar?.viewModel.isProcessing = (state == .processing)
            menuBar?.viewModel.currentRecording = c.currentMeeting
        }
    }
    func coordinator(_ c: RecordingCoordinator, recordingMeeting m: Meeting) {}
    func coordinator(_ c: RecordingCoordinator, finishedMeeting m: Meeting) {
        Task { @MainActor in
            menuBar?.viewModel.updateRecent((try? db.recentMeetings()) ?? [])
        }
    }
}
```

- [ ] **Step 3: Build, commit**

```bash
cd /Users/joyson/recapit
xcodegen generate
xcodebuild -project recapit.xcodeproj -scheme recapit -destination 'platform=macOS' build 2>&1 | tail -3
git add recapit/UI/CountdownNotification.swift recapit/App/recapitApp.swift recapit.xcodeproj
git commit -m "feat: CountdownNotification + full AppDelegate pipeline wire-up"
```

---

### Task 19: Manual E2E smoke test + DMG release

**Files:**
- Create: `scripts/build-dmg.sh`
- Create: `docs/SMOKE_TESTS.md`

- [ ] **Step 1: Create the build script**

```bash
mkdir -p /Users/joyson/recapit/scripts
cat > /Users/joyson/recapit/scripts/build-dmg.sh << 'EOF'
#!/bin/bash
set -e
cd /Users/joyson/recapit
xcodebuild -project recapit.xcodeproj -scheme recapit -configuration Release \
  -derivedDataPath build ONLY_ACTIVE_ARCH=NO build
APP_PATH="build/Build/Products/Release/Recapit.app"
DMG_NAME="recapit-1.0.0.dmg"
hdiutil create -volname "Recapit" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_NAME"
echo "Done: $DMG_NAME"
EOF
chmod +x /Users/joyson/recapit/scripts/build-dmg.sh
```

- [ ] **Step 2: Create `docs/SMOKE_TESTS.md`**

```bash
mkdir -p /Users/joyson/recapit/docs
cat > /Users/joyson/recapit/docs/SMOKE_TESTS.md << 'EOF'
# Recapit smoke test checklist

Before each release, run through every item.

## 1. First-run wizard
- [ ] Delete `~/Library/Preferences/com.joyson.recapit.plist`
- [ ] Open Recapit
- [ ] All three permission prompts appear in order
- [ ] Processing mode defaults to Local
- [ ] Calendar list populates

## 2. Calendar trigger
- [ ] Add a calendar event with a Zoom URL starting in 90 seconds
- [ ] Wait → notification at T-60s
- [ ] Notification has "Join + Record" action
- [ ] Tap action → countdown starts → recording begins

## 3. Ad-hoc recording
- [ ] Click menu bar icon → "Capture Now"
- [ ] Countdown elapses → recording state
- [ ] Speak → check Console for ASR output
- [ ] Click Stop → processing state → done

## 4. Output
- [ ] `~/Pictures/Screenshots` has no new files (audio cleanup default)
- [ ] `~/Recapit/notes/{id}.md` exists with frontmatter + transcript + summary
- [ ] Main window shows the meeting in sidebar
- [ ] Reader pane shows summary + action items

## 5. Settings + provider switching
- [ ] Open Settings → switch to Cloud mode → enter OpenAI key → Test → ✓
- [ ] Record a short meeting → verify summary uses OpenAI
- [ ] Switch back to Local → verify Ollama summary works (with Ollama running locally)
EOF
```

- [ ] **Step 3: Run all unit tests + smoke test the build**

```bash
cd /Users/joyson/recapit
xcodebuild test -project recapit.xcodeproj -scheme recapitTests -destination 'platform=macOS' 2>&1 | tail -10
bash scripts/build-dmg.sh
ls -lh recapit-1.0.0.dmg
```

Manually follow `docs/SMOKE_TESTS.md`.

- [ ] **Step 4: Commit + tag**

```bash
cd /Users/joyson/recapit
git add scripts/ docs/
git commit -m "chore: DMG build script + smoke test checklist"
git tag v1.0.0
gh repo create joyson-fernandes/recapit --public --description "Local-first AI meeting note-taker for macOS"
git remote add origin https://github.com/joyson-fernandes/recapit.git
git push -u origin main --tags
gh release create v1.0.0 recapit-1.0.0.dmg --title "Recapit v1.0.0" --notes "Phase 1 MVP — local-first AI meeting notes for macOS."
```

---

## Deferred to v1.1 (acknowledged scope cuts)

These are intentionally not in Phase 1 to keep the build under 6 weeks. Add them once Phase 1 is stable.

### Task 20 (v1.1): NotesWindow — Granola-style split view
A separate `NSWindow` that opens automatically when recording starts:
- Left: editable Markdown notes pane (saved to `meeting.preNotes` on stop)
- Right: live transcript stream that auto-scrolls
- Top bar: title + elapsed timer + Stop button

### Task 21 (v1.1): SettingsView
SwiftUI `NSWindow`-mounted settings sheet matching the spec's settings layout:
- Processing mode + provider config + API key fields (write to `KeychainStore`)
- Hotkey recorder fields (reuse the klip `HotkeyRecorderView` pattern)
- Calendar selection
- Disk usage row + "Clean up old audio" button
- "Test connection" button per API key (calls `LLMProvider.complete("ping", json: false, model: ...)`)

### Task 22 (v1.1): Real Pyannote ONNX diarization
Replace `PyannoteProvider.diarize()` heuristic with:
1. Slide 10s windows over the 30s chunk
2. Run `segmentation-3.0.onnx` per window — outputs speaker activity matrix
3. Run `wespeaker_en_voxceleb_CAM++.onnx` to get embeddings for each segment
4. Cluster embeddings (agglomerative clustering, cosine distance) to assign global speaker IDs
5. Reference: OpenWhispr's blog post + `pyannote-audio` ONNX export docs

### Task 23 (v1.1): Search UI in MainWindow
Toolbar search field with two modes:
- **Keyword**: calls `MeetingDB.searchTranscripts(query)` → FTS5 hits
- **Semantic**: calls `EmbeddingStore.search(query: queryEmbedding)` → vec0 nearest-neighbour
Mode toggle in the search field as a segmented control.

### Task 24 (v1.1): Hotkey support
Port `HotkeyManager` + `HotkeyRecorderView` from klip. Wire to start/stop/ad-hoc actions.

### Task 25 (v1.1): Speaker rename UI
Inline-editable speaker name in the ReaderPane. Persists to `speakers` table.

### Task 26 (v1.1): Auto-update via Sparkle
Wire the Sparkle framework for daily auto-update checks against GitHub releases feed.
