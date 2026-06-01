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
