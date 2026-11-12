# Roadmap: Ruhrpott-Raser

Details zur Architektur stehen im [Konzept](docs/KONZEPT.md).

## M1: Pipeline-Prototyp
Eine Kachelregion (z. B. Bochum-Innenstadt, 2 × 2 km) wird von den Rohdaten über den Zwischenlayer zu Voxel-Chunks verarbeitet.
- [ ] Import: DGM1, LoD2, OSM für die Testregion
- [ ] Schema des Zwischenlayers in PostGIS
- [ ] Deterministische Voxelisierung (Gelände, Gebäude, Straßen)
- [ ] Export/Viewer zur Kontrolle (noch ohne eigenen Renderer)

## M2: Renderer
- [ ] Chunk-Meshing inkl. Schrägen/Sonderformen
- [ ] Fahrbare Kamera durch die Testregion
- [ ] Fassaden-Grammatik + parametrische Materialien
- [ ] Sharp-bilinear-Shader
- [ ] Tag/Nacht, viele Lichtquellen, Mood pro Viertel

## M3: Fahren & Streaming
- [ ] Glattes Kollisionsmesh aus dem Zwischenlayer
- [ ] Fahrzeugphysik
- [ ] Streaming mehrerer Kacheln, Vorausgenerierung in Fahrtrichtung
- [ ] LOD für weite Sichtweiten

## M4: Multiplayer-Grundgerüst
- [ ] Autoritativer Server, 2–8 Spieler
- [ ] Client-Prediction für Fahrzeuge
- [ ] Interest-Management pro Kachel
- [ ] Zerstörungs-/Bau-Deltas (Key-Value-Store)

## M5: Gameplay
- [ ] Gebäude mieten, prozedurale Innenräume
- [ ] Ein Geschäftstyp mit Wirtschaftssimulation
- [ ] Missionsgenerator mit echten POIs
- [ ] Erste handgebaute Story-Mission

## M6: Skalierung
- [ ] Ganzes Ruhrgebiet
- [ ] Ganz NRW
- [ ] Fassaden-Tool (Foto → Grammatik-Parameter) für größere Gebiete

## Offene Fragen
- Wie redet fire mit der GPU (eigene Bindings, FFI zu Vulkan/WebGPU …)?
- Läuft der Client nativ oder im Browser?
- Wie viele Spieler soll ein Server tragen?
- Wie stark ist die Welt zerstörbar bzw. bebaubar?
- Wie laufen Ingame-Zeit und Wirtschaft weiter, wenn Spieler offline sind?
- Lizenzen der Datenquellen final prüfen (NRW Open Data, OSM/ODbL, Mapillary/Panoramax)
