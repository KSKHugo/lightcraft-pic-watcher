import AppKit
import SwiftUI

/// The symbol in the menu bar and the panel that opens from it.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var timer: Timer?
    private var frame = 0
    /// The arrows turn at least this long, so even a quick copy is visible.
    private var busyUntil = Date.distantPast
    private var doneUntil = Date.distantPast
    private var shown: (TrayState, Int)?

    var openSettings: () -> Void = {}

    init(model: AppModel) {
        self.model = model
        super.init()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageOnly
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            model: model,
            openSettings: { [weak self] in self?.popover.performClose(nil); self?.openSettings() },
            close: { [weak self] in self?.popover.performClose(nil) }))
        model.onChange = { [weak self] in self?.refresh() }
        model.onCopied = { [weak self] in self?.copied() }
        refresh()
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            model.refreshLightCraft()
            // A transient popover closes as soon as its app is not active.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showPopover() {
        if !popover.isShown { toggle() }
    }

    private func copied() {
        busyUntil = max(busyUntil, Date().addingTimeInterval(0.4))
        doneUntil = busyUntil.addingTimeInterval(1.6)
        refresh()
    }

    private var displayed: TrayState {
        let now = Date()
        let state = model.trayState
        if state == .warn || state == .paused { return state }
        if state == .busy {
            if busyUntil < now.addingTimeInterval(1.0) { busyUntil = now.addingTimeInterval(1.0) }
            return .busy
        }
        if now < busyUntil { return .busy }
        if now < doneUntil { return .done }
        return .idle
    }

    func refresh() {
        let state = displayed
        let animate = model.prefs.animateIcon && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let needsTimer = (state == .busy && animate) || Date() < doneUntil || Date() < busyUntil
        if needsTimer, timer == nil {
            let t = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !needsTimer {
            timer?.invalidate()
            timer = nil
        }
        let frameShown = state == .busy && animate ? frame : 0
        if shown == nil || shown! != (state, frameShown) {
            shown = (state, frameShown)
            item.button?.image = TrayIcon.image(state, frame: frameShown)
        }
        let labels: [TrayState: String] = [.idle: "Bereit", .busy: "Kopiert ein Bild", .done: "Bild übernommen",
                                           .paused: "Pausiert", .warn: "Problem"]
        item.button?.toolTip = "LightCraft Pic Watcher – \(labels[state] ?? "")"
        item.button?.setAccessibilityLabel(item.button?.toolTip)
    }

    private func tick() {
        frame = (frame + 1) % TrayIcon.frameCount
        refresh()
    }

    func popoverDidClose(_ notification: Notification) {}
}
