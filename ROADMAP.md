# Roadmap: Ruhrpott-Raser

Details zur Architektur stehen im [Konzept](docs/KONZEPT.md).

## M1: Pipeline-Prototyp
Eine Kachelregion (z. B. Bochum-Innenstadt, 2 × 2 km) wird von den Rohdaten über den Zwischenlayer zu Voxel-Chunks verarbeitet.
- [ ] Import: DGM1, LoD2, OSM für die Testregion
- [ ] Schema des Zwischenlayers in PostGIS
- [ ] Deterministische Voxelisierung (Gelände, Gebäude, Straßen)
- [ ] Voxel mit diagonalen Höhen-Schnitten (vier Eckhöhen, geteilt mit Nachbarn)
- [ ] Override-Layer + Generator-Versionierung pro Kachel (von Anfang an, nicht nachrüsten)
- [ ] Export/Viewer zur Kontrolle (noch ohne eigenen Renderer)

## M2: Renderer
- [ ] Chunk-Meshing inkl. Höhen-Schnitten
- [ ] Fahrbare Kamera durch die Testregion
- [ ] Fassaden-Grammatik + parametrische Materialien
- [ ] Sharp-bilinear-Shader
- [ ] Tag/Nacht, viele Lichtquellen, warme Straßenbeleuchtung als Basis
- [ ] Wetterzustand als gemeinsamer Eingang für Renderer, Physik und Gameplay
- [ ] Wetterlagen: klar, Nebel, Regen (nasse Straßen, Spiegelungen), später Gewitter, Schnee, Wind
- [ ] Mondphase/-stand astronomisch korrekt, Wolken mit orangem Stadtlicht-Himmel
- [ ] Volumetrischer Nebel mit Lichtkegeln/Halos
- [ ] Referenzszene: Zechensiedlung in nebliger Nacht
- [ ] Mood-Akzente pro Viertel, Render-Profile pro Gebiet
- [ ] Debug-Ansicht: aktive Generatoren, Overrides, Render-Profil

## M3: Fahren & Streaming
- [ ] Kollisionsmesh aus den geschnittenen Voxeln, Override-Mesh wo nötig
- [ ] Fahrzeugphysik inkl. Nässe, Aquaplaning, Glätte
- [ ] Streaming mehrerer Kacheln, Vorausgenerierung in Fahrtrichtung
- [ ] LOD für weite Sichtweiten

## M4: Multiplayer-Grundgerüst
- [ ] Autoritativer Server, 2–8 Spieler
- [ ] Client-Prediction für Fahrzeuge
- [ ] Interest-Management pro Kachel
- [ ] Serverseitiges Wetter (simuliert per Seed, optional echtes DWD-Wetter)
- [ ] Zerstörungs-/Bau-Deltas (Key-Value-Store)

## M5: Gameplay
- [ ] Gebäude mieten, prozedurale Innenräume
- [ ] Ein Geschäftstyp mit Wirtschaftssimulation
- [ ] Missionsgenerator mit echten POIs
- [ ] Erste handgebaute Story-Mission
- [ ] Wetter-Einfluss auf Entdeckung, Kundschaft und Missionen

## M6: Skalierung
- [ ] Ganzes Ruhrgebiet
- [ ] Ganz NRW
- [ ] Fassaden-Tool (Foto → Grammatik-Parameter) für größere Gebiete
- [ ] Spezial-Generatoren für Problemfälle (Autobahnkreuze, Brücken, Fördertürme)
- [ ] Meldefunktion „sieht falsch aus“ als Arbeitsliste für Nachbesserungen

## Offene Fragen
- Wie redet fire mit der GPU (eigene Bindings, FFI zu Vulkan/WebGPU …)?
- Läuft der Client nativ oder im Browser?
- Wie viele Spieler soll ein Server tragen?
- Wie stark ist die Welt zerstörbar bzw. bebaubar?
- Wie laufen Ingame-Zeit und Wirtschaft weiter, wenn Spieler offline sind?
- Lizenzen der Datenquellen final prüfen (NRW Open Data, OSM/ODbL, Mapillary/Panoramax)
