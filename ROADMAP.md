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
- [x] Fahrbare Kamera (Viewer): Fahrmodus mit Gas, Bremse, Lenkung, 1,4 m über dem Gelände (F: freier Flug); geladen wird voraus (Tempo x 2,5 s), ab 126 km/h ohne die nahe Voxel-Stufe, je Bild höchstens ein naher Block; `--gpu 1` zeichnet mit der Grafikkarte (scene3d Hardware)
- [ ] Bildrate: der Software-Renderer schafft auf 4 Kernen bei 640x400 in der Stadt mit naher Stufe 2,7 Bilder/s (Rendern 270 ms bei 4 Mio. Dreiecken), auf der Autobahn (83 m/s, nur ferne Stufe) 12 Bilder/s (Rendern 59 ms, Nachladen 25 ms) - flüssig geht nur mit der Grafikkarte; dort fehlen noch Nebel, Lichtkacheln und Spiegelungen (fire). Auf echter Hardware messen
- [x] Kollision im Fahrmodus: Gebäude halten auf (0,6 m Abstand), an der Wand entlang gleiten; Überdachungen und Durchfahrten bleiben frei
- [ ] Laden entlang der Route: Kegel in Fahrtrichtung, Korridor vorab bei bekanntem Ziel; Kollision mit Bäumen, Laternen und Bordsteinen; Fahrzeugmodell
- [x] Untergrund glatt: das Gelände ist in jeder Stufe ein Netz aus dem Höhenraster (mit Diagonalen), Voxel nur für das, was darauf steht; hart (Voxel) nur, wo etwas hineingreift
- [x] Keller: `cellars` je Gebäude (Zwischenlayer, Override, PostGIS); das Gelände ist dort ausgehoben, die Außenwand läuft hinunter
- [ ] Keller aus OSM (`building:levels:underground`), Graben und Absenken im Baumodus
- [ ] Gemeinsame Vorlagen für wiederkehrende Gebäude (gleicher Grundriss und gleiche Dachform nach Drehung/Verschiebung): eine Außenhülle für alle, nur Abweichungen einzeln
- [x] Vegetation und Stadtmöbel als grobe 3D-Pixelgrafik (Voxel-Modelle wie in Minecraft gebaut): Bäume prozedural in Varianten, Bänke, Laternen, Papierkörbe, Schilder, Ampeln; Standorte aus OSM, Wälder und Parks deterministisch bestreut; Modelle geteilt (`Raser.Props`, `Prop` im Zwischenlayer und in PostGIS)
- [ ] Mehr Arten: Hecken, Büsche, Sträucher, Baumreihen (`natural=tree_row`), Litfaßsäulen, Haltestellen (`highway=bus_stop`), Poller, Fahrradständer; Laternen entlang der Straßen ergänzen, wo OSM keine hat
- [ ] Straßenraum wie in Deutschland: Bordsteinkanten mit Höhenunterschied (Gehweg über der Fahrbahn, abgesenkt an Einfahrten und Übergängen), Laternen entlang der Straßen, Straßenschilder (Verkehrszeichen aus OSM `traffic_sign` und an Kreuzungen, Straßennamensschilder, Ortstafeln)
- [ ] Natürliche Straßenkanten: Ränder von Fahrbahn und Gehweg als geglättete Kurven (Radien an Einmündungen) im glatten Untergrund, Bordstein als Profil entlang der Kurve (Konzept, Abschnitt 1)
- [ ] Bauelemente (Konzept, Abschnitt 1): Grundriss-Formen aus einem Katalog - Diagonalen 1×1 bis 6×1 (Datenformat, Mesher, Voxelizer passt die Gebäudekanten an), dann Rundungen (Eckkneipen), Torbögen, Türen zwischen zwei Wänden; dieselben Elemente als Fertigteile im Baumarkt; 3D-Dachziegel als Pixel-Relief
  - [x] Stufe 1: Diagonalen 1×1 bis 6×1 (Datenformat RRC2, Mesher, Voxelizer nach Bresenham je Voxelreihe; bis zur Geländeoberfläche ein voller Sockel) - `docs/images/viewer-diagonale-wand.png`
  - [x] Sockel ohne Stufen: unter Bauelementen mit den Eckhöhen des Geländes, bündig mit dem Boden; die Wand hinter einem Element eine Säule dicker
  - [x] Rundungen: Viertelkreise mit Radius 1..32 Voxel (bis 6,4 m) um eine Rasterecke, gefüllt innen (runde Ecke, Turm) oder außen (Innenecke); der Voxelizer erkennt Ketten kurzer, gleichmäßig drehender Kanten und legt einen Kreis hinein (Kasa) - `docs/images/viewer-rundung.png`; Chunk-Format RRC3 (Formen als Varint)
  - [x] Schnitte mit Versatz für Grundrisse aus den Daten (Generator 13): je Randvoxel eine Kante zwischen zwei Punkten auf seinem Rand (1/32 Voxel, 6 mm), Ecken mit einem Punkt im Voxel; Nachbarn teilen sich die Punkte - keine Stufen in jedem Winkel, Rundungen als Sehnen. Gemessen an gedrehten Rechtecken (2°..87°) und einem Kreis: mittlerer Fehler je Randvoxel 0,005..0,01 Voxel, keine Stufe über einem halben Voxel (vorher mit Diagonalen 0,06..0,34 und bis zu 52 Stufen). Diagonalen und Rundungen bleiben als Fertigteile für den Baumodus
  - [x] Grundrisse bereinigen (Raser.Footprints, beim Laden jeder Kachel - Werkzeug und Viewer gleich): Ecken rasten unter 15 cm ein, auch zwischen Gebäuden; Ecken knapp neben der Wand eines Nachbarn rücken auf sie (keine Schlitze zwischen Reihenhäusern); Knicke unter 5 cm fallen weg
  - [ ] Dieselben Regeln im Baumodus, in Client und Server: beim Umbauen rasten neue Ecken an Nachbarn und bestehende Kanten ein (eine gemeinsame Funktion in Raser.World), damit auch Umgebautes stimmig bleibt
  - [x] Bodennetz bis an die Wand: hart bleibt nur die Säule (20 cm), in der etwas steht; in den ausgesparten 80-cm-Zellen läuft das glatte Netz mit Gehweg und Bordstein Säule für Säule bis an den Grundriss (FarMesher.Fringe) - keine Treppe mehr am Wandfuß
  - [x] Dachüberstand bei Steildächern (40 cm an Traufe und Ortgang): eine Platte unter der fortgesetzten Dachfläche, Außenkante mit Schnitten, darunter die Untersicht - `docs/images/viewer-dachueberstand.png`
  - [ ] Dachüberstand auch in der fernen Stufe; Dachrinne und Fallrohr; Überstand je Baujahr/Stil (Altbau knapp, Siedlungshaus breit)
  - [x] Schnitte in der Ansicht (Raser.Plan.Elevation): dieselben Schnitte wie im Grundriss, aber senkrecht und entlang einer Achse durchgezogen - für Bögen
  - [x] Durchfahrten: Wege und Straßen, die ein Gebäude ganz durchqueren (mindestens 2,5 m darin), bekommen einen Durchgang mit Torbogen (Fußweg 3 m, sonst 4 m hoch, Stich bis 1,5 m), Pflaster am Boden, Decke darüber, fensterlose Seitenwände - `docs/images/viewer-durchfahrt.png`
  - [x] Haustüren mit Rundbogen (Stich 35 cm) und Oberlicht aus Glas; Wände zwei Voxel dick mit Laibung
  - [x] Dachziegel in Pixel-Art mit Relief (Bumpmap des Atlas: Ziegelreihen, Mauer- und Pflasterfugen) - `docs/images/viewer-dachziegel.png`
  - [ ] Türen und Torbögen als Fertigteile im Baumodus, Klinken; Traufzähne
  - [x] Bögen als eingehängte Stücke (Generator 29): die Wand lässt ein Rechteck bis zum Scheitel frei, ein Bogenstück in Wandfarbe füllt die Zwickel (Raser.Facade.Arches, FarMesher.Spandrel) - Haustüren, Kirchenfenster, Portale; Durchfahrten bekommen ein Gewölbe mit glatten Seitenwänden durch das ganze Haus. Glatt in jeder Wandrichtung - `docs/images/viewer-durchfahrt.png`
  - [ ] Bogenstücke auch in der fernen Stufe; als Fertigteil im Baumodus
