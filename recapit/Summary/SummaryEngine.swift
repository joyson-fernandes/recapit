import Foundation
import GRDB

final class SummaryEngine {
    let llm: LLMProvider
    let db: MeetingDB
    let markdown: MarkdownStore
    let summaryModel: String
    let embeddingModel: String

    init(llm: LLMProvider, db: MeetingDB, markdown: MarkdownStore,
         summaryModel: String, embeddingModel: String) {
        self.llm = llm
        self.db = db
        self.markdown = markdown
        self.summaryModel = summaryModel
        self.embeddingModel = embeddingModel
    }

    func process(meetingId: String) async throws {
        guard var meeting = try db.meeting(id: meetingId) else { return }
        meeting.state = .processing
        try db.updateMeeting(meeting)

        let segments = try db.segments(meetingId: meetingId)
        let transcript = segments.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")

        // Pass 1 — Summary
        let summaryPrompt = SummaryPrompts.summary(transcript: transcript, preNotes: meeting.preNotes)
        let summary = try await llm.complete(summaryPrompt, json: false, model: summaryModel)
        meeting.summary = summary
        try db.updateMeeting(meeting)

        // Pass 2 — Action items
        let actionsPrompt = SummaryPrompts.actionItems(transcript: transcript)
        let actionsJSON = try await llm.complete(actionsPrompt, json: true, model: summaryModel)
        let actions = (ActionItemExtractor.parse(actionsJSON) ?? []).map { item in
            var i = item; i.meetingId = meetingId; return i
        }
        for var a in actions {
            try await db.dbQueue.write { try a.insert($0) }
        }

        // Pass 3 — Embeddings
        do {
            let segs = try db.segments(meetingId: meetingId)
            let texts = segs.map(\.text)
            let embeddings = try await llm.embed(texts, model: embeddingModel)
            let store = EmbeddingStore(db: db)
            for (seg, emb) in zip(segs, embeddings) {
                if let sid = seg.id {
                    try await store.upsert(meetingId: meetingId, segmentId: sid, embedding: emb)
                }
            }
        } catch {
            NSLog("Embedding pass failed: %@", String(describing: error))
        }

        // Write markdown
        try markdown.write(
            meeting: meeting,
            preNotes: meeting.preNotes,
            summary: meeting.summary,
            actionItems: actions,
            segments: segments,
            attendees: (try? JSONDecoder().decode([String].self,
                       from: Data((meeting.attendees ?? "[]").utf8))) ?? []
        )

        meeting.state = .done
        try db.updateMeeting(meeting)
    }
}
