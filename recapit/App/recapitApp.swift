import AppKit

@main
struct recapitApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, CalendarMonitorDelegate, RecordingCoordinatorDelegate {
    private var menuBar: MenuBarController?
    private var settings: SettingsStore!
    private var calendarMonitor: CalendarMonitor!
    private var firstRun: FirstRunWizardController!
    private var mainWindow: MainWindowController?
    private var db: MeetingDB!
    private var markdown: MarkdownStore!
    private var coordinator: RecordingCoordinator!
    private var countdown: CountdownNotification!
    private var asr: ASRProvider!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        let recapitDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Recapit")
        try? FileManager.default.createDirectory(at: recapitDir, withIntermediateDirectories: true)
        do {
            db = try MeetingDB(path: recapitDir.appendingPathComponent("recapit.sqlite").path)
        } catch {
            NSLog("DB init failed: %@", String(describing: error))
            return
        }
        markdown = MarkdownStore(root: recapitDir)
        calendarMonitor = CalendarMonitor(settings: settings)
        calendarMonitor.delegate = self

        asr = WhisperKitProvider(modelName: settings.asrModel)

        coordinator = RecordingCoordinator(
            db: db, markdown: markdown, settings: settings, asr: asr,
            summaryEngineFactory: { [weak self] in
                guard let self else { fatalError() }
                let llm: LLMProvider = OllamaProvider()
                return SummaryEngine(llm: llm, db: self.db, markdown: self.markdown,
                                     summaryModel: self.settings.llmModel,
                                     embeddingModel: "nomic-embed-text")
            }
        )
        coordinator.delegate = self

        menuBar = MenuBarController()
        mainWindow = MainWindowController(db: db)
        menuBar?.onOpenMainWindow = { [weak self] in self?.mainWindow?.show() }
        menuBar?.onCaptureNow = { [weak self] in self?.coordinator?.startAdhoc() }
        menuBar?.onStop = { [weak self] in Task { await self?.coordinator?.stop() } }
        menuBar?.onJoin = { [weak self] m in
            self?.coordinator?.startCountdown(title: m.title,
                                              calendarEventId: m.id,
                                              meetingURL: m.meetingURL)
        }

        countdown = CountdownNotification()
        countdown.configure()
        countdown.onJoin = { [weak self] _ in
            guard let upcoming = self?.menuBar?.viewModel.upcoming.first else { return }
            self?.coordinator?.startCountdown(title: upcoming.title,
                                              calendarEventId: upcoming.id,
                                              meetingURL: upcoming.meetingURL)
        }

        firstRun = FirstRunWizardController(settings: settings, calendarMonitor: calendarMonitor)
        firstRun.showIfNeeded()
        calendarMonitor.start()
    }

    // MARK: - CalendarMonitorDelegate
    nonisolated func calendarMonitor(_ monitor: CalendarMonitor, didUpdateUpcoming items: [UpcomingMeeting]) {
        Task { @MainActor in self.menuBar?.viewModel.updateUpcoming(items) }
    }
    nonisolated func calendarMonitor(_ monitor: CalendarMonitor, meetingStartingSoon m: UpcomingMeeting) {
        Task { @MainActor in self.countdown.post(meeting: m) }
    }
    nonisolated func calendarMonitor(_ monitor: CalendarMonitor, meetingNow m: UpcomingMeeting) {
        Task { @MainActor in
            self.coordinator.startCountdown(title: m.title, calendarEventId: m.id, meetingURL: m.meetingURL)
        }
    }

    // MARK: - RecordingCoordinatorDelegate
    func coordinator(_ c: RecordingCoordinator, didChangeState state: RecordingCoordinator.State) {
        menuBar?.setRecordingIcon(state == .recording)
        menuBar?.viewModel.isProcessing = (state == .processing)
        menuBar?.viewModel.currentRecording = c.currentMeeting
    }
    func coordinator(_ c: RecordingCoordinator, recordingMeeting m: Meeting) {}
    func coordinator(_ c: RecordingCoordinator, finishedMeeting m: Meeting) {
        menuBar?.viewModel.updateRecent((try? db.recentMeetings()) ?? [])
    }
}
