import SwiftUI
import WatcherCore

extension Color {
    static let watcherAccent = Color(red: 0.69, green: 0.31, blue: 0.11)
}

struct PopoverView: View {
    let model: AppModel
    var openSettings: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            route
            hints
            list
            Divider()
            HStack(spacing: 6) {
                Button(model.prefs.paused ? "Fortsetzen" : "Pausieren") { model.togglePause() }
                Button("Zielordner") { model.openTargetFolder(); close() }
                Button("LightCraft öffnen") { model.openLightCraft(); close() }
                    .disabled(!model.lightCraft.installed)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(10)
            Divider()
            VStack(spacing: 0) {
                MenuRow(title: "Einstellungen …", shortcut: "⌘,", key: ",", action: openSettings)
                MenuRow(title: "LightCraft Pic Watcher beenden", shortcut: "⌘Q", key: "q") { NSApp.terminate(nil) }
            }
            .padding(5)
        }
        .frame(width: 350)
        .tint(.watcherAccent)
        .onAppear { model.refreshLightCraft() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: TrayIcon.image(model.trayState))
                .renderingMode(.template)
                .foregroundStyle(Color.watcherAccent)
                .frame(width: 34, height: 34)
                .background(Color.watcherAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var title: String {
        switch model.trayState {
        case .warn: "Es gibt ein Problem"
        case .paused: "Pausiert"
        case .busy:
            if let name = model.history.first(where: { $0.status == .copying })?.name { "Kopiere „\(name)“" } else { "Kopiere …" }
        default: "Auf dem neuesten Stand"
        }
    }

    private var subtitle: String {
        switch model.trayState {
        case .paused:
            model.waiting > 0 ? "\(model.waiting) neue Datei\(model.waiting == 1 ? " wartet" : "en warten")" : "Neue Downloads warten, bis du fortsetzt"
        case .busy: "Mit Prüfsumme"
        default:
            model.copiedToday == 1 ? "Heute 1 Bild übernommen" : "Heute \(model.copiedToday) Bilder übernommen"
        }
    }

    private var route: some View {
        HStack(spacing: 6) {
            Text(displayPath(model.prefs.watchFolder)).lineLimit(1).truncationMode(.middle)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text(displayPath(model.prefs.targetFolder)).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .help("\(model.prefs.watchFolder.path) → \(model.prefs.targetFolder.path)")
    }

    @ViewBuilder private var hints: some View {
        if let problem = model.problem {
            Hint(text: problemText(problem), tone: .red)
        }
        let lc = model.lightCraft
        if !lc.installed {
            Hint(text: "LightCraft ist nicht installiert. Die Bilder landen trotzdem im Zielordner.", tone: .orange)
        } else {
            switch lc.setup {
            case .off, .watchesOtherFolder:
                Hint(text: "LightCraft überwacht den Zielordner noch nicht, deshalb kommen die Bilder nicht in die Mediathek.",
                     tone: .orange, action: ("Einrichten", openSettings))
            case .readyButCopies:
                Hint(text: "LightCraft kopiert jedes Bild noch einmal in seine Bibliothek. Schalte dort „In die Bibliothek kopieren“ aus.",
                     tone: .orange, action: ("Mehr", openSettings))
            case .ready:
                if !lc.running, model.history.contains(where: { $0.status == .copied && $0.date > Date().addingTimeInterval(-86_400) }) {
                    Hint(text: "LightCraft ist geschlossen. Die Bilder liegen im Zielordner und kommen beim nächsten Start in die Mediathek.", tone: .orange)
                }
            case .unknown:
                EmptyView()
            }
        }
    }

    private func problemText(_ problem: WatchProblem) -> String {
        switch problem {
        case .watchFolderUnreadable:
            "Der Ordner „\(model.prefs.watchFolder.lastPathComponent)“ lässt sich nicht lesen. Erlaube den Zugriff unter Systemeinstellungen → Datenschutz & Sicherheit → Dateien und Ordner."
        case .targetUnreachable:
            "„\(displayPath(model.prefs.targetFolder))“ ist nicht erreichbar, zum Beispiel weil das Laufwerk nicht verbunden ist. Es geht weiter, sobald der Ordner wieder da ist."
        case .targetInsideWatchFolder:
            "Der Zielordner liegt im überwachten Ordner. Wähle in den Einstellungen einen anderen."
        }
    }

    @ViewBuilder private var list: some View {
        let items = Array(model.history.prefix(8))
        if items.isEmpty {
            Text(model.prefs.onboardingDone ? "Noch keine Bilder übernommen. Lade ein Bild herunter, es erscheint hier." : "Noch nicht eingerichtet.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .padding(.horizontal, 14)
                .multilineTextAlignment(.center)
        } else {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    HistoryRow(item: item) { model.reveal(item); close() }
                }
            }
            .padding(6)
        }
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Thumbnail(url: item.status == .copied || item.status == .duplicate ? item.file : nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if item.status == .copying {
                        ProgressView().progressViewStyle(.linear).controlSize(.mini)
                    }
                }
                Spacer(minLength: 4)
                chip
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(hover ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }

    private var meta: String {
        var parts: [String] = []
        if let size = item.size { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        parts.append(item.date.formatted(Calendar.current.isDateInToday(item.date) ? .dateTime.hour().minute() : .dateTime.day().month().hour().minute()))
        if item.trashedOriginal { parts.append("Original im Papierkorb") }
        return parts.joined(separator: " · ")
    }

    private var help: String {
        switch item.status {
        case let .failed(reason): reason
        case .duplicate: "Schon im Zielordner: \(item.file?.lastPathComponent ?? "")"
        case .copied: "Im Finder zeigen: \(item.file?.lastPathComponent ?? "")"
        case .copying: "Wird kopiert"
        }
    }

    @ViewBuilder private var chip: some View {
        switch item.status {
        case .copying: Chip(text: "Kopiert …", color: .watcherAccent)
        case .copied: Chip(text: "Übernommen", color: .green)
        case .duplicate: Chip(text: "Schon vorhanden", color: .secondary)
        case .failed: Chip(text: "Fehler", color: .red)
        }
    }
}

private struct Chip: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

private struct Hint: View {
    enum Tone { case red, orange }
    var text: String
    var tone: Tone
    var action: (String, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.0, action: action.1).controlSize(.small)
            }
        }
        .foregroundStyle(tone == .red ? Color.red : Color.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background((tone == .red ? Color.red : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

private struct MenuRow: View {
    var title: String
    var shortcut: String
    var key: KeyEquivalent
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(hover ? Color.white.opacity(0.75) : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(hover ? Color.white : Color.primary)
            .background(hover ? Color.watcherAccent : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .onHover { hover = $0 }
    }
}
