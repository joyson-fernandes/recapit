import Foundation
import GRDB

enum MeetingState: String, Codable {
    case recording, processing, done, failed
}

struct Meeting: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "meetings"

    var id: String
    var title: String
    var startedAt: Int64
    var endedAt: Int64?
    var calendarEvent: String?
    var preNotes: String?
    var markdownPath: String
    var audioPath: String?
    var summary: String?
    var attendees: String?
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
