import Darwin
import Foundation
import os

package struct WatchConfiguration: Equatable, Sendable {
    package var watchFolder: URL
    package var targetFolder: URL
    package var filters: FilterSettings
    /// Move the original to the Trash once its copy is verified (never delete it outright).
    package var trashOriginal: Bool
    /// Files that arrived in the watched folder before this moment are left alone.
    package var cutoff: Date
    package var paused: Bool

    package init(watchFolder: URL, targetFolder: URL, filters: FilterSettings = FilterSettings(),
                 trashOriginal: Bool = false, cutoff: Date, paused: Bool = false) {
        self.watchFolder = watchFolder
        self.targetFolder = targetFolder
        self.filters = filters
        self.trashOriginal = trashOriginal
        self.cutoff = cutoff
        self.paused = paused
    }
}

package enum WatchProblem: Equatable, Sendable {
    case watchFolderUnreadable(String)
    case targetUnreachable
    case targetInsideWatchFolder
}

package enum WatchEvent: Sendable {
    case copying(id: UUID, name: String)
    case copied(id: UUID, name: String, destination: URL, format: String, size: Int64, trashedOriginal: Bool)
    case duplicate(id: UUID, name: String, existing: URL, size: Int64, trashedOriginal: Bool)
    case failed(id: UUID, name: String, reason: String)
    /// The file changed while it was being copied; it is tried again once it has settled.
    case postponed(id: UUID)
    case skipped(name: String, reason: SkipReason)
    /// `nil` when everything works (again).
    case problem(WatchProblem?)
    /// Files that wait: still being written, or held back while paused.
    case waiting(count: Int)
    /// A complete pass over the watched folder.
    case scanned(Date)
}

