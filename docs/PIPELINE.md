# Weltpipeline: Stand M1

Wie aus den Rohdaten Voxel-Chunks werden (Konzept, Abschnitt 2), mit den Formaten, die dabei entstehen.

```
data/raw/dgm1/*.tif  ─┐
data/raw/lod2/*.gml  ─┼─ raser import ──► world/tiles/<x>_<y>.json + .rrh ── raser voxelize ──► world/chunks/<x>_<y>/*.rrc + manifest.json
data/raw/osm/*.osm   ─┘                    (Zwischenlayer)               ▲                       (Voxel-Chunks)
                                                                    overrides/*.json
```

## Die Solution

| Projekt | Art | Inhalt |
|---|---|---|
| `src/Raser.Core` | Bibliothek (`raser.core`) | Raster und Schlüssel (`Grid`, `TileKey`, `ChunkKey`), Voxel (`Material`, `Materials`, `Palette`, `Shape`), `Chunk` mit Kodierung, globale IDs, `ByteWriter`/`ByteReader`, FNV-1a, Sortieren |
| `src/Raser.World` | Bibliothek (`raser.world`) | Zwischenlayer (`Tile`, `TileData`, `Building`, `Road`, `Area`, `Poi`, `HeightRaster`), Geometrie, Override-Layer, `Voxelizer`, `FileTileStore`, `TileGenerator` |
| `src/Raser.Import` | Bibliothek (`raser.import`) | XML-Pull-Parser, GeoTIFF (LZW, Float32), WGS84 → UTM 32, CityGML LoD2, OSM-XML, `Region` (schneidet alles in Kacheln) |
| `src/Raser.Tool` | Programm | `raser import`, `voxelize`, `export png`, `export obj`, `info` |

Jede Bibliothek hat ihre Tests in `testing/` (`forge test src/Raser.World/Raser.World.fireproj`, oder alle: `forge test RuhrpottRaser.firesln`).

## Ablauf

```bash
tools/fetch-bochum.sh                 # Rohdaten der Testregion (rund 230 MB)
FORGE=/pfad/zu/forge tools/build-bochum.sh
```

Das Werkzeug läuft in der VM (`forge run RuhrpottRaser.firesln -- info`), für echte Daten aber nativ: `forge build RuhrpottRaser.firesln --engine native -m RELEASE`
baut `src/Raser.Tool/bin/linux-rel/Raser.Tool`. Gemessen an der Testregion (Bochum-Innenstadt, 2 × 2 km, 49 vollständige Kacheln):

| Schritt | Dauer (nativ) |
|---|---|
| Import (4 DGM1-Kacheln, 4 LoD2-Kacheln mit rund 10.000 Gebäuden und Gebäudeteilen, 16 OSM-Ausschnitte) | rund 40 s |
| Voxelisierung je Kachel (rund 1.200 Chunks, 155 Mio. Voxel) | rund 47 s |
| Draufsicht je Kachel | rund 24 s |

Die Zeit der Voxelisierung geht fast ganz in die Elementzugriffe auf Byte-Puffer (docs/FIRE.md).

## Koordinaten

- Welt: ETRS89 / UTM 32N (EPSG:25832), x Ost, y Nord, z Höhe über NHN, Meter.
- Voxel: 20 cm, `floor(meter * 5)`. Chunk: 64³ Voxel = 12,8 m. Kachel: 256 × 256 m = 20 × 20 Chunk-Säulen, ohne Höhe.
- Im Zwischenlayer sind Lagen kachel-lokal (Südwest-Ecke = 0, 0), Höhen absolut.

## Zwischenlayer: `world/tiles/<x>_<y>.json` und `.rrh`

`TileData` als JSON (ohne `$type`): `quarter`, `mood`, `sources`, `buildings`, `roads`, `areas`, `pois`. Jedes Merkmal hat `id` (stabil, `Raser.Ids.Stable`) und `source`.
Merkmale, die über den Rand reichen, stehen in jeder Kachel, die ihr Rechteck berührt.

