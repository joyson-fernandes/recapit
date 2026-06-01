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