/// Watches one folder (not its subfolders) and copies every new, complete image into the
/// target folder. Runs on its own serial queue; events arrive on that queue.
package final class WatchEngine: @unchecked Sendable {
    private struct Handled: Hashable {
        var path: String
        var size: Int64
        var modified: Date
    }

    private let queue = DispatchQueue(label: "de.pascalhugo.lightcraftpicwatcher.engine", qos: .utility)
    private let now: @Sendable () -> Date
    private let onEvent: @Sendable (WatchEvent) -> Void
    private let log = Logger(subsystem: "de.pascalhugo.lightcraftpicwatcher", category: "engine")

    private var configuration: WatchConfiguration?
    private var folderSource: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var fastTimer: DispatchSourceTimer?
    private var slowTimer: DispatchSourceTimer?
    private var stability = StabilityTracker()
    private var handled: Set<Handled> = []
    private let duplicates = DuplicateIndex()
    private var problem: WatchProblem?
    private var lastWaiting = -1
    /// When this engine started: files added earlier come from the catch-up.
    private var sessionStart = Date.distantFuture

    package init(now: @escaping @Sendable () -> Date = { Date() }, onEvent: @escaping @Sendable (WatchEvent) -> Void) {
        self.now = now
        self.onEvent = onEvent
    }

    deinit {
        folderSource?.cancel()
        fastTimer?.cancel()
        slowTimer?.cancel()
    }

    /// Starts watching, or applies changed settings.
    package func apply(_ configuration: WatchConfiguration) {
        queue.async { self.applyNow(configuration) }
    }

    package func stop() {
        queue.async {
            self.configuration = nil
            self.folderSource?.cancel(); self.folderSource = nil; self.watchedPath = nil
            self.fastTimer?.cancel(); self.fastTimer = nil
            self.slowTimer?.cancel(); self.slowTimer = nil
        }
    }

    package func scanSoon() {
        queue.async { self.scan() }
    }

    /// For tests: applies settings and runs one pass, synchronously.
    package func scanForTesting(_ configuration: WatchConfiguration? = nil) {
        queue.sync {
            if let configuration { self.configuration = configuration }
            if self.sessionStart == .distantFuture { self.sessionStart = self.now() }
            self.scan()
        }
    }

    private func applyNow(_ new: WatchConfiguration) {
        let old = configuration
        configuration = new
        if old == nil, sessionStart == .distantFuture { sessionStart = now() }
        if old?.watchFolder != new.watchFolder || folderSource == nil {
            watch(new.watchFolder)
        }
        if slowTimer == nil {
            // A safety net: a pass every 30 seconds even if no change notice came in.
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(5))
            timer.setEventHandler { [weak self] in self?.scan() }
            timer.resume()
            slowTimer = timer
        }
        scan()
    }

    /// A change notice for the folder itself: files added, removed or renamed.
    private func watch(_ folder: URL) {
        folderSource?.cancel()
        folderSource = nil
        let fd = open(folder.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderSource = source
        watchedPath = folder.path
    }

    /// While a file is still being written, a pass every second.
    private func setFastTimer(_ on: Bool) {
        if on, fastTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.scan() }
            timer.resume()
            fastTimer = timer
        } else if !on, let timer = fastTimer {
            timer.cancel()
            fastTimer = nil
        }
    }

    private func report(_ new: WatchProblem?) {
        guard new != problem else { return }
        problem = new
        onEvent(.problem(new))
    }

    private func scan() {
        guard let config = configuration else { return }
        if folderSource == nil || watchedPath != config.watchFolder.path { watch(config.watchFolder) }

        let watch = config.watchFolder.standardizedFileURL.resolvingSymlinksInPath().path
        let target = config.targetFolder.standardizedFileURL.resolvingSymlinksInPath().path
        if target == watch || target.hasPrefix(watch + "/") {
            report(.targetInsideWatchFolder)
            setFastTimer(false)
            return
        }

        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: config.watchFolder, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
        } catch {
            report(.watchFolderUnreadable((error as NSError).localizedDescription))
            setFastTimer(false)
            return
        }
        guard targetReachable(config.targetFolder) else {
            report(.targetUnreachable)
            setFastTimer(true)
            return
        }
        report(nil)

        var present: Set<String> = []
        var waiting = 0
        let moment = now()
        for url in entries {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            let added = values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
            guard added >= config.cutoff else { continue }
            guard let info = FileProbe.info(url) else { continue }
            if PartialDownload.isPartial(name) {
                // A download that stopped long ago (abandoned) is not waited for.
                if moment.timeIntervalSince(info.modified) < 600 { waiting += 1 }
                continue
            }
            let key = Handled(path: url.path, size: info.size, modified: info.modified)
            if handled.contains(key) { continue }
            guard info.isRegularFile else {
                handled.insert(key)
                // Folders (an unpacked archive) are not looked into; links are never followed.
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    onEvent(.skipped(name: name, reason: .notAFile))
                }
                continue
            }
            present.insert(url.path)
            if config.paused { waiting += 1; continue }
            guard stability.isStable(path: url.path, size: info.size, modified: info.modified, now: moment) else {
                waiting += 1
                continue
            }
            stability.forget(url.path)
            if process(url, info: info, added: added, config: config) {
                handled.insert(key)
            } else {
                waiting += 1
            }
        }
        stability.keepOnly(present)
        setFastTimer(waiting > 0 && !config.paused)
        if waiting != lastWaiting {
            lastWaiting = waiting
            onEvent(.waiting(count: waiting))
        }
        onEvent(.scanned(moment))
    }

    /// The target folder exists, or can be made inside a folder that exists (an external drive
    /// that is not connected does not count).
    private func targetReachable(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) { return isDirectory.boolValue }
        let parent = folder.deletingLastPathComponent()
        if parent.path.hasPrefix("/Volumes/"), parent.pathComponents.count <= 3 { return false }
        return FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Returns `false` when the file should be looked at again on a later pass.
    private func process(_ url: URL, info: FileProbe.Info, added: Date, config: WatchConfiguration) -> Bool {
        let name = url.lastPathComponent
        let filters = config.filters
        if filters.onlyDownloaded, !FileProbe.isQuarantined(url) {
            onEvent(.skipped(name: name, reason: .notDownloaded)); return true
        }
        if info.size < filters.minimumBytes {
            onEvent(.skipped(name: name, reason: .tooSmall(info.size))); return true
        }
        guard let header = FileProbe.header(url), let kind = Classification.classify(fileName: name, header: header) else {
            onEvent(.skipped(name: name, reason: .notAnImage)); return true
        }
        guard filters.groups.contains(kind.group) else {
            onEvent(.skipped(name: name, reason: .groupOff(kind.group))); return true
        }

        let id = UUID()
        do {
            let hash = try SafeCopier.sha256(of: url)
            if let existing = duplicates.existingFile(withSHA256: hash, size: info.size, in: config.targetFolder) {
                // Picked up again after a restart (the catch-up overlaps a little): nothing new.
                if added < sessionStart {
                    onEvent(.skipped(name: name, reason: .alreadyCopied)); return true
                }
                let trashed = config.trashOriginal && trash(url)
                onEvent(.duplicate(id: id, name: name, existing: existing, size: info.size, trashedOriginal: trashed))
                return true
            }
            onEvent(.copying(id: id, name: name))
            let fileName = SafeCopier.sanitizedFileName(name, fileExtension: kind.fileExtension)
            let result = try SafeCopier.copy(url, into: config.targetFolder, fileName: fileName)
            duplicates.remember(result.destination, sha256: result.sha256)
            let trashed = config.trashOriginal && trash(url)
            log.info("copied \(name, privacy: .private) to \(result.destination.path, privacy: .private)")
            onEvent(.copied(id: id, name: name, destination: result.destination, format: kind.format.displayName,
                            size: result.size, trashedOriginal: trashed))
            return true
        } catch CopyError.sourceChanged {
            // Still being written after all: wait for it to settle again.
            onEvent(.postponed(id: id))
            return false
        } catch {
            onEvent(.failed(id: id, name: name, reason: String(describing: error)))
            return true
        }
    }

    private func trash(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            log.error("could not move the original to the Trash: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
