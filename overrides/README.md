# Override-Layer

Handgepflegte Korrekturen zwischen Zwischenlayer und Voxelisierung (Konzept, Abschnitt 9). Jede `*.json` in diesem Ordner (auch in Unterordnern) wird gelesen, sortiert nach Namen.
Eine Kachel trägt den Hash der Overrides, die sie betreffen; ändert sich einer, erzeugt `raser voxelize` nur diese Kacheln neu.

```json
{ "overrides": [
    { "target": "lod2:DENW39AL10003xyz", "set": { "eaves": 7.5, "roofType": "Flat" }, "note": "Traufe nach Foto" },
    { "target": "osm:way/4711", "set": { "width": 9.0 } },
    { "target": "osm:way/4712", "remove": true },
    { "tile": "1469_22284", "set": { "quarter": "innenstadt", "mood": "neon" } }
] }
```

- `target`: die Quelle eines Gebäudes (`lod2:<gml:id>`), einer Straße oder Fläche (`osm:way/<id>`, `osm:relation/<id>#<n>`) - so wie sie in den Kachel-JSONs unter `source` steht.
- `tile`: eine Kachel (`x_y`).
- `set`: die Felder, die sich ändern. Gebäude: `ground`, `eaves`, `ridge`, `height`, `roofType` (`Flat`, `Gable`, `Hip`, `Shed`, `Pyramid`, `Mansard`; verwirft die LoD2-Dachflächen),
  `levels`, `function`, `name`, `wall`, `wallColor`, `roof`, `roofColor` (Materialien mit Namen, z. B. `"Plaster"`). Straßen: `width`, `kind`, `lanes`, `layer`, `surface`, `color`.
  Flächen: `kind`, `surface`, `color`, `priority`. Kacheln: `quarter`, `mood`. Ein anderes Feld ist ein Fehler mit Datei und Ziel.
- `remove`: das Merkmal fällt weg.
- `generator`: reserviert für Spezial-Generatoren (Autobahnkreuz, Brücke, Förderturm); geht in den Hash ein, wird aber noch nicht ausgewertet.
- `note`: frei, für Menschen.
