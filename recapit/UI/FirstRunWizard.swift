import SwiftUI
import AVFoundation
import EventKit
import ScreenCaptureKit

@MainActor
final class FirstRunWizardController {
    private let settings: SettingsStore
    private let calendarMonitor: CalendarMonitor
    private var window: NSWindow?

    init(settings: SettingsStore, calendarMonitor: CalendarMonitor) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
    }

    func showIfNeeded() {
        guard !settings.firstRunCompleted else { return }
        let view = FirstRunWizard(settings: settings,
                                  calendarMonitor: calendarMonitor,
                                  onClose: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Welcome to Recapit"
        w.setContentSize(NSSize(width: 520, height: 420))
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func close() {
        settings.firstRunCompleted = true
        window?.close()
        window = nil
    }
}

@MainActor
final class SettingsObserver: ObservableObject {
    @Published var processingMode: ProcessingMode {
        didSet { settings.processingMode = processingMode }
    }
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        self.processingMode = settings.processingMode
    }
}

struct FirstRunWizard: View {
    @ObservedObject var settingsObserver: SettingsObserver
    let settings: SettingsStore
    let calendarMonitor: CalendarMonitor
    let onClose: () -> Void

    init(settings: SettingsStore, calendarMonitor: CalendarMonitor, onClose: @escaping () -> Void) {
        self.settings = settings
        self.calendarMonitor = calendarMonitor
        self.onClose = onClose
        self.settingsObserver = SettingsObserver(settings: settings)
    }

    @State private var step = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 12)

            Group {
                switch step {
                case 0: permissionsStep
                case 1: modeStep
                default: calendarStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step < 2 { Button("Next") { step += 1 }.keyboardShortcut(.defaultAction) }
                else { Button("Get started") { onClose() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            }
            .padding(16)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions").font(.title2).bold()
            Text("Recapit needs three permissions. We'll request them one at a time.")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(name: "Calendar", description: "Detect upcoming meetings.") {
                    _ = await calendarMonitor.requestAccess()
                }
                permissionRow(name: "Microphone", description: "Record your voice.") {
                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                }
                permissionRow(name: "Screen Recording", description: "Capture system audio (other participants).") {
                    _ = try? await SCShareableContent.current
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private func permissionRow(name: String, description: String, request: @escaping () async -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name).font(.callout).fontWeight(.medium)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Grant") {
                Task { await request() }
            }.controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing mode").font(.title2).bold()
            Text("Where should transcription and summaries run?").foregroundColor(.secondary)
            ForEach(ProcessingMode.allCases, id: \.self) { mode in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: settingsObserver.processingMode == mode ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName).font(.callout).fontWeight(.medium)
                        Text(modeBlurb(mode)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.secondary.opacity(settingsObserver.processingMode == mode ? 0.12 : 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { settingsObserver.processingMode = mode }
            }
            Spacer()
        }
        .padding(16)
    }

    private func modeBlurb(_ m: ProcessingMode) -> String {
        switch m {
        case .local: return "All processing on your Mac. No data leaves the machine. Slowest first run (model download)."
        case .cloud: return "Send audio to cloud providers (Deepgram, OpenAI, Anthropic). Fastest, highest quality."
        case .hybrid: return "Local transcription, cloud summarisation. Cheapest cloud setup."
        }
    }

    private var calendarStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendars to watch").font(.title2).bold()
            Text("Recapit polls these calendars every 30 seconds.").foregroundColor(.secondary)
            Text("You can change this later in Settings.").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(16)
    }
}
