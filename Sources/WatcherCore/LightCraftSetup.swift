import Foundation

/// What LightCraft's own settings say about its automatic import, read without changing anything.
///
/// LightCraft keeps the library it opened last in `~/Library/Application Support/LightCraft/ui.json`
/// (`settings.libraryPath`, else `~/Pictures/LightCraft Library`) and the automatic import in that
/// library's `prefs.json` (`import.autoFolder`, `autoCopy`, `autoAlbum`). These files are
/// LightCraft's internal format: when they cannot be read, the state is simply unknown.
package struct LightCraftAutoImport: Equatable, Sendable {
    package var folder: String?
    package var copiesIntoLibrary: Bool
    package var album: String?
}

package enum LightCraftSetupState: Equatable, Sendable {
    /// Watches the target folder and adds the files where they are.
    case ready(album: String?)
    /// Watches the target folder but copies every photo into its library as well.
    case readyButCopies(album: String?)
    case watchesOtherFolder(String)
    case off
    case unknown
}

package enum LightCraftSetup {
    package static let bundleIdentifier = "ai.storyteller.lightcraft"

    package static var supportFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LightCraft")
    }

    package static var defaultLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/LightCraft Library")
    }

    /// The library LightCraft opens, from its `ui.json`.
    package static func libraryFolder(uiJSON: Data?) -> URL {
        guard let uiJSON,
              let root = try? JSONSerialization.jsonObject(with: uiJSON) as? [String: Any],
              let settings = root["settings"] as? [String: Any],
              let path = settings["libraryPath"] as? String, !path.isEmpty
        else { return defaultLibrary }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// The automatic import from a library's `prefs.json`. A library without the file has never
    /// changed its preferences, so the automatic import is off.
    package static func autoImport(prefsJSON: Data?) -> LightCraftAutoImport? {
        guard let prefsJSON else { return LightCraftAutoImport(folder: nil, copiesIntoLibrary: false, album: nil) }
        guard let root = try? JSONSerialization.jsonObject(with: prefsJSON) as? [String: Any] else { return nil }
        let importSettings = root["import"] as? [String: Any] ?? [:]
        let folder = (importSettings["autoFolder"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let album = (importSettings["autoAlbum"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return LightCraftAutoImport(folder: folder, copiesIntoLibrary: importSettings["autoCopy"] as? Bool ?? false, album: album)
    }

    package static func state(of autoImport: LightCraftAutoImport?, target: URL) -> LightCraftSetupState {
        guard let autoImport else { return .unknown }
        guard let folder = autoImport.folder else { return .off }
        if samePath(folder, target.path) {
            return autoImport.copiesIntoLibrary ? .readyButCopies(album: autoImport.album) : .ready(album: autoImport.album)
        }
        return .watchesOtherFolder(folder)
    }

    /// Reads LightCraft's files from disk. Only reads, never writes.
    package static func currentState(target: URL) -> LightCraftSetupState {
        let ui = try? Data(contentsOf: supportFolder.appendingPathComponent("ui.json"))
        let library = libraryFolder(uiJSON: ui)
        guard FileManager.default.fileExists(atPath: library.path) else { return .unknown }
        let prefsURL = library.appendingPathComponent("prefs.json")
        let prefs: Data?
        if FileManager.default.fileExists(atPath: prefsURL.path) {
            guard let data = try? Data(contentsOf: prefsURL) else { return .unknown }
            prefs = data
        } else {
            prefs = nil
        }
        return state(of: autoImport(prefsJSON: prefs), target: target)
    }

    private static func samePath(_ a: String, _ b: String) -> Bool {
        func normal(_ p: String) -> String {
            URL(fileURLWithPath: (p as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
                .precomposedStringWithCanonicalMapping.lowercased()
        }
        return normal(a) == normal(b)
    }
}
