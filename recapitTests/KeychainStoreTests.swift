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
