import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var clickOutsideMonitor: Any?
    let viewModel = PopoverViewModel()

    var onOpenMainWindow: () -> Void = {}
    var onSettings: () -> Void = {}
    var onCaptureNow: () -> Void = {}
    var onStop: () -> Void = {}
    var onJoin: (UpcomingMeeting) -> Void = { _ in }
    var onQuit: () -> Void = { NSApp.terminate(nil) }

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Recapit")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(toggle)
            button.target = self
        }
    }

    private func setupPopover() {
        let view = PopoverView(
            vm: viewModel,
            onCaptureNow: { [weak self] in self?.close(); self?.onCaptureNow() },
            onOpenMainWindow: { [weak self] in self?.close(); self?.onOpenMainWindow() },
            onJoin: { [weak self] m in self?.close(); self?.onJoin(m) },
            onStop: { [weak self] in self?.onStop() },
            onSettings: { [weak self] in self?.close(); self?.onSettings() },
            onQuit: { [weak self] in self?.close(); self?.onQuit() }
        )
        let hosting = NSHostingController(rootView: view)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = .preferredContentSize
        }
        popover.contentViewController = hosting
        popover.behavior = .applicationDefined
        popover.animates = false
    }

    func setRecordingIcon(_ recording: Bool) {
        let name = recording ? "record.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Recapit")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func toggle() {
        if popover.isShown { close() } else { open() }
    }

    private func open() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func close() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
        popover.performClose(nil)
    }
}
