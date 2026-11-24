import Foundation

/// The image formats the app recognises by their first bytes. Downloads are untrusted: a file
/// counts as an image only when its content says so, whatever its name ends in.
package enum ImageFormat: String, Sendable, CaseIterable {
    case jpeg, png, gif, webp, heif, avif, tiff, jpegXL, bmp, psd
    /// Raw formats with a signature of their own (most others are TIFF-based).
    case cr3, raf, orf, rw2, x3f, mrw, crw

    /// The group a format belongs to, for the filters in the settings.
    package var group: FormatGroup {
        switch self {
        case .gif: .gif
        case .psd: .photoshop
        case .cr3, .raf, .orf, .rw2, .x3f, .mrw, .crw: .raw
        default: .photo
        }
    }

    /// The extension a copy gets when the downloaded name has none LightCraft accepts.
    package var preferredExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .gif: "gif"
        case .webp: "webp"
        case .heif: "heic"
        case .avif: "avif"
        case .tiff: "tif"
        case .jpegXL: "jxl"
        case .bmp: "bmp"
        case .psd: "psd"
        case .cr3: "cr3"
        case .raf: "raf"
        case .orf: "orf"
        case .rw2: "rw2"
        case .x3f: "x3f"
        case .mrw: "mrw"
        case .crw: "crw"
        }
    }

    /// Extensions that may carry this format.
    package var extensions: Set<String> {
        switch self {
        case .jpeg: ["jpg", "jpeg", "jpe", "jfif"]
        case .heif: ["heic", "heif", "hif"]
        case .tiff: ["tif", "tiff"]
        case .psd: ["psd", "psb"]
        case .orf: ["orf"]
        case .rw2: ["rw2", "rwl", "raw"]
        default: [preferredExtension]
        }
    }

    /// Short name for the history and the log.
    package var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .gif: "GIF"
        case .webp: "WebP"
        case .heif: "HEIC"
        case .avif: "AVIF"
        case .tiff: "TIFF"
        case .jpegXL: "JPEG XL"
        case .bmp: "BMP"
        case .psd: "Photoshop"
        default: "RAW"
        }
    }

    /// How many leading bytes `detect` needs.
    package static let headerLength = 32

    /// Recognises a format from the first bytes of a file.
    package static func detect(_ header: Data) -> ImageFormat? {
        let b = [UInt8](header.prefix(headerLength))
        func at(_ offset: Int, _ bytes: [UInt8]) -> Bool {
            b.count >= offset + bytes.count && Array(b[offset..<offset + bytes.count]) == bytes
        }
        func ascii(_ offset: Int, _ text: String) -> Bool { at(offset, Array(text.utf8)) }

        if at(0, [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if ascii(0, "GIF87a") || ascii(0, "GIF89a") { return .gif }
        if ascii(0, "RIFF") && ascii(8, "WEBP") { return .webp }
        if ascii(0, "8BPS") { return .psd }
        if ascii(0, "FUJIFILMCCD-RAW") { return .raf }
        if ascii(0, "FOVb") { return .x3f }
        if at(0, [0x00]) && ascii(1, "MRM") { return .mrw }
        if ascii(0, "II") && at(2, [0x1A, 0x00, 0x00, 0x00]) && ascii(6, "HEAPCCDR") { return .crw }
        if ascii(0, "IIRO") || ascii(0, "IIRS") || ascii(0, "MMOR") { return .orf }
        if ascii(0, "IIU") && at(3, [0x00]) { return .rw2 }
        if at(0, [0x49, 0x49, 0x2A, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2A])
            || at(0, [0x49, 0x49, 0x2B, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2B]) { return .tiff }
        if at(0, [0xFF, 0x0A]) || at(0, [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A]) {
            return .jpegXL
        }
        if ascii(0, "BM") && b.count >= 14 { return .bmp }
        // ISO base media file (HEIF, AVIF, CR3): a `ftyp` box at offset 4, the brand after it.
        if ascii(4, "ftyp"), b.count >= 12 {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            switch brand {
            case "heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1", "mif2": return .heif
            case "avif", "avis": return .avif
            case "crx ": return .cr3
            default: return nil
            }
        }
        return nil
    }
}

/// The groups the filters in the settings switch on and off.
package enum FormatGroup: String, Sendable, CaseIterable {
    case photo, raw, gif, photoshop
}

/// The extensions LightCraft's import accepts (its `EXTENSIONS`).
package enum LightCraftExtensions {
    package static let raw: Set<String> = [
        "dng", "cr2", "cr3", "nef", "nrw", "arw", "sr2", "srf", "raf", "orf", "rw2", "rwl",
        "raw", "pef", "srw", "iiq", "crw", "mrw", "x3f", "kdc", "mos", "erf", "3fr", "fff", "mef"
    ]
    package static let rendered: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "webp", "psd", "psb", "jxl", "gif", "bmp",
        "heic", "heif", "avif"
    ]
    package static var all: Set<String> { raw.union(rendered) }
}

/// What a downloaded file is, judged by its name and its first bytes together.
package struct Classification: Equatable, Sendable {
    package var format: ImageFormat
    package var group: FormatGroup
    /// The extension the copy gets: the downloaded one when it fits the content and LightCraft
    /// accepts it, otherwise the one that matches the content (a WebP named `.jpg` becomes `.webp`).
    package var fileExtension: String

    /// `nil` when the file is not an image the app should take.
    package static func classify(fileName: String, header: Data) -> Classification? {
        guard let format = ImageFormat.detect(header) else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()

        // Most raw formats are TIFF containers: the extension tells them apart, the content
        // only confirms that it is TIFF-like.
        if LightCraftExtensions.raw.contains(ext) {
            switch format {
            case .tiff, .cr3, .raf, .orf, .rw2, .x3f, .mrw, .crw:
                return Classification(format: format, group: .raw, fileExtension: ext)
            default:
                // A raw name with JPEG or PNG inside: take it as what it really is.
                break
            }
        }
        if format.extensions.contains(ext), LightCraftExtensions.all.contains(ext) {
            return Classification(format: format, group: format.group, fileExtension: ext)
        }
        return Classification(format: format, group: format.group, fileExtension: format.preferredExtension)
    }
}
