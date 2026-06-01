import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    private let db: MeetingDB
    private var window: NSWindow?

    init(db: MeetingDB) { self.db = db }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = MainWindow(db: db)
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Recapit"
        w.setContentSize(NSSize(width: 960, height: 620))
        w.styleMask = [.titled, .resizable, .closable, .miniaturizable]
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct MainWindow: View {
    let db: MeetingDB
    @State private var meetings: [Meeting] = []
    @State private var selectedId: String?
    @State private var segments: [TranscriptSegment] = []
    @State private var actionItems: [ActionItem] = []

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(meetings: meetings, selectedId: $selectedId)
                .frame(minWidth: 220)
        } detail: {
            ReaderPane(
                meeting: meetings.first { $0.id == selectedId },
                segments: segments,
                actionItems: actionItems
            )
        }
        .onAppear { reload() }
        .onChange(of: selectedId) { _, newId in
            guard let id = newId else { return }
            segments = (try? db.segments(meetingId: id)) ?? []
            actionItems = []
        }
    }

    private func reload() {
        meetings = (try? db.recentMeetings()) ?? []
        if selectedId == nil { selectedId = meetings.first?.id }
    }
}
