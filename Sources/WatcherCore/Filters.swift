import Foundation

/// The filters from the settings.
package struct FilterSettings: Equatable, Sendable {
    package var groups: Set<FormatGroup> = [.photo, .raw]
    /// Smaller files are mostly icons and logos.
    package var minimumBytes: Int64 = 20 * 1024
    /// Only files macOS marks as downloaded (the quarantine attribute browsers set).
    package var onlyDownloaded = true

    package init() {}
}

/// Why a file in the watched folder is not taken. Shown in the log, not in the menu.
package enum SkipReason: Equatable, Sendable, CustomStringConvertible {
    case incomplete
    case notAFile
    case notAnImage
    case groupOff(FormatGroup)
    case tooSmall(Int64)
    case notDownloaded
    case alreadyCopied

    package var description: String {
        switch self {
        case .incomplete: "Download noch nicht fertig"
        case .notAFile: "keine normale Datei"
        case .notAnImage: "kein Bild"
        case let .groupOff(group): "Dateityp \(group.label) ist in den Filtern aus"
        case let .tooSmall(bytes): "nur \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), kleiner als die Mindestgröße"
        case .notDownloaded: "nicht von macOS als Download gekennzeichnet"
        case .alreadyCopied: "schon in einer früheren Sitzung kopiert"
        }
    }
}

extension FormatGroup {
    package var label: String {
        switch self {
        case .photo: "Fotos"
        case .raw: "RAW"
        case .gif: "GIF"
        case .photoshop: "Photoshop"
        }
    }
}

/// Names browsers give a file while it is still downloading.
package enum PartialDownload {
    package static let extensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp", "!ut"]

    package static func isPartial(_ fileName: String) -> Bool {
        extensions.contains((fileName as NSString).pathExtension.lowercased())
    }
}
