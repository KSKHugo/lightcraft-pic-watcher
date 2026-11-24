# LightCraft Pic Watcher

Eine kleine macOS-App für die Menüleiste. Sie beobachtet den Download-Ordner, kopiert jedes neu heruntergeladene Bild in einen Ordner deiner Wahl und übergibt es an die Mediathek von [LightCraft](https://github.com/storytold/lightcraft). Dort entscheidest du, ob du das Bild behältst und in welches Album oder welchen Ordner es kommt.

**Stand: Konzept mit klickbarem Mockup.** Es gibt noch keinen App-Code. Das [Mockup](2026-11-24_LightCraft-Pic-Watcher_App-Mockup.html) zeigt Menüleiste, Einstellungen, Ersteinrichtung und das Sortieren in LightCraft mit Beispieldaten.

## Ablauf

1. Ein Bild landet im Download-Ordner.
2. Der Pic Watcher wartet, bis der Download fertig ist, und prüft am Inhalt, ob es wirklich ein Bild ist.
3. Er kopiert es in den Zielordner, zum Beispiel `~/Bilder/Aus Downloads/2026-11/`, und vergleicht die Kopie per SHA-256 mit dem Original. Während er kopiert, dreht sich das Symbol in der Menüleiste, danach erscheint kurz ein Haken.
4. LightCraft übernimmt das Bild über seinen eigenen automatischen Import ins Album „Aus Downloads“.
5. In LightCraft markierst du es als behalten (`P`) oder abgelehnt (`X`) und fügst es einem Album oder Ordner hinzu.

## Wie das Bild in LightCraft kommt

LightCraft hat einen eingebauten automatischen Import (Einstellungen → Import → Automatischer Import). Er überwacht einen Ordner, nimmt neue Fotos auf, sobald sie vollständig sind, und kann sie direkt einem Album zuordnen. Der Pic Watcher nutzt genau diesen Weg: Sein Zielordner ist der überwachte Ordner von LightCraft.

- In LightCraft „In die Bibliothek kopieren“ ausschalten, sonst liegt jedes Bild zweimal auf der Platte.
- LightCraft übernimmt nur, solange es geöffnet ist. Was vorher ankommt, nimmt es beim nächsten Start.
- LightCraft kennt nur einen überwachten Ordner. Wer ihn schon für Tethering oder einen Scanner nutzt, muss sich entscheiden.
- Der Pic Watcher schreibt nicht in die LightCraft-Bibliothek. Den Steuerkanal von LightCraft (`--control`) nutzt er ebenfalls nicht: Er ist ohne Anmeldung erreichbar und deshalb standardmäßig aus.

Warum nicht gleich den Download-Ordner in LightCraft überwachen? Dann würde LightCraft beim Einschalten alle Bilder übernehmen, die dort schon liegen, auch Logos und Symbole. Der Pic Watcher nimmt nur neue Downloads, filtert nach Typ, Größe und Herkunft, erkennt Duplikate, ordnet nach Monat und zeigt den Fortschritt in der Menüleiste.

## Grundsätze

- **Kein Netzwerkcode.** Die App sendet nichts, auch keine Statistik.
- **Download-Ordner nur lesen.** Das Original bleibt liegen. Auf Wunsch kommt es nach geprüfter Kopie in den Papierkorb, nie endgültig gelöscht.
- **Nichts überschreiben.** Gibt es den Namen im Zielordner schon, bekommt die Kopie „-1“, „-2“ usw.
- **Heruntergeladene Dateien gelten als nicht vertrauenswürdig.** Die App prüft den Dateityp an den ersten Bytes, folgt keinen symbolischen Links, behält die macOS-Download-Kennzeichnung (Quarantäne) an der Kopie und erzeugt Vorschaubilder nur mit den Systembibliotheken.
- **Unfertige Downloads abwarten.** Dateien mit `.download`, `.crdownload` oder `.part` und Dateien, deren Größe sich noch ändert, bleiben liegen.

## Geplanter Aufbau

- Native macOS-App in Swift und SwiftUI (`MenuBarExtra`), ab macOS 14, Apple Silicon und Intel.
- Beobachtung des Download-Ordners mit FSEvents.
- Start beim Anmelden über `SMAppService`.
- Kein Dock-Symbol (`LSUIElement`).
- Verteilung wie beim LightCraft Cloud Importer als signiertes und notarisiertes Disk-Image, nicht über den Mac App Store.

## Offene Fragen

- Lässt sich erkennen, ob LightCraft den Zielordner bereits überwacht? Dann könnte die App den Einrichtungsschritt selbst prüfen.
- Was macht LightCraft mit der Datei im Zielordner, wenn ein abgelehntes Bild in LightCraft gelöscht wird?
- Sollen auch andere Ordner als „Downloads“ beobachtet werden können, etwa der Schreibtisch für Bildschirmfotos?

## Sicherheit

Vor jedem Push und auf GitHub laufen `gitleaks`, `osv-scanner` und `semgrep`, wie in den anderen Projekten.

```bash
brew install gitleaks osv-scanner semgrep
```

```bash
Scripts/install_hooks.sh
```

Von Hand: `Scripts/security_check.sh`. GitHub Actions führt denselben Check bei jedem Push, jedem Pull Request und wöchentlich aus. Dependabot hält die Actions aktuell.

## Lizenz

Copyright (c) 2026 Pascal Hugo

Dieses Projekt steht wahlweise unter einer der beiden folgenden Lizenzen (`MIT OR Apache-2.0`):

- [MIT-Lizenz](LICENSE-MIT)
- [Apache-Lizenz 2.0](LICENSE-APACHE)

Das ist dieselbe Lizenz wie bei LightCraft selbst und beim LightCraft Cloud Importer. Code lässt sich so zwischen den Projekten austauschen. Die Apache-Lizenz enthält zusätzlich eine ausdrückliche Patentlizenz.

Sofern du nichts anderes angibst, wird jeder Beitrag, den du zur Aufnahme in dieses Projekt einreichst, ebenfalls unter diesen beiden Lizenzen veröffentlicht, ohne zusätzliche Bedingungen.

## Hinweis zu Marken

Der LightCraft Pic Watcher ist ein unabhängiges Projekt und kein offizielles LightCraft-Produkt. Er steht in keiner Verbindung zum LightCraft-Projekt.
