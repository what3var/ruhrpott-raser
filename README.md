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
