import Foundation

final class MarkdownStore {
    let root: URL
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
    }

    @discardableResult
    func write(meeting: Meeting,
               preNotes: String?,
               summary: String?,
               actionItems: [ActionItem],
               segments: [TranscriptSegment],
               attendees: [String]) throws -> URL {
        let url = root.appendingPathComponent(meeting.markdownPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var out = "---\n"
        out += "title: \(meeting.title)\n"
        out += "date: \(isoFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(meeting.startedAt))))\n"
        if !attendees.isEmpty {
            out += "attendees: [\(attendees.joined(separator: ", "))]\n"
        }
        if let ended = meeting.endedAt {
            let durationMin = (ended - meeting.startedAt) / 60
            out += "duration: \(durationMin)m\n"
        }
        out += "processing_mode: \(meeting.processingMode)\n"
        out += "---\n\n"
        out += "# \(meeting.title)\n\n"

        if let p = preNotes, !p.isEmpty {
            out += "## Pre-meeting notes\n\(p)\n\n"
        }
        if let s = summary, !s.isEmpty {
            out += "## Summary\n\(s)\n\n"
        }
        if !actionItems.isEmpty {
            out += "## Action items\n"
            for a in actionItems {
                let owner = a.owner.map { "\($0): " } ?? ""
                out += "- [\(a.done ? "x" : " ")] \(owner)\(a.task)\n"
            }
            out += "\n"
        }
        if !segments.isEmpty {
            out += "## Transcript\n"
            for s in segments {
                let mm = (s.startMs / 1000) / 60
                let ss = (s.startMs / 1000) % 60
                let ts = String(format: "%02d:%02d", mm, ss)
                out += "**\(ts) — \(s.speaker)**\n\(s.text)\n\n"
            }
        }

        try out.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