- [x] Baumscheiben: einzelne Bäume (Plätze, Fußgängerzonen) in einem Quadrat aus Gras (1,4 m), an der nächsten Straße ausgerichtet, mit schmalen Kantensteinen (6 cm); zu nahe Bäume rücken beim Laden von der Fahrbahn weg (Raser.Props.Settle)
- [x] Grünstreifen (Raser.Strips): Baumreihen an Straßen werden Beete zwischen Fahrbahn und Gehweg - zur Straße direkt am Bordstein, sonst schmale Kantensteine, Erde mit niedrigen Sträuchern (Voxel, zum Teil mit Blüten); der Gehweg liegt dahinter - `docs/images/viewer-gruenstreifen.png`
- [x] Bordstein oben als Band von 12 cm; Pflasterrinne (30 cm) vor dem Bordstein bei etwa 4 von 10 Wohn- und Nebenstraßen; eckige Gullis etwa alle 30 m je Seite (in der Rinne, sonst im Asphalt am Bordstein)
- [ ] Grünstreifen ohne Bäume (Luftbild-Abgleich), Laternen und Schilder im Streifen, Sträucher aus Grünstreifen der Nachbarkachel; Gullis auf der geglätteten Kante (heute auf der Mittellinie der Rohdaten)
- [x] Kirchen (ALKIS 31001_3041, Generator 25): Schiff mit hohen Spitzbogenfenstern (farbiges Glas, Maßwerk) und Portal mit Rundbogen, Turm (schmal und hoch) mit Schallöffnungen und Uhr auf jeder Seite, innen ein Raum ohne Zwischendecken; ein OSM-Punkt widmet eine Kirche nicht mehr um (Import) - `docs/images/viewer-kirche.png`
- [ ] Kirchen: Glockenturm innen (Glockenstube, Glocken, Treppe), ein bis zwei Seitenräume (Sakristei), Strebepfeiler, Rosette über dem Portal, Turmhelm mit Kreuz; kleine Zacken am Rand steiler Dachüberstände und gestufte Bogenkanten an schrägen Wänden
- [x] Wälder und Grünflächen (Raser.Greens, Generator 33): beim Laden jeder Kachel bepflanzt und möbliert, fest aus Fläche und Weltraster - Wald alle 4,5 m mit Arten in Flecken (Buche, Eiche, Birke, Ahorn, Kiefer, Fichte), Lichtungen, Waldrand niedriger und buschiger, Unterwuchs aus Büschen und Farnen, Waldboden aus Laub und Moos; Park mit Baumgruppen, Blumenbeeten, Bänken und Mülleimern an den Wegen, Laternen an langen Wegen, Hecken zur Straße; Spielplätze (Sandkasten, Schaukel, Rutsche, Klettergerüst), Tore und Körbe auf Sportplätzen, Kleingärten (Laube, Beete, Obstbaum, Hecke), Gräberreihen, Schilf am Ufer; Wege bleiben frei, Hecken und Spielgeräte halten auf; fern im Wald halb so viele, breitere Kronen - `docs/images/viewer-wald.png`, `docs/images/viewer-wald-innen.png`, `docs/images/viewer-gruenflaeche.png`, `docs/images/viewer-spielplatz.png`
- [ ] Grün weiter: Linien auf Sportplätzen, Zäune um Spielplätze und Kleingärten, Kapelle und Wege auf Friedhöfen aus den Daten, Teiche mit flachem Ufer und Seerosen, Wiesen mit hohem Gras und Blumen, Totholz und Baumstümpfe im Wald, Jahreszeiten (Herbstlaub, kahle Bäume)
- [x] Ferne Bäume als Kronen (achteckige Ringe mit eigenem Grünton je Fläche) statt Quader
- [ ] Fenster und Türen (Raser.Facade, Generator 16)
  - [x] Fensterraster entlang der Wand: Läufe (Grundriss geteilt an Ecken über 30°, Rundungen bleiben ein Lauf), Plätze gleichmäßig je Lauf mit Abstand zu den Ecken - nichts geht mehr um die Ecke
  - [x] Fenster je Nutzung (ALKIS-Funktion, POI): Wohnhaus Lochfenster (1,4 m, weißer Rahmen ringsum, keine Kreuze), Laden/Gastro/Büro Schaufenster im Erdgeschoss zur Straße (dunkle Rahmen), Pavillon/Kiosk hohe Fenster, Gewerbe Fensterbänder, öffentlich hohe breite Fenster, Garagen Tore, Überdachungen nichts - `docs/images/viewer-pavillon-fenster.png`, `docs/images/viewer-schaufenster.png`
  - [x] Eingänge auf der Hauptseite (zur nächsten Straße): Haustür aus Holz, jede zweite drei Stufen hoch mit Betonstufen davor; Glastüren bei Läden (eine je 10 m), breite Automatiktür bei Märkten
  - [x] Fenster, Türen und Tore als eingehängte Elemente (Raser.Facade.Panes, Generator 23): je Öffnung ein Parallelogramm zwischen linker und rechter Laibung, Glas mit Rahmenleisten, Türblatt mit Oberlicht - glatt auch in schrägen und runden Wänden; die Wand lässt nur die Öffnung frei. Dasselbe Prinzip für den Baumodus: linken und rechten Rand setzen, die Scheibe spannt sich dazwischen
  - [x] Pavillons ohne Zwischendecke hinter den hohen Scheiben
  - [ ] Elemente auch für Balkontüren, Schaufenster über Eck
  - [x] Die ferne Stufe nach derselben Planung: je Öffnung eine Fläche vor der Wand (FarMesher.FarWindows), nachts dieselben erleuchteten Fenster - kein Umspringen beim Näherkommen
  - [ ] Fenster mit Fensterbank, Laibung nach innen versetzt; Türen als Bauelement zwischen zwei Wänden; Vordächer und Markisen an Läden
  - [ ] Die innere Kante dicker Wände (hinter Schnitten) treppt in den Fensteröffnungen; Glas spiegelt kaum (Licht und Wetter)
