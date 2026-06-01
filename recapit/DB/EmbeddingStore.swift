import Foundation
import GRDB

/// Simple embedding storage as JSON blobs.
///
/// v1.1 will replace this with sqlite-vec for actual nearest-neighbour search.
/// For Phase 1 we just persist embeddings so they're available later.
final class EmbeddingStore {
    let db: MeetingDB

    init(db: MeetingDB) {
        self.db = db
    }

    func upsert(meetingId: String, segmentId: Int64, embedding: [Float]) async throws {
        let json = try JSONEncoder().encode(embedding)
        let jsonString = String(data: json, encoding: .utf8) ?? "[]"
        try await db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT OR REPLACE INTO meeting_embeddings(meeting_id, segment_id, dimension, embedding_json)
                VALUES (?, ?, ?, ?)
                """, arguments: [meetingId, segmentId, embedding.count, jsonString])
        }
    }

    /// Read all embeddings for a meeting. v1.1 will use this for in-memory cosine search.
    func embeddings(meetingId: String) async throws -> [(segmentId: Int64, embedding: [Float])] {
        try await db.dbQueue.read { dbConn -> [(Int64, [Float])] in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT segment_id, embedding_json
                FROM meeting_embeddings
                WHERE meeting_id = ?
                ORDER BY segment_id
                """, arguments: [meetingId])
            var out: [(Int64, [Float])] = []
            for row in rows {
                let segmentId: Int64 = row["segment_id"]
                let jsonString: String = row["embedding_json"]
                let data = Data(jsonString.utf8)
                if let arr = try? JSONDecoder().decode([Float].self, from: data) {
                    out.append((segmentId, arr))
                }
            }
            return out
        }
    }
}
