import Foundation
import WatcherCore

/// The settings, kept in UserDefaults. For a test run they can be given on the command line,
/// e.g. `-watchFolder /tmp/in -targetFolder /tmp/out` (UserDefaults' argument domain).
struct Preferences: Equatable {
    var watchFolder: URL
    var targetFolder: URL
    var trashOriginal = false
    var notify = true
    var animateIcon = true
    var photos = true
    var raw = true
    var gif = false
    var photoshop = false
    var minimumKB = 20
    var onlyDownloaded = true
    var paused = false
    var onboardingDone = false

    static let defaultWatchFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    static let defaultTargetFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Aus Downloads")

    var filters: FilterSettings {
        var f = FilterSettings()
        f.groups = Set([photos ? FormatGroup.photo : nil, raw ? .raw : nil, gif ? .gif : nil, photoshop ? .photoshop : nil].compactMap { $0 })
        f.minimumBytes = Int64(max(0, minimumKB)) * 1024
        f.onlyDownloaded = onlyDownloaded
        return f
    }

    static func load(_ d: UserDefaults = .standard) -> Preferences {
        func url(_ key: String, _ fallback: URL) -> URL {
            guard let path = d.string(forKey: key), path.hasPrefix("/") || path.hasPrefix("~") else { return fallback }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
        var p = Preferences(watchFolder: url("watchFolder", defaultWatchFolder), targetFolder: url("targetFolder", defaultTargetFolder))
        p.trashOriginal = bool("trashOriginal", p.trashOriginal)
        p.notify = bool("notify", p.notify)
        p.animateIcon = bool("animateIcon", p.animateIcon)
        p.photos = bool("photos", p.photos)
        p.raw = bool("raw", p.raw)
        p.gif = bool("gif", p.gif)
        p.photoshop = bool("photoshop", p.photoshop)
        if d.object(forKey: "minimumKB") != nil { p.minimumKB = d.integer(forKey: "minimumKB") }
        p.onlyDownloaded = bool("onlyDownloaded", p.onlyDownloaded)
        p.paused = bool("paused", p.paused)
        p.onboardingDone = bool("onboardingDone", p.onboardingDone)
        return p
    }

    func save(_ d: UserDefaults = .standard) {
        d.set(watchFolder.path, forKey: "watchFolder")
        d.set(targetFolder.path, forKey: "targetFolder")
        d.set(trashOriginal, forKey: "trashOriginal")
        d.set(notify, forKey: "notify")
        d.set(animateIcon, forKey: "animateIcon")
        d.set(photos, forKey: "photos")
        d.set(raw, forKey: "raw")
        d.set(gif, forKey: "gif")
        d.set(photoshop, forKey: "photoshop")
        d.set(minimumKB, forKey: "minimumKB")
        d.set(onlyDownloaded, forKey: "onlyDownloaded")
        d.set(paused, forKey: "paused")
        d.set(onboardingDone, forKey: "onboardingDone")
    }
}

/// A path for display, with the home folder as `~`.
func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = url.path
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}
