import Darwin
import Foundation
import XCTest
@testable import WatcherCore

private let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10] + Array("JFIF".utf8)
private let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
private let webpHeader: [UInt8] = Array("RIFF".utf8) + [0x24, 0, 0, 0] + Array("WEBPVP8 ".utf8)
private let tiffHeader: [UInt8] = [0x49, 0x49, 0x2A, 0x00, 0x08, 0, 0, 0]
private let heicHeader: [UInt8] = [0, 0, 0, 0x18] + Array("ftypheic".utf8) + [0, 0, 0, 0]
private let cr3Header: [UInt8] = [0, 0, 0, 0x18] + Array("ftypcrx ".utf8) + [0, 0, 0, 1]

final class ClassificationTests: XCTestCase {
    func testDetectsFormatsByContent() {
        XCTAssertEqual(ImageFormat.detect(Data(jpegHeader)), .jpeg)
        XCTAssertEqual(ImageFormat.detect(Data(pngHeader)), .png)
        XCTAssertEqual(ImageFormat.detect(Data(webpHeader)), .webp)
        XCTAssertEqual(ImageFormat.detect(Data(tiffHeader)), .tiff)
        XCTAssertEqual(ImageFormat.detect(Data(heicHeader)), .heif)
        XCTAssertEqual(ImageFormat.detect(Data(cr3Header)), .cr3)
        XCTAssertEqual(ImageFormat.detect(Data("FUJIFILMCCD-RAW 0201".utf8)), .raf)
        XCTAssertNil(ImageFormat.detect(Data("%PDF-1.7\n".utf8)))
        XCTAssertNil(ImageFormat.detect(Data([0x50, 0x4B, 0x03, 0x04])), "a ZIP is no image")
        XCTAssertNil(ImageFormat.detect(Data()))
    }

    func testKeepsAFittingExtension() {
        let c = Classification.classify(fileName: "Urlaub.JPG", header: Data(jpegHeader))
        XCTAssertEqual(c, Classification(format: .jpeg, group: .photo, fileExtension: "jpg"))
    }

    func testCorrectsAnExtensionThatLiesAboutTheContent() {
        // Websites often serve WebP under a .jpg name; LightCraft would choke on it.
        let c = Classification.classify(fileName: "bild.jpg", header: Data(webpHeader))
        XCTAssertEqual(c?.format, .webp)
        XCTAssertEqual(c?.fileExtension, "webp")
    }

    func testGivesAnExtensionLightCraftAccepts() {
        XCTAssertEqual(Classification.classify(fileName: "foto.jfif", header: Data(jpegHeader))?.fileExtension, "jpg")
        XCTAssertEqual(Classification.classify(fileName: "download", header: Data(pngHeader))?.fileExtension, "png")
    }

    func testRawFilesAreTIFFContainers() {
        XCTAssertEqual(Classification.classify(fileName: "DSC0001.ARW", header: Data(tiffHeader)),
                       Classification(format: .tiff, group: .raw, fileExtension: "arw"))
        XCTAssertEqual(Classification.classify(fileName: "IMG_1.CR3", header: Data(cr3Header))?.group, .raw)
        XCTAssertEqual(Classification.classify(fileName: "scan.tif", header: Data(tiffHeader))?.group, .photo)
    }

    func testANonImageWithAnImageNameIsRefused() {
        XCTAssertNil(Classification.classify(fileName: "rechnung.jpg", header: Data("%PDF-1.7".utf8)))
        XCTAssertNil(Classification.classify(fileName: "tool.png", header: Data([0xCF, 0xFA, 0xED, 0xFE])))
    }

    func testPartialDownloads() {
        XCTAssertTrue(PartialDownload.isPartial("foto.jpg.crdownload"))
        XCTAssertTrue(PartialDownload.isPartial("foto.jpg.download"))
        XCTAssertTrue(PartialDownload.isPartial("foto.jpg.part"))
        XCTAssertFalse(PartialDownload.isPartial("foto.jpg"))
    }

