import Foundation

/// Waits until a file has stopped growing: its size and modification date must stay the same
/// for `quietPeriod` before the file counts as complete. Browsers rename a finished download
/// in one step, but other apps (and a download via AirDrop or a sync tool) write in place.
package struct StabilityTracker: Sendable {
    private struct Seen: Sendable {
        var size: Int64
        var modified: Date
        var since: Date
    }

    package var quietPeriod: TimeInterval
    private var seen: [String: Seen] = [:]

    package init(quietPeriod: TimeInterval = 2) {
        self.quietPeriod = quietPeriod
    }

    /// Records the current state of a file and says whether it is complete now.
    package mutating func isStable(path: String, size: Int64, modified: Date, now: Date) -> Bool {
        if let previous = seen[path], previous.size == size, previous.modified == modified {
            return now.timeIntervalSince(previous.since) >= quietPeriod
        }
        seen[path] = Seen(size: size, modified: modified, since: now)
        return false
    }

    package mutating func forget(_ path: String) {
        seen[path] = nil
    }

    /// Drops files that are gone.
    package mutating func keepOnly(_ paths: Set<String>) {
        seen = seen.filter { paths.contains($0.key) }
    }

    package var isWaiting: Bool { !seen.isEmpty }
}
