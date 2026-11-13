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
- [ ] Spieler zu Fuß (Laufen, Sprinten, Ein-/Aussteigen)
- [ ] Fahrzeugphysik inkl. Nässe, Aquaplaning, Glätte
- [ ] Fahrzeugklassen: Fahrrad, Motorrad, Auto, Nutzfahrzeug; Tank/Akku, Zustand
- [ ] Streaming mehrerer Kacheln, Vorausgenerierung in Fahrtrichtung
- [ ] LOD für weite Sichtweiten

## M4: Multiplayer-Grundgerüst
- [ ] Koordinator + ein Regionsserver auf einem Rechner, Protokoll schon für mehrere Regionen ausgelegt
- [ ] Globale, eindeutige Objekt-IDs; globale Dienste (Konten, Inventar, Wirtschaft) getrennt von Regionen
- [ ] Autoritativer Regionsserver, 2–8 Spieler
- [ ] Client-Prediction für Fahrzeuge
- [ ] Interest-Management pro Kachel
- [ ] Serverseitiges Wetter (simuliert per Seed, optional echtes DWD-Wetter)
- [ ] Zerstörungs-/Bau-Deltas (Key-Value-Store), Zerstörung als eigener Delta-Typ mit Ursache
- [ ] Physik-Ereignisse (Aufprall, Explosion) liefern Energie und Trefferpunkt
- [ ] Zwei Regionsserver mit Randzone und Übergabe (Fahrzeug fährt über die Grenze)

## M5: Gameplay
- [ ] Spielerwerte: Vitalwerte, Fähigkeiten, Ruf
- [ ] Krankenhaus statt Tod: Aufwachen im nächsten Krankenhaus, Behandlungskosten
- [ ] Offline: Vitalwerte einfrieren, Charakter verlässt die Welt, Wartezeit gegen Kampf-Ausloggen
- [ ] Gebäudetypen aus OSM-Tags, zuerst: Tankstelle, Imbiss, Kneipe, Autohändler, Hotel
- [ ] Waffen und PvP, Fahndungslevel, Schutzbereiche, Schonfrist für Neue
- [ ] Rennen: legal auf abgesperrten Strecken und illegal im Verkehr, Wetten
- [ ] Jobs als Schicht-Missionen in Gebäuden, Aufstieg bis zur Übernahme
- [ ] Gebäude mieten, prozedurale Innenräume
- [ ] Baumodus (Grundumfang): Setzen/Entfernen, Form, Material, Pinsel, Objekte, Rückgängig
- [ ] Materialien: Beton, Holz, Glas, Metall (+ Ziegel/Putz); Material-ID + Farbindex pro Voxel
- [ ] Material-Tabelle mit physikalischen Werten (Schwelle, Zähigkeit, Dichte), zunächst ungenutzt
- [ ] Baumaterial und Farben als Inventar, Kauf im Baumarkt; öffentliches Lager für Bauamt/Bauhof
- [ ] Gebäude materialisieren beim ersten Umbau, Deltas, Konfliktmarkierung bei Generator-Updates
- [ ] Rechte: Eigentümer, Mieter, Bauamt
- [ ] Super-, Bau- und Elektronikmarkt mit platzierbaren Objekten
- [ ] Ein Geschäftstyp mit Wirtschaftssimulation
- [ ] Missionsgenerator mit echten POIs
- [ ] Erste handgebaute Story-Mission
- [ ] Wetter-Einfluss auf Entdeckung, Kundschaft und Missionen

## M6: Skalierung
- [ ] Dynamische Aufteilung der Karte nach Spielerdichte (Quadtree), Aufteilen/Zusammenlegen im Betrieb
- [ ] Ganzes Ruhrgebiet
- [ ] Ganz NRW
- [ ] Fassaden-Tool (Foto → Grammatik-Parameter) für größere Gebiete
- [ ] Weitere Gebäudetypen (Disco, Casino, Spielothek, Internetcafé …)
- [ ] Öffentliche Verwaltung: Genehmigungen, Ordnungsamt, Bauamt (öffentlicher Grund, Spielerbesitz mit Freigabe)
- [ ] Bauhöfe: Reparatur von Zerstörung, Baustellen, Winterdienst, Korrekturvorschläge für den Override-Layer
- [ ] Öffentlicher Verkehr als Schnellreise (S-Bahn, RE, Flüge)
- [ ] Spezial-Generatoren für Problemfälle (Autobahnkreuze, Brücken, Fördertürme)
- [ ] Zerstörbarkeit: Schwellen je Material, Energie-Verteilung, Materialisieren bei Zerstörung
- [ ] Später: Statik, Trümmer, Brand
- [ ] Meldefunktion „sieht falsch aus“ als Arbeitsliste für Nachbesserungen

## Offene Fragen
- Wie redet fire mit der GPU (eigene Bindings, FFI zu Vulkan/WebGPU …)?
- Läuft der Client nativ oder im Browser?
- Wie viele Spieler soll ein Regionsserver tragen, und was ist das Ziel für ganz NRW?
- Konkrete Schwellenwerte je Material (Balancing gegen Griefing)
- Grundstücksgrenzen: ALKIS-Daten verfügbar oder Ableitung aus Grundrissen?
- Zeitfaktor der Ingame-Uhr (Echtzeit oder beschleunigt wie in GTA)? Beeinflusst auch die Mondphase
- Was läuft für Geschäfte und Mieten offline weiter?
- Altersfreigabe (USK/PEGI) prüfen; Glücksspiel bleibt rein virtuell ohne Echtgeld
- Lizenzen der Datenquellen final prüfen (NRW Open Data, OSM/ODbL, Mapillary/Panoramax)
