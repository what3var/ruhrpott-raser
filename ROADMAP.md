# Roadmap: Ruhrpott-Raser

Details zur Architektur stehen im [Konzept](docs/KONZEPT.md).

## M1: Pipeline-Prototyp
Eine Kachelregion (z. B. Bochum-Innenstadt, 2 × 2 km) wird von den Rohdaten über den Zwischenlayer zu Voxel-Chunks verarbeitet. Stand und Formate: [Weltpipeline](docs/PIPELINE.md).
- [x] Import: DGM1, LoD2, OSM für die Testregion (DGM1 als GeoTIFF, LoD2 als CityGML, OSM als XML; `tools/fetch-bochum.sh`)
- [x] Schema des Zwischenlayers in PostGIS (`db/schema.sql`, `Raser.Store` mit `data.postgres`: Merkmale global, eine Kachel ist eine räumliche Abfrage; `--db postgres://...`; Dateien bleiben als Alternative)
- [x] Deterministische Voxelisierung (Gelände, Gebäude, Straßen)
- [x] Voxel mit diagonalen Höhen-Schnitten (vier Eckhöhen, geteilt mit Nachbarn)
- [x] Override-Layer + Generator-Versionierung pro Kachel (von Anfang an, nicht nachrüsten)
- [x] Export/Viewer zur Kontrolle (noch ohne eigenen Renderer): Draufsicht als PNG, Ausschnitte als OBJ
- [ ] Gegencheck mit Luftbildern (NRW DOP, Orthofotos): Untergründe genauer bestimmen (Rasen, Pflaster, Asphalt, Schotter, Wasser - wo OSM nichts oder zu grob sagt) und fehlende Gebäude finden (im Bild ein Dach, in LoD2 nichts: z. B. Neubauten) - daraus Vorschläge als Patches im Override-Layer, nicht direkt in den Rohdaten; mit nDOM/DGM-Differenz für die Höhe
- [ ] Parkhäuser erkennen und einbauen (OSM `amenity=parking` + `parking=multi-storey`, LoD2-Funktion, spätestens über den Luftbild-Abgleich): offene Geschosse mit Stützen, Rampen, Brüstungen, Einfahrt - befahrbar

