import SwiftUI

struct LibrarySidebar: View {
    let meetings: [Meeting]
    @Binding var selectedId: String?

    var body: some View {
        List(selection: $selectedId) {
            ForEach(groupedMeetings(), id: \.label) { group in
                Section(group.label) {
                    ForEach(group.items, id: \.id) { m in
                        VStack(alignment: .leading) {
                            Text(m.title).font(.callout)
                            Text(Date(timeIntervalSince1970: TimeInterval(m.startedAt))
                                    .formatted(date: .omitted, time: .shortened))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .tag(m.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private struct Group: Identifiable {
        let label: String
        let items: [Meeting]
        var id: String { label }
    }

    private func groupedMeetings() -> [Group] {
        let cal = Calendar.current
        var today: [Meeting] = []
        var yesterday: [Meeting] = []
        var thisWeek: [Meeting] = []
        var older: [Meeting] = []
        for m in meetings {
            let d = Date(timeIntervalSince1970: TimeInterval(m.startedAt))
            if cal.isDateInToday(d) { today.append(m) }
            else if cal.isDateInYesterday(d) { yesterday.append(m) }
            else if cal.isDate(d, equalTo: Date(), toGranularity: .weekOfYear) { thisWeek.append(m) }
            else { older.append(m) }
        }
        var out: [Group] = []
        if !today.isEmpty { out.append(Group(label: "TODAY", items: today)) }
        if !yesterday.isEmpty { out.append(Group(label: "YESTERDAY", items: yesterday)) }
        if !thisWeek.isEmpty { out.append(Group(label: "THIS WEEK", items: thisWeek)) }
        if !older.isEmpty { out.append(Group(label: "OLDER", items: older)) }
        return out
    }
}
