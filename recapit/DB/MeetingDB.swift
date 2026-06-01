import Foundation
import GRDB

final class MeetingDB {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        for (name, body) in DBMigration.all {
            migrator.registerMigration(name, migrate: body)
        }
        try migrator.migrate(dbQueue)
    }

    @discardableResult
    func insertMeeting(_ meeting: Meeting) throws -> String {
        try dbQueue.write { db in
            var m = meeting
            try m.insert(db)
        }
        return meeting.id
    }

    func meeting(id: String) throws -> Meeting? {
        try dbQueue.read { db in
            try Meeting.fetchOne(db, key: id)
        }
    }

    func updateMeeting(_ meeting: Meeting) throws {
        try dbQueue.write { db in
            var m = meeting
            m.updatedAt = Int64(Date().timeIntervalSince1970)
            try m.update(db)
        }
    }

    func appendSegment(_ segment: TranscriptSegment) throws {
        try dbQueue.write { db in
            var s = segment
            try s.insert(db)
        }
    }

    func segments(meetingId: String) throws -> [TranscriptSegment] {
        try dbQueue.read { db in
            try TranscriptSegment
                .filter(Column("meeting_id") == meetingId)
                .order(Column("start_ms"))
                .fetchAll(db)
        }
    }

    func searchTranscripts(_ query: String) throws -> [(meetingId: String, segmentId: Int64, text: String)] {
        try dbQueue.read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
                    ?? FTS5Pattern(matchingAllTokensIn: query) else {
                return []
            }
            // Join back to transcript_segments via rowid (= segment id) to retrieve stored columns.
            // FTS5 MATCH must reference the virtual table by name, not alias.
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.meeting_id, s.id AS segment_id, s.text
                FROM transcript_fts
                JOIN transcript_segments s ON s.id = transcript_fts.rowid
                WHERE transcript_fts MATCH ?
                ORDER BY rank
                LIMIT 100
                """, arguments: [pattern.rawPattern])
            return rows.map {
                ($0["meeting_id"] as String, $0["segment_id"] as Int64, $0["text"] as String)
            }
        }
    }

    func recentMeetings(limit: Int = 100) throws -> [Meeting] {
        try dbQueue.read { db in
            try Meeting.order(Column("started_at").desc).limit(limit).fetchAll(db)
        }
    }
}
