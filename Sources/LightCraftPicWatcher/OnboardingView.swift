import SwiftUI

/// First run: access to Downloads, the target folder, LightCraft.
struct OnboardingView: View {
    @Bindable var model: AppModel
    var finish: () -> Void
    @State private var step = 0
    @State private var includeExisting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle().fill(i <= step ? Color.watcherAccent : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            .padding(.top, 22)

            Group {
                switch step {
                case 0: access
                case 1: target
                default: lightCraft
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            HStack {
                Button("Zurück") { step -= 1 }.disabled(step == 0)
                Spacer()
                Button(step == 2 ? "Fertig" : "Weiter") {
                    if step < 2 { step += 1 } else { model.finishOnboarding(includeExisting: includeExisting); finish() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(step == 0 && model.downloadsAccess != true)
            }
            .padding(14)
        }
        .frame(width: 560, height: 520)
        .tint(.watcherAccent)
    }

    private func heading(_ title: String, _ lead: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.title2.weight(.semibold))
            Text(lead).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var access: some View {
        VStack(spacing: 14) {
            heading("Zugriff auf „\(model.prefs.watchFolder.lastPathComponent)“",
                    "Der Pic Watcher muss sehen, was in deinem Download-Ordner ankommt. macOS fragt dich dafür einmal. Die App liest dort nur und sendet nichts ins Internet.")
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            switch model.downloadsAccess {
            case nil:
                Button("Zugriff erlauben …") { model.requestDownloadsAccess() }
                    .controlSize(.large).buttonStyle(.borderedProminent)
            case true?:
                Label("Zugriff erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            case false?:
                VStack(spacing: 8) {
                    Label("Kein Zugriff", systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.headline)
                    Text("Erlaube ihn unter Systemeinstellungen → Datenschutz & Sicherheit → Dateien und Ordner → LightCraft Pic Watcher → Downloads-Ordner.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    HStack {
                        Button("Systemeinstellungen öffnen") { model.openPrivacySettings() }
                        Button("Erneut prüfen") { model.requestDownloadsAccess() }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
    }

    private var target: some View {
        VStack(spacing: 0) {
            heading("Wohin sollen die Bilder?",
                    "Neue Bilder werden in diesen Ordner kopiert. Das Original im Download-Ordner bleibt, wenn du nichts anderes einstellst.")
            Form {
                PathRow(label: "Zielordner", url: model.prefs.targetFolder) {
                    if let url = chooseFolder("Zielordner", startingAt: model.prefs.targetFolder) { model.prefs.targetFolder = url }
                }
                Toggle("Beim Anmelden starten", isOn: $model.launchAtLogin)
                Toggle(isOn: $includeExisting) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bilder, die schon im Download-Ordner liegen, auch übernehmen")
                        Text("Sonst zählen nur Bilder, die ab jetzt ankommen.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    private var lightCraft: some View {
        VStack(spacing: 0) {
            heading("LightCraft verbinden",
                    "LightCraft holt neue Bilder selbst ab, wenn es den Zielordner überwacht. Das stellst du einmal in LightCraft ein; der Haken erscheint hier von allein.")
            LightCraftTab(model: model, compact: true)
        }
    }
}
