# DesktopPet

Ein kleines Pixel-Haustier, das auf deinem Mac-Desktop lebt: es läuft am unteren
Bildschirmrand herum, hat Hunger/Laune/Energie, du kannst es füttern und
streicheln, und es merkt sich seinen Zustand auch über einen Neustart hinweg.

Gebaut als native macOS-App (Swift + AppKit, kein Electron) — daher sehr
leichtgewichtig und mit einem echten transparenten "Overlay"-Fenster, das über
allen anderen Fenstern schwebt.

## Features (v1)

- **3 Pixel-Haustiere** zur Auswahl: Katze, Hund, Hase — komplett prozedural aus
  Pixel-Formen gezeichnet (kein Bild-Asset nötig).
- Läuft frei am unteren Bildschirmrand hin und her, bleibt stehen, schläft,
  reagiert je nach Laune (fröhlich / neutral / traurig / hungrig).
- **Interagiert mit deinen echten Fenstern:**
  - setzt sich auf **Fenster-Oberkanten** und läuft darauf herum
  - **springt** auf Fenster, die in Reichweite sind
  - **klettert** an den Bildschirmrändern hoch (Sprite dreht sich mit) und steigt
    oben auf eine Fensterkante über
  - **fällt** mit Schwerkraft, wenn es über die Kante läuft, das Fenster
    geschlossen wird oder du es fallen lässt
  - **fährt flüssig mit**, wenn du das Fenster verschiebst, auf dem es sitzt
    (Physik läuft mit 60 Hz, das Pet klebt bildgenau auf der Kante)
  - Kanten, die hinter anderen Fenstern liegen, werden ignoriert — das Pet steht
    nie auf einer unsichtbaren Kante
- Klicks gehen durch die transparenten Bereiche hindurch: nur das Pet selbst
  fängt Mausklicks ab.
- **Füttern** und **Streicheln** (einfach kurz anklicken) über das
  Rechtsklick-Menü am Pet, über die Menüleiste, oder per systemweitem
  Tastenkürzel (Standard ⌘F / ⌘S — funktioniert überall, nicht nur bei
  geöffnetem Menü).
- Hunger/Laune/Energie verändern sich mit der Zeit — auch während die App
  geschlossen ist (Zustand wird lokal gespeichert und beim nächsten Start
  "nachgerechnet").
- Kein Dock-Icon, läuft nur als Menüleisten-Helfer: monochromes SF-Symbol des
  aktuellen Tiers (passt sich hellem/dunklem Menübalken an), darunter ein
  natives Menü mit Status, Aktionen (⌘F / ⌘S) und Tier-Auswahl.
- **Echtes Einstellungsfenster** (⌘, oder "Einstellungen…" im Menü):
  - Tastenkürzel für Füttern/Streicheln frei belegbar (klicken, Tastenkombi
    drücken — wie die Shortcut-Recorder in Systemeinstellungen)
  - Lauf-Tempo per Schieberegler
  - Startbildschirm bei Multi-Monitor-Setups
  - "Bei der Anmeldung starten" (echter Login-Item-Schalter, via
    `SMAppService`)
- Pet lässt sich mit der Maus greifen und woanders hinziehen.

## Entwicklung / Ausführen

Voraussetzung: Xcode (für den Swift-Compiler) unter macOS.

```bash
swift run
```

Startet die App direkt aus dem Quellcode (Debug-Build).

## Eine richtige, doppelklickbare App bauen

```bash
Scripts/build_app.sh --dmg
```

Erzeugt:

- `dist/DesktopPet.app` — die fertige App (Release-Build, eigenes Icon,
  ad-hoc signiert)
- `dist/DesktopPet.dmg` — ein Installer-Image zum Weitergeben/Runterladen

`dist/DesktopPet.app` kann direkt per Doppelklick gestartet werden, oder in
den `Applications`-Ordner gezogen werden. Beim ersten Start ggf. Rechtsklick →
"Öffnen", da die App nur ad-hoc (nicht mit einer Apple-Developer-ID) signiert
ist — macOS Gatekeeper fragt sonst nach, weil sie nicht notarisiert ist.

## Projektstruktur

