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

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        calendarMonitor = CalendarMonitor(settings: settings)
        menuBar = MenuBarController()
        firstRun = FirstRunWizardController(settings: settings, calendarMonitor: calendarMonitor)
        firstRun.showIfNeeded()
        calendarMonitor.start()
    }
}
