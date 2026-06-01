import GRDB

enum DBMigration: String {
    case v1 = "v1_initial"

    static var all: [(String, (Database) throws -> Void)] {
        [
            (DBMigration.v1.rawValue, v1)
        ]
    }

    private static func v1(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE meetings (
          id              TEXT PRIMARY KEY,
          title           TEXT NOT NULL,
          started_at      INTEGER NOT NULL,
          ended_at        INTEGER,
          calendar_event  TEXT,
          pre_notes       TEXT,
          markdown_path   TEXT NOT NULL,
          audio_path      TEXT,
          summary         TEXT,
          attendees       TEXT,
          meeting_url     TEXT,
          state           TEXT NOT NULL,
          processing_mode TEXT NOT NULL,
          created_at      INTEGER NOT NULL,
          updated_at      INTEGER NOT NULL
        );
        """)
        try db.execute(sql: "CREATE INDEX idx_meetings_started_at ON meetings(started_at DESC);")
        try db.execute(sql: "CREATE INDEX idx_meetings_state ON meetings(state);")

        try db.execute(sql: """
        CREATE TABLE transcript_segments (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
          channel         TEXT NOT NULL,
          start_ms        INTEGER NOT NULL,
          end_ms          INTEGER NOT NULL,
          speaker         TEXT NOT NULL,
          text            TEXT NOT NULL
        );
        """)
        try db.execute(sql: "CREATE INDEX idx_segments_meeting ON transcript_segments(meeting_id, start_ms);")

        try db.execute(sql: """
        CREATE VIRTUAL TABLE transcript_fts USING fts5(
          text, meeting_id UNINDEXED, segment_id UNINDEXED,
          content='transcript_segments', content_rowid='id'
        );
        """)
        try db.execute(sql: """
        CREATE TRIGGER transcript_ai AFTER INSERT ON transcript_segments BEGIN
          INSERT INTO transcript_fts(rowid, text, meeting_id, segment_id)
          VALUES (new.id, new.text, new.meeting_id, new.id);
        END;
        """)

        try db.execute(sql: """
        CREATE TABLE speakers (
          meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
          speaker_id      TEXT NOT NULL,
          display_name    TEXT NOT NULL,
          PRIMARY KEY (meeting_id, speaker_id)
        );
        """)

        try db.execute(sql: """
        CREATE TABLE action_items (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
          task            TEXT NOT NULL,
          owner           TEXT,
          due             TEXT,
          done            INTEGER NOT NULL DEFAULT 0,
          position        INTEGER NOT NULL
        );
        """)

        try db.execute(sql: """
        CREATE TABLE meeting_overrides (
          calendar_event  TEXT PRIMARY KEY,
          recurring_id    TEXT,
          rule            TEXT NOT NULL
        );
        """)
        try db.execute(sql: """
        CREATE TABLE meeting_embeddings (
          meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
          segment_id      INTEGER NOT NULL,
          dimension       INTEGER NOT NULL,
          embedding_json  TEXT NOT NULL,
          PRIMARY KEY (meeting_id, segment_id)
        );
        """)
        try db.execute(sql: "CREATE INDEX idx_meeting_embeddings_meeting ON meeting_embeddings(meeting_id);")
    }
}