- [ ] (aufgegangen in den Bauelementen) Gerade Fronten in jedem Winkel: senkrechter Schnitt im Grundriss je Voxel (zwei Randpunkte in Vierteln, mit den Nachbarn geteilt), Fassaden schräg zum Gitter glatt, Fenster entlang der Wand; Grundstücke zur Straße ausrichten (gemeinsame Fluchtlinie), an der Grundstücksgrenze schräg abschneiden
- [ ] Später: Grünstreifen an der Straße und Mittelstreifen (mit Bäumen), Verkehrsberuhigung in 30er-Zonen - Einengungen und Verschwenkungen, Drempel und Aufpflasterungen (OSM `traffic_calming=bump/hump/table/choker/chicane`, `zone:maxspeed=DE:30`)
- [ ] Gehwege nach Bauzeit erkennen und bauen (aus OSM `sidewalk`/`surface`, Straßentyp, Baujahr des Viertels, später Luftbild): alt geteert nur mit Bordstein und Höhenunterschied; grobes Pflaster der 80er/90er; heute schmale Pflastersteine, bei genug Breite mit rotem Radweg (`cycleway=track`)
- [ ] Fassaden-Grammatik + parametrische Materialien
  - [x] Fassaden-Materialien im Atlas (Generator 30): zwei Fassaden-Bänke der Palette (128 .. 159, 180 .. 247, je vier Dreckstufen) - Putz in Weiß, Creme, Beige, Ocker, Gelb, Pastellgrün, Rosa, Hellblau, Hellgrau, Kratzputz; Ziegel rot, dunkel, hell, gelb, braun, Kreuzverband mit dunklen Bindern, Klinker; Schiefer und Faserzement; Sandstein und grauer Werkstein in Quadern; Fachwerk-Balken; Waschbeton, Betonplatten, dunkle Vorhangfassade, Trapezblech; Dachziegel rot, orange, braun, anthrazit, Schiefer. Fassaden und Dächer mit zwei Texeln je Voxel (Ziegel 40 x 10 cm, Dachziegel 20 x 30 cm) und Relief; Dachziegel quer zum Gefälle; Atlas 2048 x 2048 - `docs/images/viewer-haeuser-atlas.png`
  - [x] Aussehen je Gebäude (Raser.HouseStyle): Bautyp aus Nutzung, Höhe, Dach und Grundriss (Siedlungshaus, Zeilenbau, Altbau, Hochhaus, Gewerbe, öffentlich, Kirche, Nebengebäude), eine Farbfamilie je Straße und Bautyp (Siedlung in Ziegel, Zeile in Pastell, ein Dach für alle), jedes Haus seine Farbe daraus, jedes fünfte aus einer anderen Familie; LoD2-Teile wie das Gebäude, an das sie stoßen. In den Voxeln Sockel, Gesims, Erdgeschoss der Läden, Giebel mit Schiefer oder Faserzement, Fachwerk (Schwelle, Riegel, Ständer, Streben), unter der Traufe schmutziger; im Netz Rahmen- und Türfarbe, Fensterbänke, Fensterläden, Balkone (Zeilen, Hochhäuser), Giebelgauben; die ferne Stufe mit Sockel, Gesims, Balkonen und Gauben - `docs/images/viewer-haeuser-siedlung.png`, `docs/images/viewer-haeuser-zeile.png`, `docs/images/viewer-haeuser-fachwerk.png` (erfundene Testkachel), `docs/images/viewer-haeuser-bochum.png`
  - [x] Stil nach Ort (Generator 31, `Raser.HouseStyle.SettingOf`): Altstadt (Gebiet `historic=district` oder namens Altstadt, Baujahr vor 1850, dicht mit kleinen Häusern), Land (Hof, Weiler, Dorf, Felder in der Nähe bei lockerer Bebauung), Industrie- und Gewerbegebiet, Innenstadt, Wohngebiet - Fachwerk in der Altstadt weiß verputzt mit dunklen Balken, auf dem Land mit roten Ziegeln dazwischen, Scheunen in Ziegel; kein Fachwerk im Gewerbe - `docs/images/viewer-altstadt.png`, `docs/images/viewer-dorf.png` (erfundene Testkachel)
  - [x] Import: Gebiete ohne Belag (`TileData.zones`: landuse residential/farmyard/meadow ..., place, historic), OSM-Tags der Gebäude-Umrisse am LoD2-Gebäude (`Building.tags`: building, building:levels, start_date, building:material, roof:colour, parking ...), Ortsnamen als POI - wirkt erst nach einem neuen Import der Region
  - [x] Besondere Gebäude als Bausteine (`IBuildingKind` in Raser.World, Teile im Netz in `Raser.KindParts`): Tankstelle (Shop, Dach auf Stützen mit Blende, Zapfsäulen auf Inseln, Preismast), Überdachungen auf Stützen (ALKIS 51009_161x, vorher volle Blöcke), Parkhaus (offene Geschosse mit Brüstung, Stützen), Markt (Vordach, Werbeband in neutraler Farbe), Kiosk (Markise), Garagenhof (bunte Tore), Werkstatt, Halle (Trapezblech und Sandwichpaneele grau, blau, weiß, rot oder Klinker; Rolltore, Lichtband, Sheddach), Schule - `docs/images/viewer-tankstelle.png`, `docs/images/viewer-parkhaus.png`, `docs/images/viewer-industrie.png` (erfundene Testkachel)
  - [ ] Weitere Bausteine: Laderampen an Hallen, Rampen im Parkhaus, Zechengebäude (Fördergerüst, Maschinenhaus), Bahnhof, Krankenhaus, Sporthalle; Zapfsäulen und Preismast als Hindernis
  - [ ] Später, sparsam: Werbetafeln (Plakatwände an Brandmauern und Straßen) und Litfaßsäulen - ohne echte Marken
  - [ ] Baujahr auch aus Luftbildern; LoD2-Gebäudeteile mit der ID ihres Gebäudes (heute: Teile folgen dem Nachbarn, an den sie stoßen)
  - [ ] Mehr Fassaden-Elemente: Stuck und Fensterfaschen am Altbau, Erker, Loggien, Treppenhausfenster, Balkontüren statt Fenster hinter den Balkonen, Dachrinnen, Schornsteine; Fachwerk und Giebel auch in der fernen Stufe
