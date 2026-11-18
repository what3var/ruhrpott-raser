# Ruhrpott-Raser

Online-Multiplayer-Spiel im Stil von GTA, gespielt in einer voxelbasierten Nachbildung von NRW.
Gleichzeitig der **Extremtest für die Programmiersprache [fire](https://github.com/what3var/fire)**.

- Voxel-Look wie Minecraft, aber feiner (20 cm Voxel, Schrägen für Diagonalen)
- Nachts zwischen Vice City und Cyberpunk, je nach Viertel unterschiedlich
- Welt wird zur Laufzeit aus offenen Geodaten (NRW Open Data, OSM) erzeugt
- Häuser mieten, zwielichtige Geschäfte betreiben, wilde Missionen

## Dokumente

- [Konzept](docs/KONZEPT.md): Architektur, Weltpipeline, Rendering, Gameplay
- [Roadmap](ROADMAP.md): Meilensteine und offene Fragen
- [Weltpipeline](docs/PIPELINE.md): Stand von M1, Projekte, Formate, Messwerte
- [Server](docs/SERVER.md): Stand von M4, Prozesse, Ports, Launcher-API, Spielprotokoll, Konten
- [Inventar und Karte](docs/INVENTAR.md): Taschen, Hände, Rucksack, Handy, Bedienung, Operationen, Synchronisation mit dem Server, Karte
- [Was das Projekt in fire findet](docs/FIRE.md): Fehler, Lücken und Umwege
- [Override-Layer](overrides/README.md)

## Aufbau

`RuhrpottRaser.firesln` ist eine fire-Solution mit den Projekten `Raser.Core`, `Raser.World`, `Raser.Import` (Bibliotheken, je mit Tests in `testing/`)
und `Raser.Tool` (das Werkzeug der Pipeline):

```bash
forge test RuhrpottRaser.firesln                                   # alle Tests
forge build RuhrpottRaser.firesln --engine native -m RELEASE --toolchain gcc      # src/Raser.Tool/bin/linux-rel/Raser.Tool
tools/fetch-bochum.sh && tools/build-bochum.sh                     # Testregion Bochum-Innenstadt: Rohdaten -> Chunks -> world.png
```

### Weltdaten einrichten (auch unter Windows)

Das Spiel braucht fertige Weltdaten in `world/` (nicht im Repository: Kacheln 31 MB, Chunks 450 MB, Netz-Cache 1,9 GB). Ohne Shell-Skripte,
mit dem Werkzeug selbst (`src/Raser.Tool/setup.fire`):

```bash
forge build RuhrpottRaser.firesln -p Raser.Tool --engine native -m RELEASE --toolchain gcc -o raser
raser setup                 # Rohdaten laden (DGM1/LoD2 von opengeodata.nrw.de, OSM), importieren, voxelisieren - etwa 40 min
raser setup --meshes 1      # dazu den Netz-Cache (noch etwa 45 min; sonst baut ihn das Spiel beim Fahren nach und nach)
raser fetch                 # nur die Rohdaten nach data/raw (fortsetzbar, Vorhandenes wird übersprungen)
```

Andere Ausschnitte (je Region eigene Ordner): `--region lichtendorf` ist die A1 an der Raststätte Lichtendorf (Schwerte/Dortmund: Autobahn mit
drei bis vier Fahrstreifen je Richtung, Rastanlage auf beiden Seiten, Anschlussstelle; 3 x 3 km Kacheln, etwa 45 min mit `--jobs 2`),
`--bbox lon0,lat0,lon1,lat1` ein beliebiger Ausschnitt in Grad (die 1-km-Kacheln von DGM1 und LoD2 ergeben sich aus den Ecken, OSM kommt in
Teilen):

```bash
raser setup --region lichtendorf --raw data/raw-lichtendorf --world world-lichtendorf --jobs 2
raser-game --world world-lichtendorf --at 402300,5702000
```

Unter Windows heißt das Programm `raser.exe`; Optionen: `--raw <ordner>` (Rohdaten, Vorgabe `data/raw`), `--world <ordner>` (Vorgabe `world`),
`--jobs <n>` (Worker-Threads). Voxelisieren und Netz-Cache laufen auf allen Kernen, je Kachel ein Worker (`fire dedicated`); beim Voxelisieren
braucht ein Worker bis gut 2 GB, darum höchstens so viele, wie in 80 % des freien Speichers passen. Wichtig: das Werkzeug nativ als Release
bauen (`--engine native -m RELEASE --toolchain gcc`), in der VM ist es ein Vielfaches langsamer. `--toolchain gcc` (bzw. `clang`, unter Windows `msvc`) ist seit fire 58efe6cb nötig: `forge build` nimmt sonst TinyCC, das schnell übersetzt, aber deutlich langsameren Code erzeugt.

## Menü im Spiel

Esc öffnet das Menü (`src/Raser.Game/menu.fire`, mit dem UI-Toolkit von fire): Weiter, Optionen (Grafik, Steuerung, Ton, Spiel), Steuerung
(alle Tasten, umbelegbar), Verbindung (online), Beenden. Offline hält es das Spiel an, online läuft die Welt weiter, der eigene Wagen bekommt
keine Eingaben. Die Optionen stehen in `spiel.json` neben `launcher.json` (`RASER_CONFIG` oder `--config` für einen anderen Ordner,
`--settings 0` ohne Datei); was auf der Kommandozeile steht (`--size`, `--gpu`, `--render-threads`, `--near`, `--far`, `--workers`, `--no-sky`),
geht vor (dazu `--fullscreen 1`). Vollbild, Sichtweite, Himmel, Render-Threads und Kamera wirken sofort, Fenstergröße, Renderer und Worker nach einem Neustart.

```bash
raser-game --menu-shot menu.png [--menu-keys down,enter,right] [--menu-bench 100000]   # das offene Menü ohne Fenster als PNG
forge test src/Raser.Game/Raser.Game.fireproj --engine native                          # Einstellungen und Tastenbelegung
```

## Launcher

`Raser.Launcher` ist das Programm, mit dem Spieler anfangen: Anmeldung oder Registrierung am Spielserver (HTTP/JSON, Port 7480), News, Version mit
Notizen, Update der Installation und der Start des Spiels mit `--server <host>:7481 --token <token> --user <name>` (dazu `--world <install>/world`,
wenn die Installation eine Welt hat). Server und Benutzername merkt er sich in `launcher.json` im Konfigurationsordner (`~/.config/ruhrpott-raser`,
`%APPDATA%\RuhrpottRaser`, `~/Library/Application Support/RuhrpottRaser`; `RASER_LAUNCHER_CONFIG` oder `--config` für einen anderen) - das Passwort
und den Token nie. Die Installation liegt standardmäßig in `~/.local/share/ruhrpott-raser`.

Updates: jede Datei der Liste (`/api/version`) muss ein relativer Pfad ohne `..` sein, sonst lehnt er das ganze Update ab. Eine Datei wird nach
`<install>/.raser-tmp` geladen, gegen Größe und SHA-256 geprüft und erst dann an ihren Platz umbenannt; `<install>/.raser-install.json` merkt sich
Größe, Zeit und SHA-256 der installierten Dateien (so wird beim nächsten Start nicht alles neu gehasht). Gelöscht werden nur Dateien, die der Launcher
selbst installiert hat und die das Release nicht mehr hat. Netzarbeit läuft in eigenen Threads (`fire dedicated`), das Fenster bleibt bedienbar.

```bash
forge build RuhrpottRaser.firesln -p Raser.Launcher --engine native -m RELEASE --toolchain gcc -o raser-launcher
raser-launcher                                                         # das Fenster
raser-launcher --check --server 127.0.0.1:7480 --user anna --password geheim --install spiel   # ohne Fenster: anmelden, News, Update
raser-launcher --check ... --register | --no-update | --play           # registrieren / nur vergleichen / danach das Spiel starten
raser-launcher --shot launcher.png --wait 3 --user anna --password geheim --update   # ohne Bildschirm: das Fenster als PNG
forge test src/Raser.Launcher/Raser.Launcher.fireproj --engine native  # Tests der reinen Funktionen
src/Raser.Launcher/testing/check_test.sh raser-launcher                # Ablauf mit Netz gegen den Ersatz-Server (Python)
```