```
Sources/DesktopPet/
  main.swift              App-Einstieg (+ Dev-Flags, siehe unten)
  AppDelegate.swift        Verdrahtet Fenster + Menüleiste
  PetWindowController.swift Erzeugt das transparente Overlay-Fenster
  PetView.swift             Zeichnet das Pixel-Sprite, Drag & Rechtsklick-Menü
  PetMenuBuilder.swift      Gemeinsames Menü für Menüleiste + Rechtsklick
  PetEngine.swift           "Gehirn": Timer, Physik, Zustandsmaschine
  WindowScanner.swift       Findet Fensterkanten (inkl. Verdeckungs-Prüfung)
  PetState.swift            Hunger/Laune/Energie + Speichern/Laden
  BehaviorState.swift       idle/walk/eating/sleeping + Laune-Level
  PetKind.swift              Katze/Hund/Hase + Farbpaletten
  SpriteBuilder.swift        Zeichnet ein Pixel-Frame aus Formen (Ellipsen etc.)
  PixelCanvas.swift          Kleines Pixel-Grid + Zeichen-Hilfsfunktionen
  StatusBarController.swift  Menüleisten-Symbol + Menü
  IconExporter.swift         Rendert das App-Icon aus dem Katzen-Sprite
  SettingsStore.swift         Persistierte Einstellungen (Shortcuts, Tempo, …)
  SettingsWindowController.swift Das Einstellungsfenster
  ShortcutRecorderControl.swift  "Klick + Taste drücken"-Steuerelement
  KeyboardShortcut.swift      Modell für ein Tastenkürzel (Codable)
  GlobalHotKeyManager.swift   Systemweite Hotkeys (Carbon, keine Berechtigung nötig)
```

Nützliche Dev-Flags von `main.swift`:

```bash
# Sprite als ASCII-Grid ausgeben (schnelles Debuggen ohne Bild)
.build/debug/DesktopPet --print-ascii cat

# Ein Pixel-Frame als PNG exportieren, z.B. zum Anschauen
.build/debug/DesktopPet --export-icon /tmp/preview.png dog happy

# Menü-Struktur als Text ausgeben (prüfen ohne Screenshot)
.build/debug/DesktopPet --dump-menu

# Physik live mitschreiben: Position, Zustand, gefundene Fensterkanten
# (optional: Start-X-Position, z.B. nah am linken Rand)
.build/debug/DesktopPet --trace 30 100
```

## Ressourcen

Rund 1,5–2 % CPU und ~45 MB RAM im Betrieb. Die Physik läuft mit 60 Hz, aber
teure Dinge sind entkoppelt: die Fenster-Abfrage für das Fenster, auf dem das Pet
sitzt, läuft nur mit 20 Hz — und schaltet erst auf jeden Frame hoch, sobald sich
das Fenster tatsächlich bewegt (also während du es ziehst). Neu gezeichnet wird
nur, wenn sich wirklich Pixel ändern.

## Zu den Fenster-Rechten

Für das Klettern auf Fenstern liest die App nur die **Geometrie** der offenen
Fenster (`CGWindowListCopyWindowInfo`) — Position und Größe. Das geht ohne
jede Sonderberechtigung. Fenster*titel* oder Inhalte werden bewusst **nicht**
gelesen; das würde die Bildschirmaufnahme-Berechtigung erfordern.

Die systemweiten Tastenkürzel (Füttern/Streicheln) laufen über Carbons
`RegisterEventHotKey` statt über einen globalen Tastatur-Monitor — dafür
braucht macOS ebenfalls keine Input-Monitoring-Berechtigung.

## Bekannte Einschränkungen

- Nur ein Pet gleichzeitig sichtbar (Wechsel über Menü ersetzt die Figur, der
  Zustand Hunger/Laune bleibt aber erhalten).
- Beim Griff an den Bildschirmrand "hüpft" das Pet die letzten ~70 px zur Kante,
  statt sie heranzulaufen.
- Multi-Monitor funktioniert grundsätzlich (das Pet rechnet mit dem Bildschirm,
  auf dem es gerade ist), ist aber kaum getestet.
- App ist nur ad-hoc signiert, nicht notarisiert — für eine "richtige"
  Verteilung außerhalb des eigenen Rechners bräuchte es eine Apple Developer-ID
  und Notarisierung.
- "Bei der Anmeldung starten" nutzt `SMAppService` und braucht daher die
  gebaute `.app` (nicht `swift run`); macOS kann den Login-Eintrag zudem in
  Systemeinstellungen → Allgemein → Anmeldeobjekte als "braucht Bestätigung"
  anzeigen, bis man ihn dort einmal freigibt.

## Ideen für später

- Mehr Animationen/Reaktionen (z.B. Sprechblase beim Füttern), weitere Tiere.
- Verschiedene Futter-Arten per Drag&Drop.
- Sound-Effekte.
- Auto-Update-Mechanismus, falls die App außerhalb des eigenen Rechners
  verteilt wird.
