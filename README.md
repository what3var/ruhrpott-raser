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
forge build RuhrpottRaser.firesln --engine native -m RELEASE      # src/Raser.Tool/bin/linux-rel/Raser.Tool
tools/fetch-bochum.sh && tools/build-bochum.sh                     # Testregion Bochum-Innenstadt: Rohdaten -> Chunks -> world.png
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
forge build RuhrpottRaser.firesln -p Raser.Launcher --engine native -m RELEASE -o raser-launcher
raser-launcher                                                         # das Fenster
raser-launcher --check --server 127.0.0.1:7480 --user anna --password geheim --install spiel   # ohne Fenster: anmelden, News, Update
raser-launcher --check ... --register | --no-update | --play           # registrieren / nur vergleichen / danach das Spiel starten
raser-launcher --shot launcher.png --wait 3 --user anna --password geheim --update   # ohne Bildschirm: das Fenster als PNG
forge test src/Raser.Launcher/Raser.Launcher.fireproj --engine native  # Tests der reinen Funktionen
src/Raser.Launcher/testing/check_test.sh raser-launcher                # Ablauf mit Netz gegen den Ersatz-Server (Python)
```
