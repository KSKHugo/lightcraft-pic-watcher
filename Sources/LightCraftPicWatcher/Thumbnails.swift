import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Small previews for the list in the menu. Quick Look renders them in a separate, sandboxed
/// process, so a broken or hostile download never gets decoded inside this app.
@MainActor
@Observable
final class ThumbnailStore {
    static let shared = ThumbnailStore()
    private var images: [URL: NSImage] = [:]
    private var requested: Set<URL> = []

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let image = images[url] { return image }
        if !requested.contains(url) {
            requested.insert(url)
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 80, height: 64),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
                guard let image = rep?.nsImage else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.images[url] = image } }
            }
        }
        return nil
    }
}

struct Thumbnail: View {
    var url: URL?
    var store = ThumbnailStore.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image = store.image(for: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
