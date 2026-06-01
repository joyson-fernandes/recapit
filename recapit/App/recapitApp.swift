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
final class AppDelegate: NSObject, NSApplicationDelegate, AudioCaptureDelegate {
    private var menuBar: MenuBarController?
    private var settings: SettingsStore!
    private var calendarMonitor: CalendarMonitor!
    private var firstRun: FirstRunWizardController!
    private var mainWindow: MainWindowController?
    private var db: MeetingDB!
    private var capture: AudioCaptureEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        let recapitDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Recapit")
        try? FileManager.default.createDirectory(at: recapitDir, withIntermediateDirectories: true)
        let dbPath = recapitDir.appendingPathComponent("recapit.sqlite").path
        do {
            db = try MeetingDB(path: dbPath)
        } catch {
            NSLog("DB init failed: %@", String(describing: error))
            return
        }

        calendarMonitor = CalendarMonitor(settings: settings)
        menuBar = MenuBarController()
        mainWindow = MainWindowController(db: db)
        menuBar?.onOpenMainWindow = { [weak self] in self?.mainWindow?.show() }
        menuBar?.onCaptureNow = { [weak self] in self?.smokeTestStartMic() }
        menuBar?.onStop = { [weak self] in self?.capture?.stop(); self?.menuBar?.setRecordingIcon(false) }

        firstRun = FirstRunWizardController(settings: settings, calendarMonitor: calendarMonitor)
        firstRun.showIfNeeded()
        calendarMonitor.start()
    }

    private func smokeTestStartMic() {
        capture = AudioCaptureEngine()
        capture?.delegate = self
        do {
            try capture?.startMic()
            menuBar?.setRecordingIcon(true)
        } catch {
            NSLog("mic start failed: %@", String(describing: error))
        }
    }

    // MARK: - AudioCaptureDelegate
    nonisolated func audioCapture(_ engine: AudioCaptureEngine, chunk: AudioChunk) {
        let rms = sqrt(chunk.samples.reduce(0) { $0 + $1 * $1 } / Float(chunk.samples.count))
        NSLog("mic chunk @ %lld ms, %d samples, rms %.4f", chunk.startMs, chunk.samples.count, rms)
    }
    nonisolated func audioCaptureDidFail(_ engine: AudioCaptureEngine, error: Error) {
        NSLog("mic fail: %@", String(describing: error))
    }
}