- [ ] Fenster ab Stufe 1 als Fassaden-Textur (gleiches Raster wie die Voxel-Fenster, 1 Texel je Voxel); nachts einzelne Fenster als Lichtquellen
- [ ] Ausstattung der Gebäude, zufällig aber stabil (aus ID und Seed): vorgerenderte Innenansichten hinter den Fenstern für das schnelle Vorbeifahren, detaillierte Ausstattung in der Nähe und beim Betreten
- [ ] Sharp-bilinear-Shader
- [x] Tag/Nacht: Sonnenstand über Bochum nach Datum und Uhrzeit (Raser.Weather), Sonne mit Schatten, Mond, Dämmerungsfarben; nachts die 10 nächsten Laternen als Punktlichter, Fenster mit Licht dahinter (gut ein Drittel der Wohnungen, die meisten Läden) und Laternenköpfe leuchten - `docs/images/viewer-nacht.png`, `docs/images/viewer-sonne.png`
- [ ] Autoscheinwerfer, Ampeln und Leuchtreklamen als Licht
- [x] Wetterzustand als gemeinsamer Eingang (Raser.Weather in Raser.Core): Datum, Uhrzeit, Wolken, Regen, Nebel, Nässe - stufenlos 0..1; Physik und Gameplay lesen später dasselbe
- [x] Wetterlagen in Stärken: klar, wolkig, bedeckt, Niesel, Regen, Starkregen, Dunst, Nebel, dichter Nebel (Viewer: --weather, --rain/--fog/--clouds, Tasten T/G Uhr, R Wetter, +/- Stärke) - `docs/images/viewer-regen.png`, `docs/images/viewer-nebel.png`
- [x] Nasse Straßen (Stufe 1): bei Nässe eine nasse Textur (Beläge 40 % dunkler, Rasen und Wände etwas) und Glanz (Specular nach Nässe) - Laternen und Sonne als Lichter auf dem Asphalt - `docs/images/viewer-nass-nacht.png`, `docs/images/viewer-nass.png`
- [x] Spiegelungen auf nassen Flächen (scene3d Object.Reflectivity, Bildschirm-Spiegelung), Regen als Striche (Emitter.Stretch), alle Laternen als Licht (Light.Cutoff mit Kacheln), Fenster der fernen Stufe leuchten nachts (Object.EmissiveTexture) - braucht fire `native-c`
- [x] Pfützen ab Regen: dunkle, glatte Flecken auf den Belägen (dritte Textur mit flachem Relief) - `docs/images/viewer-pfuetzen.png`
- [ ] Pfützen in Senken statt nach Rauschen, mit stärkerer Spiegelung; Gewitter, Schnee, Wind; Wetter, das sich mit der Zeit ändert; Spiegelungen auch auf der GPU
- [ ] Ingame-Uhr in Echtzeit (deutsche Ortszeit, echter Sonnenstand), Zeitfaktor als Server-Einstellung
- [x] Mondphase/-stand astronomisch korrekt (Meeus, gekürzt: etwa ein Grad), Wolken mit orangem Stadtlicht-Himmel
- [x] Himmel (Raser.SkyLook, Sky): Verlauf nach Sonnenstand, Dämmerung und blaue Stunde, Sonne mit Schein, Mond in seiner Phase, wenige Sterne, Wolkenschicht nach Bedeckung (zieht langsam), Nebel in der Farbe des Horizonts
- [ ] Himmel: Wolken mit Volumen bzw. Schichten in mehreren Höhen, Mond und Sonne am Horizont abgeflacht
- [ ] Volumetrischer Nebel mit Lichtkegeln/Halos
- [ ] Referenzszene: Zechensiedlung in nebliger Nacht
- [ ] Mood-Akzente pro Viertel, Render-Profile pro Gebiet
- [ ] Debug-Ansicht: aktive Generatoren, Overrides, Render-Profil

