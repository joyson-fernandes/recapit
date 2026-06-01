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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var settings: SettingsStore!
    private var calendarMonitor: CalendarMonitor!
    private var firstRun: FirstRunWizardController!
    private var mainWindow: MainWindowController?
    private var db: MeetingDB!

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

        firstRun = FirstRunWizardController(settings: settings, calendarMonitor: calendarMonitor)
        firstRun.showIfNeeded()
        calendarMonitor.start()
    }
}
