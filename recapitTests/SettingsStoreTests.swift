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