## M3: Fahren & Streaming
- [ ] Kollisionsmesh aus den geschnittenen Voxeln, Override-Mesh wo nötig
- [x] Spieler zu Fuß (`Raser.Walker`): gehen, sprinten, aus- und einsteigen (E), Figur mit Schritten, Kamera dahinter oder aus seinen Augen
- [x] Baumstämme, Laternen und Ampeln halten Wagen und Spieler auf (der Spieler gleitet um sie herum); Beete, Büsche, Bänke, Schilder nicht
- [ ] zu Fuß: Treppen und Türen; Maus zum Umsehen
- [x] Spielprogramm `Raser.Game` (gemeinsamer Code mit dem Viewer in `Raser.Client`): Auto, Verfolger-/Haubenkamera, Tacho, Uhr, Wetter, Scheinwerfer
- [x] Fahrzeugphysik (Einspurmodell `Raser.Vehicle`) inkl. Nässe und Aquaplaning
- [x] Aufprall: der Wagen (zwei Kreise) rutscht an Wänden entlang und dreht dabei weg, frontal prallt er zurück (`Vehicle.Collide`, `Obstacles.Push`)
- [x] Verfolgerkamera weicht Gebäuden aus (rückt heran und höher, weich wieder hinaus)
- [x] Kamera an der Wand: weicht bis 60° zur Seite aus (die Richtung mit dem weitesten freien Weg), bleibt es eng, steigt sie und blickt von oben
- [x] Schaden aus der Wucht des Aufpralls (`Vehicle.health`, `DamageOf`: bis 7 km/h nichts, 50 km/h frontal 39 %; kaputt fährt nichts), Anzeige „Zustand“
- [ ] Glätte; Bordsteine; Laternen und Schilder umfahren
- [x] Fahrzeugklassen (`Vehicle.Of`): Auto, Transporter, Motorrad, Fahrrad - eigene Fahrwerte, Modelle, Kamera; die anderen Klassen stehen am Start geparkt, der Spieler steigt ins nächste ein; Fahrzeuge halten einander auf
- [x] Zweiräder legen sich in die Kurve (`Vehicle.lean` = atan(v · Gierrate / g), höchstens 40°), der Fahrer sitzt (Sitzhaltung der Figur)
- [x] Tank je Fahrzeug (`Vehicle.fuel`, Gas x Antrieb verbraucht; das Fahrrad braucht keinen; leer fährt nichts), Anzeige „Tank“
- [x] Angefahrene Fahrzeuge rutschen los (`Vehicle.Shove`: unelastischer Stoß nach Masse, die Reifen bremsen, Wände halten auf) und nehmen Schaden
- [x] Fahrzeuge am Straßenrand verteilt (`Game.Parking`: Straßen für Autos der Startkachel, 20 bis 200 m vom Start, nicht an Gebäuden und Pfosten; `--parked 8`)
- [ ] Fahrzeuge: Akku statt Tank für E-Fahrzeuge, Tankstellen; angestoßene Fahrzeuge drehen sich; Parkplätze in allen Kacheln (beim Nachladen), Parkplatzflächen aus OSM
- [x] Streaming gemessen (`raser --live 60 [--speed 50]`: Autopilot, 30 Bilder je s): über Kachelgrenzen hinweg fehlt unter dem Wagen und 60 m voraus nie eine Stufe (50 km/h, nah 1, fern 5)
- [x] Die fernen Stufen baut ein eigener Worker (vorher das Hauptprogramm), Modelle entstehen Netz für Netz im Zeitbudget
- [x] Ruckler beim Nachladen kleiner (fire a9d8598d: Natives sperren einander nicht mehr; Netze als Byte-Puffer durch den Kanal; Worker `dedicated`): 24 statt 15 Bilder je s, das längste Bild 0,25 bis 0,55 statt 0,8 bis 1,3 s
- [x] Rest-Ruckler beim Nachladen: die alten Arrays der Netze hingen nach `Pack` weiter am Netz (ein auf `undefined` gesetztes Feld gibt fire absichtlich nicht frei) - mit `delete`: 28,8 Bilder je s, das längste Bild 0,29 s, Abholen höchstens 4 ms
- [x] Vorausladen in Fahrtrichtung: die nahe Stufe gilt um das Fahrzeug und entlang seines Wegs (Tempo x 4 s, höchstens 250 m), bestellt in der Reihenfolge der Fahrt (`WorldView.SetMotion`/`Want`); die Worker bauen auch die Modelle - Geisterfahrt (`--live 25 --ghost 1 --speed 100`): ohne nahe Stufe unter dem Wagen 0 statt 95 Bilder, 30 m voraus 2 statt 236
- [x] Lange Fahrten: Hindernisse und Gelände geben Kacheln weiter als eine Kachel wieder frei (`Trim`), Fahrzeuge weiter als 400 m werden nicht nachgesetzt
- [ ] Netze auf 6000 statt 16 000 Vierecke begrenzt (ein Worker hält die Sperre von scene3d beim Bauen eines Modells kürzer) - ob das Rendern davon etwas merkt, ist nicht gemessen: `--live` ohne `--render` rendert nicht ("Rendern" ist dort die Wartezeit bis zum nächsten Bild)
- [ ] LOD für weite Sichtweiten
- [x] GPU (`--gpu 1`, getestet mit lavapipe: `FIRE_S3D_GPU=cpu`): die Welt erscheint (undurchsichtige Netze mit `AlphaCutoff`), Nebel/Lichtkacheln/Spiegelungen kommen aus fire 74a2c16d
- [x] Himmel nativ in scene3d (`Object.Background`, fire-Zweig `native-c`: zuerst gezeichnet, ohne Tiefe und Nebel): Regen und Glas vor dem Himmel, Himmel auf der GPU, keine Blits mehr

