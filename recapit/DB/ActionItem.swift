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
