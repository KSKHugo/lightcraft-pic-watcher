import Foundation

/// Finds a file in the target folder with the same content as a new download.
///
/// Only files of the same size are hashed, and each hash is remembered as long as the file's
/// size and modification date stay the same. Only the top level counts: LightCraft's watched
/// folder is read without subfolders as well.
package final class DuplicateIndex {
    private struct Key: Hashable {
        var path: String
        var size: Int64
        var modified: Date
    }

    private var hashes: [Key: String] = [:]

    package init() {}

    package func existingFile(withSHA256 hash: String, size: Int64, in folder: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            guard let info = FileProbe.info(url), info.isRegularFile, info.size == size else { continue }
            let key = Key(path: url.path, size: info.size, modified: info.modified)
            let existing: String
            if let known = hashes[key] {
                existing = known
            } else {
                guard let computed = try? SafeCopier.sha256(of: url) else { continue }
                hashes[key] = computed
                existing = computed
            }
            if existing == hash { return url }
        }
        return nil
    }

    /// A file the app just wrote: no need to hash it again later.
    package func remember(_ url: URL, sha256: String) {
        guard let info = FileProbe.info(url) else { return }
        hashes[Key(path: url.path, size: info.size, modified: info.modified)] = sha256
    }
}
