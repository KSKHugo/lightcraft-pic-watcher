import AppKit
import SwiftUI
import UserNotifications

/// A menu bar app: no Dock icon (`LSUIElement`), one status item, two windows on demand.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = AppModel()
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` starts a bare executable; it still belongs in the menu bar only.
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        let controller = StatusItemController(model: model)
        controller.openSettings = { [weak self] in self?.showSettings() }
        statusItem = controller
        if model.prefs.onboardingDone {
            model.start()
            // For a test run: `-showSettingsAtLaunch YES` (with `-settingsTab lightcraft` etc.).
            if UserDefaults.standard.bool(forKey: "showSettingsAtLaunch") { showSettings() }
        } else {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveState()
    }

    /// Opening the app again (from the Finder or Spotlight) shows its panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.prefs.onboardingDone { statusItem?.showPopover() } else { showOnboarding() }
        return false
    }

    private func window(title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = window(title: "LightCraft Pic Watcher – Einstellungen",
                                    content: SettingsView(model: model, showOnboarding: { [weak self] in self?.showOnboarding() }))
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = window(title: "Willkommen beim LightCraft Pic Watcher", content: OnboardingView(model: model) { [weak self] in
                self?.onboardingWindow?.close()
                self?.statusItem?.showPopover()
            })
        }
        settingsWindow?.close()
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    // A click on a notification shows the copy in the Finder.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let path = response.notification.request.content.userInfo["file"] as? String
        DispatchQueue.main.async {
            if let path, FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
