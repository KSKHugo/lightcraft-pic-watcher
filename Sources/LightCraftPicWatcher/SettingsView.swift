import AppKit
import Combine
import SwiftUI
import WatcherCore

struct SettingsView: View {
    @Bindable var model: AppModel
    var showOnboarding: () -> Void
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(model: model, showOnboarding: showOnboarding)
                .tabItem { Label("Allgemein", systemImage: "gearshape") }.tag("general")
            FilterTab(model: model)
                .tabItem { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }.tag("filter")
            LightCraftTab(model: model)
                .tabItem { Label("LightCraft", systemImage: "photo.on.rectangle") }.tag("lightcraft")
            AboutTab()
                .tabItem { Label("Über", systemImage: "info.circle") }.tag("about")
        }
        .padding(.top, 8)
        .frame(width: 600, height: 520)
        .tint(.watcherAccent)
    }
}

/// Picks a folder with the system panel.
@MainActor
func chooseFolder(_ title: String, startingAt url: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
    NSApp.activate()
    return panel.runModal() == .OK ? panel.url : nil
}

struct PathRow: View {
    var label: String
    var url: URL
    var choose: () -> Void
    var reveal: (() -> Void)?

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(displayPath(url))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .help(url.path)
                Spacer()
                if let reveal { Button("Zeigen", action: reveal) }
                Button("Ändern …", action: choose)
            }
        }
    }
}

private struct GeneralTab: View {
    @Bindable var model: AppModel
    var showOnboarding: () -> Void

