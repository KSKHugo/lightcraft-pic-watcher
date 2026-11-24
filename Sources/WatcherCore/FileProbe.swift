import Darwin
import Foundation

/// Reads what the app needs to know about a file without following symbolic links.
package enum FileProbe {
    package struct Info: Equatable, Sendable {
        package var isRegularFile: Bool
        package var size: Int64
        package var modified: Date
    }

    /// `lstat`: a symbolic link is reported as what it is, never as its target.
    package static func info(_ url: URL) -> Info? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)
            + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000)
        return Info(isRegularFile: (st.st_mode & S_IFMT) == S_IFREG, size: Int64(st.st_size), modified: modified)
    }

    /// Whether macOS marked the file as downloaded (`com.apple.quarantine`).
    package static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// The first bytes of a regular file, opened with `O_NOFOLLOW`.
    package static func header(_ url: URL, length: Int = ImageFormat.headerLength) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        let count = read(fd, &buffer, length)
        guard count > 0 else { return nil }
        return Data(buffer.prefix(count))
    }
}
