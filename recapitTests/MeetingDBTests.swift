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
            id: nil, meetingId: id, channel: "mic",
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
            id: nil, meetingId: id, channel: "system", startMs: 0, endMs: 100,
            speaker: "Speaker_1", text: "kubernetes deployment failed"
        ))
        let hits = try db.searchTranscripts("kubernetes")
        XCTAssertEqual(hits.count, 1)
    }
}