### Detail und Abwechslung
- [ ] Fahrzeuge detaillierter: echte Modelle statt Quadern (Karosserieformen, Scheiben, Räder mit Felgen, Spiegel, Kennzeichen, Lichter), mehrere Modelle je Klasse (Kleinwagen, Kombi, SUV, Taxi, Bus, Lieferwagen, Roller, Rennrad ...), Farben und Zustand sichtbar (Beulen, Schmutz)
- [ ] Spieler und Fußgänger detaillierter: Figur mit Gelenken (Ober-/Unterarm, Knie), Gehen/Rennen/Sitzen als Animation, verschiedene Statur, Kleidung, Frisuren, Hautfarben
- [ ] Grünstreifen detaillierter: Gräser, Stauden, Blühstreifen, Bodendecker, Rindenmulch, Laub, Baumschutzbügel, Poller; verschiedene Bepflanzung je Straßenart und Stadtteil
- [ ] Mehr Abwechslung überall: Varianten statt Wiederholung (Bäume nach Art, Fassaden, Fenster, Türen, Straßenmöbel, Werbung, Mülltonnen, Fahrräder an Ständern), zufällig aber deterministisch je Ort
- [ ] Werbetafeln und Litfaßsäulen - aber nicht zu viele: wenige je Straße, an typischen Stellen (Litfaßsäulen an Kreuzungen und Plätzen, Plakatwände an Hauptstraßen, Bahndämmen, Brandwänden, Bushaltestellen), Plakate mit erfundenen Motiven (keine echten Marken), deterministisch je Ort