    func testSanitizedFileName() {
        XCTAssertEqual(SafeCopier.sanitizedFileName("bild.jpg", fileExtension: "webp"), "bild.webp")
        XCTAssertEqual(SafeCopier.sanitizedFileName("..versteckt.png", fileExtension: "png"), "versteckt.png")
        XCTAssertEqual(SafeCopier.sanitizedFileName("a:b.png", fileExtension: "png"), "a-b.png")
        XCTAssertEqual(SafeCopier.sanitizedFileName(" ", fileExtension: "png"), "Bild.png")
        let long = String(repeating: "ä", count: 300) + ".jpg"
        XCTAssertLessThanOrEqual(SafeCopier.sanitizedFileName(long, fileExtension: "jpg").utf8.count, 204)
    }

    func testStabilityNeedsAQuietPeriod() {
        var tracker = StabilityTracker(quietPeriod: 2)
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(tracker.isStable(path: "/a", size: 10, modified: t0, now: t0))
        XCTAssertFalse(tracker.isStable(path: "/a", size: 10, modified: t0, now: t0 + 1))
        XCTAssertFalse(tracker.isStable(path: "/a", size: 20, modified: t0 + 1, now: t0 + 2.5), "it grew: start over")
        XCTAssertTrue(tracker.isStable(path: "/a", size: 20, modified: t0 + 1, now: t0 + 4.5))
    }
}

final class LightCraftSetupTests: XCTestCase {
    let target = URL(fileURLWithPath: "/Users/test/Pictures/Aus Downloads")

