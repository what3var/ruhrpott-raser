# Konzept: Ruhrpott-Raser

## 1. Voxel-Größe und Fahren

- **Voxelgröße 25 cm** (1/4 Minecraft). Pro Volumen sind das 64× mehr Voxel als bei Minecraft.
  - Chunks/Bricks deshalb größer wählen (z. B. 64³ = 16 m Kantenlänge).
  - LOD ist ab Tag 1 Pflicht.
- **Diagonalen:** Zusätzlich zu Würfeln gibt es Sonderformen (Schrägen, Viertelkeile). Die bringen mehr als noch kleinere Voxel.
- **Fahrphysik getrennt von der Optik:** Straßen und Gelände bekommen ein eigenes, glattes Kollisionsmesh aus dem Zwischenlayer. Fahrzeuge fahren nie direkt auf Voxel-Treppen.

## 2. Weltpipeline

```
Rohdaten ──► Zwischenlayer (semantisch, vektorbasiert) ──► Voxel-Chunks (deterministisch)
 (Server, einmal je Kachel)   (Datenbank, persistent)         (Client oder Server, cachebar)
```

### Rohdaten

| Quelle | Inhalt |
|---|---|
| NRW Open Data: DGM1 | Geländemodell mit 1-m-Raster |
| NRW Open Data: 3D-Gebäudemodelle LoD2 | Grundrisse, Höhen, Dachformen |
| NRW Open Data: DOP | Luftbilder für Dach- und Bodenfarben |
| OpenStreetMap | Straßen, Landnutzung, POIs |
| Mapillary / Panoramax | Straßenfotos als Vorlage für Fassaden |

> Lizenzen vor der Nutzung prüfen. Google Street View scheidet nach dessen Nutzungsbedingungen aus.

### Zwischenlayer (pro Kachel, z. B. 256 × 256 m)

- Gebäude: Grundriss, Höhe, Dachtyp, Fassaden-Parameter, ID (für Mietbarkeit)
- Straßengraph: Spuren, Breite, Belag
- Landnutzung, Höhenraster
- Gameplay-Tags: Viertel-Typ, „Mood“ für Nachtbeleuchtung, POIs für Missionen

### Generierung

- **On-the-fly:** Eine Kachel wird beim ersten Betreten erzeugt. Beim Serverstart wird ein Kerngebiet vorbereitet.
- **Vorausgenerierung in Fahrtrichtung:** Bei 200 km/h sind es etwa 55 m/s. Mehrere Kilometer Vorlauf entlang der Route, nicht nur ein Radius um den Spieler.
- **Deterministische Voxelisierung:** Zwischenlayer + Seed ergeben immer denselben Chunk. Der Client voxelisiert selbst, der Server schickt nur den Zwischenlayer und Spieler-Deltas.

### Speicherung

- **PostGIS:** Zwischenlayer, räumliche Abfragen
- **Key-Value-Store** (z. B. RocksDB): Chunk-Deltas, Schlüssel `(kachel, chunk)`

## 3. Fassadentexturen

Fassadentexturen sind sehr klein (< 100 px breit). Sie werden in drei Ebenen beschrieben statt als Bild gespeichert:

1. **Fassaden-Grammatik:** Etagen, Fensterraster, Fenstertyp, Erdgeschoss-Typ (Laden, Kneipe, Garage), Farben. Ein paar Dutzend Bytes pro Gebäude.
2. **Material als parametrische Wellenfunktion:** Putz, Klinker, Waschbeton, Wellblech. Regelmäßige Pulse z. B. für Mauerwerk.
3. **Optionales Residuum:** kleine Textur mit Palette für Besonderheiten wie Graffiti oder Schilder.

- **Erkennung:** Ein KI-gestütztes Tool wandelt ein Foto in Grammatik-Parameter um.
- **Fallback:** Gebäude ohne Foto bekommen plausible Parameter aus Baujahr, Viertel und LoD2-Typ.
- **Datenschutz/Marken:** Gesichter, Kennzeichen und Firmenlogos werden nicht übernommen.

**Rendering:** Pixel werden nearest-neighbor gerendert, aber antialiased. Das geschieht als „sharp bilinear“ direkt im Shader (Pixel-Art-AA über `fwidth`) statt mit vorab hochskalierten Texturen. Der Effekt ist derselbe, es braucht keinen zusätzlichen Speicher und funktioniert in jeder Entfernung.

## 4. Nacht-Atmosphäre

Der „Mood“ eines Viertels wird aus Landnutzung und POIs abgeleitet:

| Viertel-Typ | Stimmung |
|---|---|
| Industrie / Hütte / Hafen | Orange-rote Glut, Dampf, Natriumdampflampen |
| Innenstadt / Kneipenmeile | Neon in Magenta und Cyan, Richtung Vice City |
| Hochhaussiedlung / Gewerbe | Kaltes Blau, Werbetafeln, Richtung Cyberpunk |
| Zechensiedlung / Vorort | Warm, dunkel, wenige Laternen |

Technik dafür: Clustered Forward oder Deferred Rendering für viele Lichtquellen, emissive Voxel, Bloom, Nebel, nasse Straßen mit Reflexionen.

## 5. Gameplay

- **Häuser mieten:** Jedes LoD2-Gebäude ist potenziell mietbar. Innenräume werden prozedural aus Grundriss und Nutzung erzeugt, erst beim ersten Betreten.
- **Zwielichtige Geschäfte:** Wirtschaftssimulation mit Tarnfirma, Umsatz, Polizei-Aufmerksamkeit und Konkurrenz durch Spieler. Der Standort zählt.
- **Missionen:** Ein Generator nutzt echte POIs als Ziele, dazu kommen handgebaute Story-Missionen an festen Orten.

## 6. Multiplayer

- Der Server ist autoritativ, Fahrzeuge laufen mit Client-Prediction.
- Interest-Management pro Kachel: Synchronisiert wird nur, was in der Nähe ist.
- Zerstörung und Umbau werden als Deltas zum deterministischen Grundzustand übertragen und gespeichert.

## 7. Was fire leisten muss

Das Projekt soll die Sprache in allen Bereichen belasten:

- Nebenläufigkeit: Generierungs-Worker, Server-Tick, Streaming
- Netzwerk-I/O: Spielerprotokoll, Datenbankanbindung
- GPU-Anbindung: Rendering, ggf. Compute für Meshing
- Speicherlayout: dichte Voxel-Daten, Bricks, Kompression
- Serialisierung: Zwischenlayer, Deltas, Netzwerkpakete
- Werkzeuge: Import der Geodaten, Fassaden-Tool