## M4: Multiplayer-Grundgerüst
- [x] Koordinator + ein Regionsserver auf einem Rechner, Protokoll schon für mehrere Regionen ausgelegt (`raser-server`, docs/SERVER.md: ein Prozess, getrennte Klassen, Nachrichten mit Region und Kachel)
- [x] Konten und Sitzungen (SQLite, PBKDF2, Rollen Spieler/Admin), Launcher-API (HTTP 7480), Spielprotokoll v1 (TCP 7481), Chat, Admin-Befehle, Konsole im Spiel
- [ ] Globale, eindeutige Objekt-IDs (Spieler, Fahrzeuge, Behälter, Gegenstände am Boden: ja, `Raser.IdAllocator`); globale Dienste (Konten: ja; Inventar, Wirtschaft) getrennt von Regionen
- [x] Autoritativer Regionsserver, 2–8 Spieler: Protokoll v2 (Eingaben je Takt, 30 Hz), dieselbe Physik auf Server und Client (`Raser.Sim`: Fahrzeuge, Gehen, Hindernisse der Kacheln, Stöße), Fahrzeuge der Region mit IDs, Inventar über den Server (docs/SERVER.md)
- [x] Client-Prediction für Fahrzeuge und zu Fuß: Abgleich mit Nachrechnen, weicher Ausgleich, Sprung bei großen Fehlern; die anderen 100 ms in der Vergangenheit interpoliert
- [ ] Verkehr (NPC-Autos, Fußgänger) auf dem Server: Haken `RegionServer.Npcs`/`NpcEntities` und Entitäten 3/4 sind da; Ereignis „Spieler umgehauen“ mit Verursacher (die Folgen fehlen noch)
- [x] Interest-Management pro Kachel (eigene Kachel und die 8 Nachbarn); Snapshots als Delta gegen den bestätigten (Protokoll v3/v4), weit weg nur jeder 2.
- [x] Stand der Spieler in SQLite (Lage, Fahrzeug, Körper, Inventar mit Inhalt), Startpunkt vom Server; Hindernis-Kacheln aus einem Worker (Übernahme zu fester Taktgrenze); zu Fuß gegen zu Fuß (Spieler, Fußgänger)
- [ ] Serverseitiges Wetter (jetzt: Uhr und Preset maßgeblich vom Server, `/time`, `/weather`; simuliert per Seed, optional echtes DWD-Wetter)
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
