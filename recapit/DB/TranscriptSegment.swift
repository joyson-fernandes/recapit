import Foundation
import GRDB

struct TranscriptSegment: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcript_segments"
    var id: Int64?
    var meetingId: String
    var channel: String
    var startMs: Int64
    var endMs: Int64
    var speaker: String
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
