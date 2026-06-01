import SwiftUI

struct PopoverView: View {
    @ObservedObject var vm: PopoverViewModel
    let onCaptureNow: () -> Void
    let onOpenMainWindow: () -> Void
    let onJoin: (UpcomingMeeting) -> Void
    let onStop: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let r = vm.currentRecording {
                recordingCard(meeting: r)
                Divider()
            } else if vm.isProcessing {
                processingCard
                Divider()
            }
            upcomingList
            if !vm.recentMeetings.isEmpty {
                Divider()
                recentList
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Recapit").font(.headline)
            Spacer()
            Button(action: onCaptureNow) {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle")
                    Text("Capture Now").font(.callout)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.37, green: 0.36, blue: 0.90))
            .controlSize(.small)
        }
        .padding(10)
    }

    private func recordingCard(meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .shadow(color: .red.opacity(0.7), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title).font(.callout).fontWeight(.semibold)
                Text("Recording · 03:42").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button("Stop") { onStop() }.controlSize(.small)
        }
        .padding(10)
    }

    private var processingCard: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.6)
            Text("Summarising…").font(.callout)
        }
        .padding(10)
    }

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UPCOMING TODAY")
                .font(.caption2).foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 8)
            if vm.upcoming.isEmpty {
                Text("No meetings in the next 24 hours.")
                    .font(.callout).foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            } else {
                ForEach(vm.upcoming) { m in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(m.title).font(.callout)
                            Text(m.startDate.formatted(date: .omitted, time: .shortened) + " · " + m.calendarTitle)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if m.meetingURL != nil {
                            Button("Join") { onJoin(m) }
                                .buttonStyle(.bordered).controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT")
                .font(.caption2).foregroundColor(.secondary).padding(.horizontal, 10).padding(.top, 8)
            ForEach(vm.recentMeetings.prefix(3), id: \.id) { m in
                Button(action: { onOpenMainWindow() }) {
                    HStack {
                        Text(m.title).font(.callout)
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(m.startedAt))
                                .formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenMainWindow) {
                Text("Open Library").font(.caption)
            }.buttonStyle(.plain).foregroundColor(.accentColor)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape").foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(8)
    }
}
