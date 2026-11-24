import AppKit
import Observation
import ServiceManagement
import UserNotifications
import WatcherCore
import os

enum TrayState: String {
    case idle, busy, done, paused, warn
}

/// LightCraft as far as this app can see it: installed, running, and its automatic import.
struct LightCraftStatus: Equatable {
    var appURL: URL?
    var version: String?
    var running = false
    var setup: LightCraftSetupState = .unknown

    var installed: Bool { appURL != nil }
}

@MainActor
@Observable
final class AppModel {
    var prefs: Preferences {
        didSet {
            guard prefs != oldValue else { return }
            prefs.save()
            if prefs.targetFolder != oldValue.targetFolder { refreshLightCraft() }
            if prefs.notify, !oldValue.notify { requestNotificationPermission() }
            applyToEngine()
            onChange?()
        }
    }
    private(set) var history: [HistoryItem] = .load()
    private(set) var problem: WatchProblem?
    private(set) var waiting = 0
    private(set) var lightCraft = LightCraftStatus()
    private(set) var downloadsAccess: Bool?
    private(set) var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status

    /// For the status item: called after anything that may change what it shows.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called once per verified copy (the icon shows a check mark for a moment).
    @ObservationIgnored var onCopied: (() -> Void)?

    @ObservationIgnored private var engine: WatchEngine?
    @ObservationIgnored private var cutoff: Date
    @ObservationIgnored private var lastActiveSaved = Date.distantPast
    @ObservationIgnored private var pendingNotes: [HistoryItem] = []
    @ObservationIgnored private var noteTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "de.pascalhugo.lightcraftpicwatcher", category: "app")

    /// Images that arrived while the app was not running are picked up, at most this far back.
    static let catchUpLimit: TimeInterval = 7 * 24 * 3600

    init() {
        prefs = .load()
        let lastActive = UserDefaults.standard.object(forKey: "lastActive") as? Date
        cutoff = Self.cutoff(lastActive: lastActive, now: Date())
        refreshLightCraft()
        observeLightCraft()
    }

    static func cutoff(lastActive: Date?, now: Date) -> Date {
        guard let lastActive else { return now }
        return max(lastActive.addingTimeInterval(-120), now.addingTimeInterval(-catchUpLimit))
    }

    var isCopying: Bool { history.contains { $0.status == .copying } }

    var trayState: TrayState {
        if problem != nil { return .warn }
        if prefs.paused { return .paused }
        if isCopying { return .busy }
        return .idle
    }

    var copiedToday: Int {
        history.filter { $0.status == .copied && Calendar.current.isDateInToday($0.date) }.count
    }

    // MARK: engine

    /// Starts watching once the first-run setup is done.
    func start() {
        guard prefs.onboardingDone else { return }
        if engine == nil {
            engine = WatchEngine { [weak self] event in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
            }
        }
        if prefs.notify { requestNotificationPermission() }
        applyToEngine()
    }

    private func applyToEngine() {
        guard let engine, prefs.onboardingDone else { return }
        engine.apply(WatchConfiguration(watchFolder: prefs.watchFolder, targetFolder: prefs.targetFolder, filters: prefs.filters,
                                        trashOriginal: prefs.trashOriginal, cutoff: cutoff, paused: prefs.paused))
    }

    /// Takes the images that are already in the watched folder as well (after asking).
    func includeExistingImages() {
        cutoff = .distantPast
        applyToEngine()
    }

    func finishOnboarding(includeExisting: Bool) {
        cutoff = includeExisting ? .distantPast : Date().addingTimeInterval(-5)
        prefs.onboardingDone = true
        start()
    }

    private func handle(_ event: WatchEvent) {
        switch event {
        case let .copying(id, name):
            history.insert(HistoryItem(id: id, name: name, date: Date(), status: .copying), at: 0)
        case let .copied(id, name, destination, format, size, trashed):
            let item = HistoryItem(id: id, name: name, date: Date(), status: .copied, file: destination, format: format,
                                   size: size, trashedOriginal: trashed)
            replace(item)
            queueNotification(item)
            onCopied?()
        case let .duplicate(id, name, existing, size, trashed):
            replace(HistoryItem(id: id, name: name, date: Date(), status: .duplicate, file: existing, size: size, trashedOriginal: trashed))
        case let .failed(id, name, reason):
            replace(HistoryItem(id: id, name: name, date: Date(), status: .failed(reason)))
        case let .postponed(id):
            history.removeAll { $0.id == id }
        case let .skipped(name, reason):
            log.info("skipped \(name, privacy: .private): \(reason.description, privacy: .public)")
        case let .problem(p):
            problem = p
        case let .waiting(count):
            waiting = count
        case let .scanned(date):
            // Remembered now and then, so images that arrive while the app is off are picked up later.
            if date.timeIntervalSince(lastActiveSaved) > 30 {
                lastActiveSaved = date
                UserDefaults.standard.set(date, forKey: "lastActive")
            }
        }
        onChange?()
    }

    private func replace(_ item: HistoryItem) {
        if let i = history.firstIndex(where: { $0.id == item.id }) { history[i] = item } else { history.insert(item, at: 0) }
        if history.count > 60 { history.removeLast(history.count - 60) }
        history.save()
    }

    func saveState() {
        UserDefaults.standard.set(Date(), forKey: "lastActive")
        history.save()
    }

    // MARK: actions

    func togglePause() { prefs.paused.toggle() }

    func openTargetFolder() {
        try? FileManager.default.createDirectory(at: prefs.targetFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(prefs.targetFolder)
    }

    func reveal(_ item: HistoryItem) {
        guard let file = item.file, FileManager.default.fileExists(atPath: file.path) else { return openTargetFolder() }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    func openLightCraft() {
        guard let url = lightCraft.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func copyTargetPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prefs.targetFolder.path, forType: .string)
    }

    func clearHistory() {
        history.removeAll { $0.status != .copying }
        history.save()
        onChange?()
    }

    /// Lists the Downloads folder once. The first time, macOS asks whether the app may.
    func requestDownloadsAccess() {
        let folder = prefs.watchFolder
        Task.detached {
            let ok = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
            await MainActor.run { self.downloadsAccess = ok }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: login item

    var launchAtLogin: Bool {
        get { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                log.error("login item: \(error.localizedDescription, privacy: .public)")
            }
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    // MARK: LightCraft

    func refreshLightCraft() {
        var status = LightCraftStatus()
        status.appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: LightCraftSetup.bundleIdentifier)
        if let url = status.appURL {
            status.version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }
        status.running = !NSRunningApplication.runningApplications(withBundleIdentifier: LightCraftSetup.bundleIdentifier).isEmpty
        let target = prefs.targetFolder
        status.setup = LightCraftSetup.currentState(target: target)
        if status != lightCraft {
            lightCraft = status
            onChange?()
        }
    }

    private func observeLightCraft() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == LightCraftSetup.bundleIdentifier else { return }
                MainActor.assumeIsolated { self?.refreshLightCraft() }
            }
        }
    }

    // MARK: notifications

    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// Several images in a row become one notification.
    private func queueNotification(_ item: HistoryItem) {
        guard prefs.notify, canNotify else { return }
        pendingNotes.append(item)
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.postNotification()
        }
    }

    private func postNotification() {
        let items = pendingNotes
        pendingNotes = []
        guard let first = items.first else { return }
        let content = UNMutableNotificationContent()
        content.title = items.count == 1 ? "Bild übernommen" : "\(items.count) Bilder übernommen"
        let folder = prefs.targetFolder.lastPathComponent
        let lc: String
        switch lightCraft.setup {
        case .ready, .readyButCopies: lc = lightCraft.running ? ", gleich in LightCraft" : ", beim nächsten Start in LightCraft"
        default: lc = ""
        }
        content.body = items.count == 1 ? "\(first.name) → \(folder)\(lc)" : "Aus dem Download-Ordner → \(folder)\(lc)"
        if let path = first.file?.path { content.userInfo = ["file": path] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
