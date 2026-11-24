import CryptoKit
import Darwin
import Foundation

package enum CopyError: Error, Equatable, CustomStringConvertible {
    case sourceUnreadable
    case sourceChanged
    case verificationFailed
    case destinationUnwritable(String)

    package var description: String {
        switch self {
        case .sourceUnreadable: "Die Datei ließ sich nicht lesen."
        case .sourceChanged: "Die Datei hat sich beim Kopieren verändert."
        case .verificationFailed: "Die Kopie stimmt nicht mit dem Original überein und wurde verworfen."
        case let .destinationUnwritable(reason): "Der Zielordner ist nicht beschreibbar: \(reason)"
        }
    }
}

package struct CopyResult: Equatable, Sendable {
    package var destination: URL
    package var sha256: String
    package var size: Int64
}

/// Copies a file into a folder without ever overwriting anything there.
///
/// The copy is written under a hidden name first (LightCraft and the Finder skip hidden files),
/// compared with the original by SHA-256, and only then renamed to its final name, atomically
/// and refusing to replace an existing file. Extended attributes travel with it, the quarantine
/// mark included, so macOS still treats the copy as downloaded.
package enum SafeCopier {
    package static func copy(_ source: URL, into folder: URL, fileName: String) throws -> CopyResult {
        guard let before = FileProbe.info(source), before.isRegularFile else { throw CopyError.sourceUnreadable }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw CopyError.destinationUnwritable(error.localizedDescription)
        }
        let temporary = folder.appendingPathComponent(".picwatcher-\(UUID().uuidString).tmp")
        // copyfile without following a link at the source; COPYFILE_ALL keeps the attributes.
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC | COPYFILE_EXCL)
        guard copyfile(source.path, temporary.path, nil, flags) == 0 else {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporary)
            throw errno == ENOENT || errno == EACCES ? CopyError.sourceUnreadable : CopyError.destinationUnwritable(reason)
        }
        do {
            let original = try sha256(of: source)
            let copied = try sha256(of: temporary)
            guard let after = FileProbe.info(source), after.size == before.size, after.modified == before.modified else {
                throw CopyError.sourceChanged
            }
            guard original == copied else { throw CopyError.verificationFailed }
            let destination = try moveIntoPlace(temporary, folder: folder, fileName: fileName)
            return CopyResult(destination: destination, sha256: copied, size: after.size)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Renames the verified copy to `fileName`, or `name-1.ext`, `name-2.ext` … when taken.
    private static func moveIntoPlace(_ temporary: URL, folder: URL, fileName: String) throws -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        for n in 0..<10_000 {
            let name = n == 0 ? fileName : (ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)")
            let target = folder.appendingPathComponent(name)
            if renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
            guard errno == EEXIST else {
                throw CopyError.destinationUnwritable(String(cString: strerror(errno)))
            }
        }
        throw CopyError.destinationUnwritable("kein freier Dateiname")
    }

    /// SHA-256 of a file, read in 1 MB pieces, never through a symbolic link.
    package static func sha256(of url: URL) throws -> String {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CopyError.sourceUnreadable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A file name that is safe to create: no path separators, no leading dot, not empty.
    package static func sanitizedFileName(_ name: String, fileExtension: String) -> String {
        var base = (name as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { base = "Bild" }
        while base.utf8.count > 200 { base.removeLast() }
        return "\(base).\(fileExtension)"
    }
}
