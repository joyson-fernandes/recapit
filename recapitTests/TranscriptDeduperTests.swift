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