## M2: Renderer
- [x] Chunk-Meshing inkl. Höhen-Schnitten (`Raser.Mesh`: Greedy Meshing, schräge Oberseiten, Trapez-Seiten, Glas/Wasser getrennt)
- [ ] Fahrbare Kamera durch die Testregion (`Raser.Viewer` mit scene3d: fliegende Kamera, Nachladen und Entladen von Chunk-Säulen um den Blickpunkt, `--shot`, `--fly` mit Zeiten; nahe Blöcke in Worker-Threads, ferne Stufe im Hauptprogramm; 83 m/s mit der fernen Stufe; Vorrat nach freiem Speicher, Vorausladen im Stillstand; nahe Stufe schneller vernetzt (2,3 -> unter 1 s je Block) und im Netz-Cache (38 ms je Block, `raser meshes`); offen: mittlere Stufe, naher Radius nach Tempo)
- [ ] Detailstufen nach Entfernung: Voxel nah (Stufe 0), gröbere Voxel (Stufen 1-2), fern direkt aus dem Zwischenlayer (Höhenraster-Netz, Gebäude aus Grundriss und Dachflächen) - Stufe 0 und fern gebaut (`Raser.FarMesher`), mittlere Stufen offen
- [ ] Laden entlang der Route: Kegel in Fahrtrichtung, Nähe-Radius nach Tempo, grob vor fein, Korridor vorab bei bekanntem Ziel; Ziel: Autobahn mit 250-300 km/h - grob vor fein und Ladepunkt voraus gebaut; 83 m/s halten die fernen Stufen (Messflug); offen: Nähe-Radius nach Tempo, Korridor vorab
- [x] Untergrund glatt: das Gelände ist in jeder Stufe ein Netz aus dem Höhenraster (mit Diagonalen), Voxel nur für das, was darauf steht; hart (Voxel) nur, wo etwas hineingreift
- [x] Keller: `cellars` je Gebäude (Zwischenlayer, Override, PostGIS); das Gelände ist dort ausgehoben, die Außenwand läuft hinunter
- [ ] Keller aus OSM (`building:levels:underground`), Graben und Absenken im Baumodus
- [ ] Gemeinsame Vorlagen für wiederkehrende Gebäude (gleicher Grundriss und gleiche Dachform nach Drehung/Verschiebung): eine Außenhülle für alle, nur Abweichungen einzeln
- [x] Vegetation und Stadtmöbel als grobe 3D-Pixelgrafik (Voxel-Modelle wie in Minecraft gebaut): Bäume prozedural in Varianten, Bänke, Laternen, Papierkörbe, Schilder, Ampeln; Standorte aus OSM, Wälder und Parks deterministisch bestreut; Modelle geteilt (`Raser.Props`, `Prop` im Zwischenlayer und in PostGIS)
- [ ] Mehr Arten: Hecken, Büsche, Sträucher, Baumreihen (`natural=tree_row`), Litfaßsäulen, Haltestellen (`highway=bus_stop`), Poller, Fahrradständer; Laternen entlang der Straßen ergänzen, wo OSM keine hat
- [ ] Straßenraum wie in Deutschland: Bordsteinkanten mit Höhenunterschied (Gehweg über der Fahrbahn, abgesenkt an Einfahrten und Übergängen), Laternen entlang der Straßen, Straßenschilder (Verkehrszeichen aus OSM `traffic_sign` und an Kreuzungen, Straßennamensschilder, Ortstafeln)
- [ ] Natürliche Straßenkanten: Ränder von Fahrbahn und Gehweg als geglättete Kurven (Radien an Einmündungen) im glatten Untergrund, Bordstein als Profil entlang der Kurve (Konzept, Abschnitt 1)
- [ ] Gerade Fronten in jedem Winkel: senkrechter Schnitt im Grundriss je Voxel (zwei Randpunkte in Vierteln, mit den Nachbarn geteilt), Fassaden schräg zum Gitter glatt, Fenster entlang der Wand; Grundstücke zur Straße ausrichten (gemeinsame Fluchtlinie), an der Grundstücksgrenze schräg abschneiden
- [ ] Später: Grünstreifen an der Straße und Mittelstreifen (mit Bäumen), Verkehrsberuhigung in 30er-Zonen - Einengungen und Verschwenkungen, Drempel und Aufpflasterungen (OSM `traffic_calming=bump/hump/table/choker/chicane`, `zone:maxspeed=DE:30`)
- [ ] Gehwege nach Bauzeit erkennen und bauen (aus OSM `sidewalk`/`surface`, Straßentyp, Baujahr des Viertels, später Luftbild): alt geteert nur mit Bordstein und Höhenunterschied; grobes Pflaster der 80er/90er; heute schmale Pflastersteine, bei genug Breite mit rotem Radweg (`cycleway=track`)
- [ ] Fassaden-Grammatik + parametrische Materialien
- [ ] Fenster ab Stufe 1 als Fassaden-Textur (gleiches Raster wie die Voxel-Fenster, 1 Texel je Voxel); nachts einzelne Fenster als Lichtquellen
- [ ] Ausstattung der Gebäude, zufällig aber stabil (aus ID und Seed): vorgerenderte Innenansichten hinter den Fenstern für das schnelle Vorbeifahren, detaillierte Ausstattung in der Nähe und beim Betreten
- [ ] Sharp-bilinear-Shader
- [ ] Tag/Nacht, viele Lichtquellen, warme Straßenbeleuchtung als Basis
- [ ] Wetterzustand als gemeinsamer Eingang für Renderer, Physik und Gameplay
- [ ] Wetterlagen: klar, Nebel, Regen (nasse Straßen, Spiegelungen), später Gewitter, Schnee, Wind
- [ ] Ingame-Uhr in Echtzeit (deutsche Ortszeit, echter Sonnenstand), Zeitfaktor als Server-Einstellung
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
- [ ] Wirtschaft pro aktivem Tag: Login aktiviert den Tag, Nachbuchung beim Einloggen, wenige immer laufende Posten
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
- Grundstücksgrenzen: ALKIS-Daten verfügbar oder Ableitung aus Grundrissen? (gebraucht auch zum Ausrichten der Fronten zur Straße)
- Gerade Fronten: reichen Schnitte im Grundriss im Weltgitter, oder braucht es gedrehte Gitter je Grundstück? (Konzept, Abschnitt 1)
- Altersfreigabe (USK/PEGI) prüfen; Glücksspiel bleibt rein virtuell ohne Echtgeld
- Lizenzen der Datenquellen final prüfen (NRW Open Data, OSM/ODbL, Mapillary/Panoramax)