- Gebäude: aus jedem `bldg:Building`/`bldg:BuildingPart` mit eigener Geometrie, je Grundfläche eines. `footprint` (Ring), `ground` (tiefster Punkt der Grundfläche),
  `eaves`/`ridge` (tiefster/höchster Dachpunkt), `roofs` (die LoD2-Dachflächen), `roofType` (ALKIS-Dachform), `function` (`alkis=<code>`, oder ein OSM-POI im Grundriss: `amenity=fuel` ...), `name`.
- Straßen: OSM `highway=*` (ohne Tunnel, ohne `proposed`/`construction`), Bahnen (`railway=rail|light_rail|subway|tram`, ohne eingebettete Straßenbahn); Breite aus `width` oder nach Art.
- Flächen: Wasser, Parkplätze, Plätze, Sport- und Spielplätze, Wald, Grün, Felder, Bahngelände, Gewerbe/Handel - mit Priorität bei Überlappung.
- `.rrh`: das Höhenraster, 258 × 258 Höhen im Abstand von 1 m auf den Pixelmitten des DGM1 (-0,5 .. 256,5 m), in Zentimetern als Differenzen (Varints).

## Voxel-Chunks: `world/chunks/<x>_<y>/<cx>_<cy>_<cz>.rrc`

Deflate über `Chunk.Encode()`: `RRC1`, Schlüssel, Generator-Version, Hash der Overrides, Seed, dann Material + Farbe als Lauflängen (Varint-Länge, Byte, Byte),
dann die Formen (Höhen-Schnitte) und der Teilschaden als (Abstand zum vorigen Index, Byte). Leere Chunks (nur Luft) werden nicht gespeichert.

`manifest.json` hält fest, womit die Kachel erzeugt wurde: `generatorVersion`, `overridesHash`, `seed`, `dataHash` (alle Hashes als 16 Hex-Ziffern), die Chunks und die Zahl der Voxel.
`raser voxelize` überspringt Kacheln, bei denen alles passt; `--force` erzeugt neu.

## Voxelisierung

Je Chunk-Säule wird einmal ein Plan der 64 × 64 Voxel-Säulen gerechnet (gilt für alle Chunks übereinander):

- Gelände: Eckhöhen aus dem Raster an den Säulen-Ecken; die Oberfläche liegt im Voxel der höchsten Ecke, die vier Ecken auf 5 cm gerundet (Viertel). Darunter 2 Voxel
  Unterbau (Erde, unter Straßen Schotter, unter Wasser Sand), bis 2 m Erde, darunter Fels.
- Flächen und Grundrisse werden zeilenweise gerastert, Straßen segmentweise; die breiteste Straße und die Fläche mit der höchsten Priorität gewinnen.
- Gebäude: Säulen, deren Mitte im Grundriss liegt; Rand = Wand mit Fensterreihen (Glas) je Geschoss (2,8 m), innen Decken; das Dach-Voxel mit Eckhöhen aus den LoD2-Ebenen
  (sonst aus Dachform, Traufe und First). Wohnhäuser (ALKIS 31001_1xxx) in Ziegel, der Rest verputzt; Farbvarianten aus ID und Seed.
- Alle Lagen werden aus dem kachel-lokalen Voxel-Index gerechnet, damit Nachbar-Chunks dieselbe Säule gleich sehen. Zwei Läufe mit denselben Daten ergeben dieselben Bytes.

## Export zur Kontrolle

- `raser export png [--tile x_y] [--step n]`: Draufsicht, die Farbe des obersten Voxels je Säule mit Hangschattierung; ohne `--tile` alle Kacheln in einem Bild.
- `raser export obj --at ost,nord [--size m]`: ein Ausschnitt als OBJ + MTL (sichtbare Flächen, Höhen-Schnitte als schräge Oberseiten), für Blender oder jeden anderen Betrachter.

## Offen (für M1 und danach)

- PostGIS: Schema steht in `db/schema.sql`; der Store kommt, wenn fire einen PostgreSQL-Treiber hat (die Datenschicht `data` in fire hat SQLite, MySQL, SQL Server).
- Brücken und Tunnel (`layer`), Gebäudeteile über Durchfahrten, Fassaden-Grammatik (M2), Viertel-Typen aus den Daten.
- Kacheln am Rand der Region kommen erst mit den Daten der Nachbarregion.
