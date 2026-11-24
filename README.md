# LightCraft Pic Watcher

Eine kleine macOS-App für die Menüleiste. Sie beobachtet den Download-Ordner, kopiert jedes neu heruntergeladene Bild in einen Ordner deiner Wahl und übergibt es an die Mediathek von [LightCraft](https://github.com/storytold/lightcraft). Dort entscheidest du, ob du das Bild behältst und in welches Album oder welchen Ordner es kommt.

**Stand: Version 0.1, früher Stand.** Ein erster Test mit dem echten Download-Ordner lief durch. Mit Testordnern geprüft sind außerdem Kopie, Prüfsumme, Duplikate, Filter, Symbol-Animation, Menü, Einstellungen und Ersteinrichtung. Das [klickbare Mockup](2026-11-24_LightCraft-Pic-Watcher_App-Mockup.html) zeigt das ursprüngliche Konzept mit Beispieldaten.

## Download

Fertige Versionen liegen unter [Releases](https://github.com/KSKHugo/lightcraft-pic-watcher/releases) als Disk-Image. Die App ist mit einer Developer ID signiert und von Apple notarisiert. Sie läuft ab macOS 14 auf Apple Silicon und Intel. Zum Installieren die App aus dem Image in den Ordner „Programme“ ziehen und einmal öffnen; danach sitzt sie in der Menüleiste. Für „Beim Anmelden starten“ sollte sie in „Programme“ liegen.

## Ablauf

1. Ein Bild landet im Download-Ordner.
2. Der Pic Watcher wartet, bis der Download fertig ist, und prüft am Inhalt, ob es wirklich ein Bild ist.
3. Er kopiert es in den Zielordner (Standard: `~/Pictures/Aus Downloads`) und vergleicht die Kopie per SHA-256 mit dem Original. Während er kopiert, drehen sich zwei Pfeile am Symbol in der Menüleiste, danach erscheint kurz ein Haken.
4. LightCraft übernimmt das Bild über seinen eigenen automatischen Import, auf Wunsch gleich in ein Album wie „Aus Downloads“.
5. In LightCraft markierst du es als behalten (`P`) oder abgelehnt (`X`) und fügst es einem Album oder Ordner hinzu.

## Wie das Bild in LightCraft kommt

LightCraft hat einen eingebauten automatischen Import (Einstellungen → Import → Automatischer Import). Er überwacht einen Ordner, nimmt neue Fotos auf, sobald sie vollständig sind, und kann sie direkt einem Album zuordnen. Der Pic Watcher nutzt genau diesen Weg: Sein Zielordner ist der überwachte Ordner von LightCraft.

Die App liest dafür die Einstellungen von LightCraft (`~/Library/Application Support/LightCraft/ui.json` und `prefs.json` der Bibliothek) und zeigt an, ob der automatische Import auf den Zielordner zeigt. Sie schreibt dort nichts.

- In LightCraft „In die Bibliothek kopieren“ ausschalten, sonst liegt jedes Bild zweimal auf der Platte. Die App weist darauf hin.
- LightCraft übernimmt nur, solange es geöffnet ist. Was vorher ankommt, nimmt es beim nächsten Start.
- LightCraft kennt nur einen überwachten Ordner. Wer ihn schon für Tethering oder einen Scanner nutzt, muss sich entscheiden.
- LightCraft liest beim automatischen Import nur die oberste Ebene des Ordners. Deshalb kopiert der Pic Watcher ohne Unterordner. Die im ersten Mockup vorgesehenen Monatsordner gibt es aus diesem Grund nicht.
- Den Steuerkanal von LightCraft (`--control`) nutzt die App nicht: Er ist ohne Anmeldung erreichbar und deshalb standardmäßig aus.

Warum nicht gleich den Download-Ordner in LightCraft überwachen? Dann würde LightCraft beim Einschalten alle Bilder übernehmen, die dort schon liegen, auch Logos und Symbole. Der Pic Watcher nimmt nur neue Downloads, filtert nach Typ, Größe und Herkunft, erkennt Duplikate und zeigt den Fortschritt in der Menüleiste.

## Grundsätze

- **Kein Netzwerkcode.** Die App sendet nichts, auch keine Statistik.
- **Download-Ordner nur lesen.** Das Original bleibt liegen. Auf Wunsch kommt es nach geprüfter Kopie in den Papierkorb, nie endgültig gelöscht.
- **Nichts überschreiben.** Gibt es den Namen im Zielordner schon, bekommt die Kopie „-1“, „-2“ usw. Die Kopie entsteht unter einem versteckten Namen und wird erst nach der Prüfung umbenannt, LightCraft sieht also nie eine halbe Datei.
- **Heruntergeladene Dateien gelten als nicht vertrauenswürdig.** Die App prüft den Dateityp an den ersten Bytes, folgt keinen symbolischen Links und behält die macOS-Download-Kennzeichnung (Quarantäne) an der Kopie. Vorschaubilder erzeugt Quick Look in einem eigenen, abgeschotteten Prozess.
- **Falsche Endungen werden korrigiert.** Eine WebP-Datei, die eine Website als `.jpg` ausliefert, wird als `.webp` kopiert. Eine umbenannte Nicht-Bild-Datei wird gar nicht kopiert.
- **Unfertige Downloads abwarten.** Dateien mit `.download`, `.crdownload` oder `.part` und Dateien, die noch wachsen, bleiben liegen, bis sie 2 Sekunden unverändert sind.
- **Nachholen.** Bilder, die ankommen, während die App nicht läuft, holt sie beim nächsten Start nach, bis zu 7 Tage zurück.

## Aufbau

- `Sources/WatcherCore`: alles ohne Oberfläche. Erkennung am Inhalt, Filter, geprüfte Kopie, Duplikate, Beobachtung des Ordners, Lesen der LightCraft-Einstellungen.
- `Sources/LightCraftPicWatcher`: die App. Symbol in der Menüleiste (AppKit), Menü, Einstellungen und Ersteinrichtung (SwiftUI). Kein Dock-Symbol.
- `Tests/WatcherCoreTests`: Tests für den Kern, auch mit echten Dateien in einem Temp-Ordner.

## Bauen

Voraussetzung sind macOS 14 oder neuer und Xcode.

```bash
swift test
```

```bash
Scripts/build_app.sh
```

Die fertige App liegt danach in `dist/`. Sie ist nur ad hoc signiert und für den eigenen Mac gedacht. Beim ersten Start fragt macOS, ob die App auf den Download-Ordner zugreifen darf.

Das Disk-Image zum Download baut `Scripts/build_release.sh`: Universal-App, Developer-ID-Signatur, Notarisierung und Stapling, wie beim LightCraft Cloud Importer. Das Icon zeichnet `Scripts/make_icon.swift`.

Für einen Testlauf lassen sich die Einstellungen beim Start überschreiben, ohne die eigenen anzufassen, am besten mit einer Kopie der App unter anderer Bundle-ID:

```bash
open -n "dist/LightCraft Pic Watcher.app" --args -watchFolder /tmp/In -targetFolder /tmp/Out -onboardingDone YES -notify NO
```

## Offene Fragen

- Was macht LightCraft mit der Datei im Zielordner, wenn ein abgelehntes Bild in LightCraft gelöscht wird?
- Sollen auch andere Ordner als „Downloads“ beobachtet werden können, etwa der Schreibtisch für Bildschirmfotos? Technisch geht das schon über „Überwachter Ordner“.

## Sicherheit

Vor jedem Push und auf GitHub laufen `gitleaks`, `osv-scanner` und `semgrep`, wie in den anderen Projekten. Der Pre-Push-Hook führt vorher auch `swift test` aus.

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