    func testLibraryFromUISettings() {
        let ui = Data(#"{"settings":{"libraryPath":"/Volumes/Fotos/LightCraft Library"}}"#.utf8)
        XCTAssertEqual(LightCraftSetup.libraryFolder(uiJSON: ui).path, "/Volumes/Fotos/LightCraft Library")
        XCTAssertEqual(LightCraftSetup.libraryFolder(uiJSON: Data(#"{"settings":{"libraryPath":null}}"#.utf8)), LightCraftSetup.defaultLibrary)
        XCTAssertEqual(LightCraftSetup.libraryFolder(uiJSON: nil), LightCraftSetup.defaultLibrary)
    }

    func testStates() {
        func state(_ json: String?) -> LightCraftSetupState {
            LightCraftSetup.state(of: LightCraftSetup.autoImport(prefsJSON: json.map { Data($0.utf8) }), target: target)
        }
        XCTAssertEqual(state(nil), .off, "no prefs.json: preferences never changed")
        XCTAssertEqual(state(#"{"import":{"autoFolder":null}}"#), .off)
        XCTAssertEqual(state(#"{"import":{"autoFolder":"/Users/test/Pictures/Aus Downloads","autoCopy":false,"autoAlbum":"Aus Downloads"}}"#),
                       .ready(album: "Aus Downloads"))
        XCTAssertEqual(state(#"{"import":{"autoFolder":"/Users/test/Pictures/Aus Downloads/","autoCopy":true}}"#),
                       .readyButCopies(album: nil))
        XCTAssertEqual(state(#"{"import":{"autoFolder":"/Users/test/Tether"}}"#), .watchesOtherFolder("/Users/test/Tether"))
        XCTAssertEqual(state("kaputt"), .unknown)
    }
}

final class FileTests: XCTestCase {
    private var base: URL!
    private var downloads: URL { base.appendingPathComponent("Downloads") }
    private var target: URL { base.appendingPathComponent("Ziel") }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatcherCoreTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    @discardableResult
    private func write(_ name: String, header: [UInt8], size: Int = 40_000, quarantine: Bool = true, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? downloads).appendingPathComponent(name)
        var bytes = header
        bytes += (0..<max(0, size - header.count)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ name.count) }
        try Data(bytes).write(to: url)
        if quarantine {
            let value = "0083;00000000;Safari;"
            _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        }
        return url
    }

    func testCopyIsVerifiedNeverOverwritesAndKeepsQuarantine() throws {
        let source = try write("foto.jpg", header: jpegHeader)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("schon da".utf8).write(to: target.appendingPathComponent("foto.jpg"))

        let result = try SafeCopier.copy(source, into: target, fileName: "foto.jpg")
        XCTAssertEqual(result.destination.lastPathComponent, "foto-1.jpg")
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("foto.jpg")), Data("schon da".utf8))
        XCTAssertEqual(try Data(contentsOf: result.destination), try Data(contentsOf: source))
        XCTAssertEqual(result.sha256, try SafeCopier.sha256(of: source))
        XCTAssertTrue(FileProbe.isQuarantined(result.destination), "the copy is still marked as downloaded")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: target.path).filter { $0.hasPrefix(".") }
        XCTAssertEqual(leftovers, [], "no temporary files left behind")
    }

    func testSymbolicLinksAreNotFollowed() throws {
        let secret = try write("geheim.jpg", header: jpegHeader, in: base)
        let link = downloads.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        XCTAssertNil(FileProbe.header(link))
        XCTAssertThrowsError(try SafeCopier.copy(link, into: target, fileName: "link.jpg"))
    }

    // MARK: engine

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _events: [WatchEvent] = []
        var events: [WatchEvent] { lock.withLock { _events } }
        func add(_ e: WatchEvent) { lock.withLock { _events.append(e) } }
        var copied: [String] { events.compactMap { if case let .copied(_, _, d, _, _, _) = $0 { d.lastPathComponent } else { nil } } }
        var duplicates: [String] { events.compactMap { if case let .duplicate(_, n, _, _, _) = $0 { n } else { nil } } }
        var skipped: [String: SkipReason] {
            Dictionary(events.compactMap { if case let .skipped(n, r) = $0 { (n, r) } else { nil } }, uniquingKeysWith: { a, _ in a })
        }
        var problems: [WatchProblem?] { events.compactMap { if case let .problem(p) = $0 { p } else { nil } } }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        var _now = Date()
        var now: Date { lock.withLock { _now } }
        func advance(_ s: TimeInterval) { lock.withLock { _now += s } }
    }

    private func engine() -> (WatchEngine, Recorder, Clock) {
        let recorder = Recorder(), clock = Clock()
        let engine = WatchEngine(now: { clock.now }, onEvent: { recorder.add($0) })
        return (engine, recorder, clock)
    }

    /// Two passes, the second after the quiet period: what a real download sees.
    private func settle(_ engine: WatchEngine, _ clock: Clock, _ config: WatchConfiguration) {
        engine.scanForTesting(config)
        clock.advance(3)
        engine.scanForTesting(config)
    }

    func testEngineCopiesNewImagesAndLeavesTheRest() throws {
        let cutoff = Date().addingTimeInterval(-60)
        try write("vorher.jpg", header: jpegHeader)
        // Files added before the cutoff are left alone.
        let (engine, recorder, clock) = engine()
        var config = WatchConfiguration(watchFolder: downloads, targetFolder: target, cutoff: Date().addingTimeInterval(1))
        settle(engine, clock, config)
        XCTAssertEqual(recorder.copied, [])

        config.cutoff = cutoff
        try write("neu.jpg", header: jpegHeader)
        try write("falsch.jpg", header: webpHeader)
        try write("logo.png", header: pngHeader, size: 2_000)
        try write("rechnung.pdf", header: Array("%PDF-1.7".utf8))
        try write("selbst.png", header: pngHeader, quarantine: false)
        try write("laeuft.jpg.crdownload", header: jpegHeader)
        try write("bild.gif", header: Array("GIF89a".utf8))
        settle(engine, clock, config)

        XCTAssertEqual(Set(recorder.copied), ["vorher.jpg", "neu.jpg", "falsch.webp"])
        XCTAssertEqual(recorder.skipped["logo.png"], .tooSmall(2_000))
        XCTAssertEqual(recorder.skipped["rechnung.pdf"], .notAnImage)
        XCTAssertEqual(recorder.skipped["selbst.png"], .notDownloaded)
        XCTAssertEqual(recorder.skipped["bild.gif"], .groupOff(.gif))
        XCTAssertNil(recorder.skipped["laeuft.jpg.crdownload"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("neu.jpg").path), "the original stays")

        // A third pass changes nothing: every file is handled once.
        clock.advance(3)
        engine.scanForTesting(config)
        XCTAssertEqual(recorder.copied.count, 3)
    }

    func testEngineWaitsForAFileToSettle() throws {
        let (engine, recorder, clock) = engine()
        let config = WatchConfiguration(watchFolder: downloads, targetFolder: target, cutoff: .distantPast)
        let url = try write("gross.jpg", header: jpegHeader)
        engine.scanForTesting(config)
        XCTAssertEqual(recorder.copied, [], "just appeared: not yet")
        clock.advance(1)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 7, count: 1000))
        try handle.close()
        clock.advance(2)
        engine.scanForTesting(config)
        XCTAssertEqual(recorder.copied, [], "it grew in the meantime")
        clock.advance(3)
        engine.scanForTesting(config)
        XCTAssertEqual(recorder.copied, ["gross.jpg"])
    }

    func testEngineSkipsDuplicatesAndCanTrashTheOriginal() throws {
        let (engine, recorder, clock) = engine()
        var config = WatchConfiguration(watchFolder: downloads, targetFolder: target, cutoff: .distantPast)
        let first = try write("a.jpg", header: jpegHeader)
        settle(engine, clock, config)
        XCTAssertEqual(recorder.copied, ["a.jpg"])

        // The same picture downloaded again, under the name a browser gives it.
        try FileManager.default.copyItem(at: first, to: downloads.appendingPathComponent("a (1).jpg"))
        config.trashOriginal = true
        settle(engine, clock, config)
        XCTAssertEqual(recorder.duplicates, ["a (1).jpg"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path).filter { !$0.hasPrefix(".") }, ["a.jpg"])
    }

    func testAfterARestartAlreadyCopiedImagesStayQuiet() throws {
        // The previous session copied the image; the catch-up after the restart sees it again.
        let source = try write("alt.jpg", header: jpegHeader)
        _ = try SafeCopier.copy(source, into: target, fileName: "alt.jpg")
        let (engine, recorder, clock) = engine()
        clock._now = Date().addingTimeInterval(10)
        let config = WatchConfiguration(watchFolder: downloads, targetFolder: target, cutoff: .distantPast)
        settle(engine, clock, config)
        XCTAssertEqual(recorder.copied, [])
        XCTAssertEqual(recorder.duplicates, [], "not shown in the menu again")
        XCTAssertEqual(recorder.skipped["alt.jpg"], .alreadyCopied)
    }

    func testEnginePauses() throws {
        let (engine, recorder, clock) = engine()
        var config = WatchConfiguration(watchFolder: downloads, targetFolder: target, cutoff: .distantPast, paused: true)
        try write("a.jpg", header: jpegHeader)
        settle(engine, clock, config)
        XCTAssertEqual(recorder.copied, [])
        config.paused = false
        settle(engine, clock, config)
        XCTAssertEqual(recorder.copied, ["a.jpg"])
    }

    func testEngineRefusesATargetInsideTheWatchedFolder() throws {
        let (engine, recorder, clock) = engine()
        let config = WatchConfiguration(watchFolder: downloads, targetFolder: downloads.appendingPathComponent("Bilder"), cutoff: .distantPast)
        try write("a.jpg", header: jpegHeader)
        settle(engine, clock, config)
        XCTAssertEqual(recorder.copied, [])
        XCTAssertEqual(recorder.problems.last, .targetInsideWatchFolder)
    }

    func testEngineReportsAMissingDrive() throws {
        let (engine, recorder, clock) = engine()
        let config = WatchConfiguration(watchFolder: downloads, targetFolder: URL(fileURLWithPath: "/Volumes/GibtsNicht-\(UUID().uuidString)/Eingang"), cutoff: .distantPast)
        try write("a.jpg", header: jpegHeader)
        settle(engine, clock, config)
        XCTAssertEqual(recorder.copied, [])
        XCTAssertEqual(recorder.problems.last, .targetUnreachable)
    }
}