    var body: some View {
        Form {
            Section {
                PathRow(label: "Überwachter Ordner", url: model.prefs.watchFolder) {
                    if let url = chooseFolder("Überwachter Ordner", startingAt: model.prefs.watchFolder) { model.prefs.watchFolder = url }
                }
                PathRow(label: "Zielordner", url: model.prefs.targetFolder, choose: {
                    if let url = chooseFolder("Zielordner", startingAt: model.prefs.targetFolder) { model.prefs.targetFolder = url }
                }, reveal: { model.openTargetFolder() })
            } footer: {
                Text("Nur neue Dateien zählen. Kopiert wird direkt in den Zielordner, ohne Unterordner: LightCraft liest beim automatischen Import nur die oberste Ebene.")
                    .foregroundStyle(.secondary)
            }
            Section("Original im Download-Ordner") {
                Picker("Nach dem Kopieren", selection: $model.prefs.trashOriginal) {
                    Text("Liegen lassen").tag(false)
                    Text("In den Papierkorb legen").tag(true)
                }
                .pickerStyle(.radioGroup)
                Text("Erst nachdem die Kopie per Prüfsumme bestätigt ist. Die App löscht nie endgültig.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Beim Anmelden starten", isOn: $model.launchAtLogin)
                if model.loginItemStatus == .requiresApproval {
                    Text("macOS möchte das in den Systemeinstellungen unter „Allgemein → Anmeldeobjekte“ bestätigt haben.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Mitteilung zeigen, wenn Bilder übernommen wurden", isOn: $model.prefs.notify)
                Toggle("Symbol in der Menüleiste animieren", isOn: $model.prefs.animateIcon)
                Button("Ersteinrichtung erneut zeigen …", action: showOnboarding)
            } footer: {
                Text("Mit „Bewegung reduzieren“ in den Bedienungshilfen bleibt das Symbol immer still.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FilterTab: View {
    @Bindable var model: AppModel
    @State private var confirmExisting = false

    var body: some View {
        Form {
            Section("Dateitypen") {
                Toggle(isOn: $model.prefs.photos) { labeled("Fotos", "JPEG, HEIC, PNG, WebP, AVIF, TIFF, JPEG XL") }
                Toggle(isOn: $model.prefs.raw) { labeled("RAW-Dateien", "DNG, CR3, NEF, ARW, RAF, ORF, RW2 und weitere, die LightCraft liest") }
                Toggle(isOn: $model.prefs.gif) { labeled("GIF", "Meist Animationen oder Grafiken") }
                Toggle(isOn: $model.prefs.photoshop) { labeled("Photoshop-Dateien", "PSD, PSB") }
            }
            Section {
                LabeledContent("Mindestgröße") {
                    HStack {
                        TextField("", value: $model.prefs.minimumKB, format: .number)
                            .frame(width: 70).multilineTextAlignment(.trailing).labelsHidden()
                        Text("KB")
                    }
                }
                Toggle(isOn: $model.prefs.onlyDownloaded) {
                    labeled("Nur Dateien, die macOS als Download kennzeichnet", "Bilder, die du selbst in den Ordner legst, bleiben dann liegen.")
                }
            } footer: {
                Text("Kleinere Dateien sind meist Symbole oder Logos.").foregroundStyle(.secondary)
            }
            Section("Immer") {
                bullet("Unfertige Downloads (.download, .crdownload, .part) werden erst genommen, wenn die Datei 2 Sekunden lang nicht mehr wächst.")
                bullet("Der Inhalt zählt, nicht die Endung. Eine WebP-Datei mit der Endung .jpg wird als .webp kopiert, eine umbenannte Nicht-Bild-Datei gar nicht.")
                bullet("Duplikate erkennt die App an der Prüfsumme (SHA-256) und kopiert sie nicht noch einmal.")
                bullet("Bilder, die ankommen, während die App nicht läuft, holt sie beim nächsten Start nach (bis zu 7 Tage zurück).")
            }
            Section {
                Button("Bilder, die schon im Ordner liegen, jetzt übernehmen …") { confirmExisting = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Alle Bilder im überwachten Ordner übernehmen?", isPresented: $confirmExisting) {
            Button("Übernehmen") { model.includeExistingImages() }
        } message: {
            Text("Es gelten dieselben Filter. Bilder, die schon im Zielordner liegen, werden nicht noch einmal kopiert.")
        }
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bullet(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct LightCraftTab: View {
    let model: AppModel
    var compact = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section { LightCraftStatusBox(model: model) }
            Section {
                LightCraftSteps(model: model)
                HStack {
                    Button("Pfad kopieren") { model.copyTargetPath() }
                    Button("LightCraft öffnen") { model.openLightCraft() }.disabled(!model.lightCraft.installed)
                    Spacer()
                    Button("Erneut prüfen") { model.refreshLightCraft() }
                }
            } header: {
                Text("So kommt ein Bild in LightCraft")
            } footer: {
                Text("LightCraft hat einen eigenen automatischen Import. Er überwacht einen Ordner und nimmt neue Fotos auf, sobald sie vollständig sind. Diesen Ordner setzt du einmal auf den Zielordner des Pic Watchers.")
                    .foregroundStyle(.secondary)
            }
            if !compact {
                Section("Gut zu wissen") {
                    Text("LightCraft übernimmt nur, solange es geöffnet ist. Was vorher ankommt, nimmt es beim nächsten Start.")
                    Text("LightCraft kennt einen überwachten Ordner. Wer ihn schon für Tethering oder einen Scanner nutzt, muss sich entscheiden.")
                    Text("Der Pic Watcher liest die Einstellungen von LightCraft nur, um diesen Stand anzuzeigen. Er schreibt nichts in die LightCraft-Bibliothek und nutzt nicht den Steuerkanal von LightCraft.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLightCraft() }
        .onReceive(timer) { _ in model.refreshLightCraft() }
    }
}

struct LightCraftStatusBox: View {
    let model: AppModel

    var body: some View {
        let lc = model.lightCraft
        let (symbol, color, title, detail) = describe(lc)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func describe(_ lc: LightCraftStatus) -> (String, Color, String, String) {
        guard lc.installed else {
            return ("xmark.circle.fill", .orange, "LightCraft ist nicht installiert",
                    "Die Bilder landen trotzdem im Zielordner. LightCraft gibt es unter github.com/storytold/lightcraft.")
        }
        let name = "LightCraft" + (lc.version.map { " \($0)" } ?? "")
        let running = lc.running ? "läuft" : "ist geschlossen"
        switch lc.setup {
        case let .ready(album):
            return ("checkmark.circle.fill", .green, "\(name) ist eingerichtet und \(running)",
                    album.map { "Neue Bilder kommen ins Album „\($0)“." } ?? "Neue Bilder kommen in die Mediathek. Ein Album kannst du in LightCraft eintragen.")
        case .readyButCopies:
            return ("exclamationmark.triangle.fill", .orange, "\(name) überwacht den Zielordner, kopiert aber",
                    "Jedes Bild liegt dann zweimal auf der Platte. Schalte in LightCraft „In die Bibliothek kopieren“ aus.")
        case let .watchesOtherFolder(folder):
            return ("exclamationmark.triangle.fill", .orange, "\(name) überwacht einen anderen Ordner",
                    "Zurzeit: \(displayPath(URL(fileURLWithPath: folder))). LightCraft kennt nur einen überwachten Ordner.")
        case .off:
            return ("circle.dashed", .orange, "\(name): automatischer Import ist aus", "Richte ihn wie unten beschrieben ein.")
        case .unknown:
            return ("questionmark.circle", .secondary, "\(name) \(running)",
                    "Ob der automatische Import eingerichtet ist, lässt sich nicht feststellen. Prüfe es in LightCraft.")
        }
    }
}

struct LightCraftSteps: View {
    let model: AppModel

    var body: some View {
        let setup = model.lightCraft.setup
        let watches: Bool? = switch setup {
        case .ready, .readyButCopies: true
        case .unknown: nil
        default: false
        }
        let notCopying: Bool? = switch setup {
        case .ready: true
        case .readyButCopies: false
        default: nil
        }
        let album: String? = if case let .ready(a) = setup { a } else if case let .readyButCopies(a) = setup { a } else { nil }
        VStack(alignment: .leading, spacing: 8) {
            step(1, nil, Text("In LightCraft **Einstellungen → Import → Automatischer Import** öffnen."))
            step(2, watches, Text("Bei **Überwachter Ordner** „Auswählen …“ und `\(displayPath(model.prefs.targetFolder))` wählen."))
            step(3, notCopying, Text("**In die Bibliothek kopieren** ausschalten. Sonst liegt jedes Bild zweimal auf der Platte."))
            step(4, album.map { _ in true }, Text("Optional: bei **Album** einen Namen eintragen, etwa „Aus Downloads“.") + Text(album.map { " Eingetragen: „\($0)“." } ?? ""))
        }
    }

    private func step(_ n: Int, _ done: Bool?, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if done == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("\(n)").font(.caption.weight(.semibold)).frame(width: 16, height: 16)
                        .background(Circle().strokeBorder(.secondary.opacity(0.5)))
                }
            }
            .frame(width: 18)
            text.fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Entwicklung")
                LabeledContent("Lizenz", value: "MIT OR Apache-2.0")
                LabeledContent("Quellcode") {
                    Link("github.com/KSKHugo/lightcraft-pic-watcher",
                         destination: URL(string: "https://github.com/KSKHugo/lightcraft-pic-watcher")!)
                }
            }
            Section("Datenschutz und Sicherheit") {
                Text("**Kein Netzwerkcode.** Die App sendet nichts, auch keine Statistik.")
                Text("**Download-Ordner nur lesen.** Das Original bleibt, außer du wählst den Papierkorb.")
                Text("**Nichts wird überschrieben.** Gibt es den Namen schon, bekommt die Kopie „-1“, „-2“ usw.")
                Text("**Jede Kopie wird geprüft** (SHA-256) und behält die macOS-Download-Kennzeichnung.")
                Text("**Vorschaubilder** erzeugt Quick Look in einem eigenen, abgeschotteten Prozess.")
            }
            .font(.callout)
            Section {
                Text("Ein unabhängiges Projekt, kein offizielles LightCraft-Produkt. Es steht in keiner Verbindung zum LightCraft-Projekt.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
