import SwiftUI

struct ReaderPane: View {
    let meeting: Meeting?
    let segments: [TranscriptSegment]
    let actionItems: [ActionItem]

    var body: some View {
        if let m = meeting {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(m)
                    if let p = m.preNotes, !p.isEmpty {
                        section(label: "PRE-MEETING NOTES") {
                            Text(p).font(.callout)
                        }
                    }
                    if let s = m.summary, !s.isEmpty {
                        section(label: "SUMMARY") {
                            Text(s).font(.callout).textSelection(.enabled)
                        }
                    }
                    if !actionItems.isEmpty {
                        section(label: "ACTION ITEMS") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(actionItems, id: \.id) { a in
                                    HStack {
                                        Image(systemName: a.done ? "checkmark.square" : "square")
                                        if let owner = a.owner {
                                            (Text("**\(owner)** — ").bold() + Text(a.task)).font(.callout)
                                        } else {
                                            Text(a.task).font(.callout)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    section(label: "TRANSCRIPT") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(segments, id: \.id) { s in
                                let ts = String(format: "%02d:%02d", (s.startMs/1000)/60, (s.startMs/1000)%60)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(ts) — \(s.speaker)").font(.caption).foregroundColor(.secondary)
                                    Text(s.text).font(.callout).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        } else {
            VStack {
                Image(systemName: "waveform").font(.system(size: 48)).foregroundColor(.secondary)
                Text("Select a meeting").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ m: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.title).font(.title2).bold()
            Text(Date(timeIntervalSince1970: TimeInterval(m.startedAt))
                .formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func section<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }
}
