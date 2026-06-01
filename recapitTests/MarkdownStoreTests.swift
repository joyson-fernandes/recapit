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
