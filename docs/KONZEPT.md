# Konzept: Ruhrpott-Raser

## 1. Voxel-Größe und Fahren

- **Voxelgröße 20 cm** (1/5 Minecraft). Das passt zu in Europa üblichen Maßen: Tür 2,0 m = 10 Voxel, Geschosshöhe ca. 2,8–3,0 m = 14–15 Voxel, Wandstärken von 20–40 cm = 1–2 Voxel, Bordstein 20 cm = 1 Voxel.
  - Pro Volumen sind das 125× mehr Voxel als bei Minecraft.
  - Chunks/Bricks deshalb größer wählen (z. B. 64³ = 12,8 m Kantenlänge).
  - LOD ist ab Tag 1 Pflicht.
- **Diagonale Höhen-Schnitte:** Ein Voxel darf oben schräg abgeschnitten sein. Die Oberseite ist über **vier Eckhöhen** definiert, quantisiert in 1/4-Voxel-Schritten (5 cm).
  - Benachbarte Voxel teilen sich die Eckhöhen. So entstehen durchgehende, lückenlose Flächen ohne Treppen.
  - Straßen, Rampen, Böschungen und Dächer sind damit direkt im Voxelmodell abbildbar.
  - Speicher: 4 × 2 Bit = 1 Byte zusätzlich pro geschnittenem Voxel (nur Oberflächen-Voxel, Rest bleibt voller Würfel).
  - Später möglich: diagonale Schnitte im Grundriss (Viertelkeile) für schräge Fassaden und Bordsteine.
- **Fahrphysik auf derselben Geometrie:** Das Kollisionsmesh für Fahrzeuge entsteht aus denselben geschnittenen Voxeln wie die Optik. Was man sieht, ist auch das, worauf man fährt. Wo Fahrzeuge ganz glatte Flächen brauchen (Autobahn, enge Kurven), darf ein Override-Mesh aus dem Zwischenlayer einspringen (siehe Abschnitt 9).

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
| NRW Open Data: DOP | Luftbilder für Dach- und Bodenfarben; Gegencheck: Untergründe genauer bestimmen, fehlende Gebäude als Patches (Override-Layer) |
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

### Gelände und was darauf steht

- **Das Gelände ist glatt:** ein Netz aus dem Höhenraster, mit Diagonalen statt Stufen, in jeder Detailstufe. Stufig (Voxel) ist nur, was darauf steht.
- **Gebaut wird im globalen Voxel-Raster:** Die Unterkante eines Gebäudes rastet auf ein Voxel (20 cm) ein, und zwar nach unten: Es versinkt eher halb im Gelände,
  als dass es schwebt. Wo das Gelände unter dem Grundriss tiefer liegt, füllt ein Fundament die Lücke.
- **Das Gelände ist hart, wo etwas hineingreift:** Fundamente, Keller, Gruben und Aufschüttungen. Dort bekommt das Gelände seine Voxel-Flächen mit harter
  Kante, und das glatte Netz spart die Stelle aus (in Zellen von 80 cm). Darum kann man das Gelände in einem Gebäude abtragen oder mit harter Kante absenken,
  zum Beispiel für Keller. Das gilt für Gebäude aus den Daten (`cellars` im Zwischenlayer bzw. als Override) und für den Baumodus.

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

**Fenster:** Ab der ersten Detailstufe sind Fenster Teil der Fassade (Textur bzw. Shader nach demselben Raster wie die Voxel-Fenster), keine Geometrie. Echte Fenster-Voxel gibt es nah am Spieler, in materialisierten Gebäuden und bei Zerstörung (Glas splittert). Nachts leuchten einzelne Fenster.

**Ausstattung:** Jedes Gebäude bekommt eine zufällige, aber stabile Ausstattung (aus Gebäude-ID und Seed, passend zu Nutzung und Viertel). Für das Vorbeifahren mit hohem Tempo reichen ein paar vorgerenderte Innenansichten hinter den Fenstern (Wohnzimmer, Büro, Laden, Treppenhaus - als Textur mit Tiefe, ohne Geometrie); läuft man nah vorbei oder betritt das Gebäude, entsteht die detaillierte Ausstattung (Möbel und Objekte, Abschnitt 7) - dieselbe Wahl, nur genauer.

**Materialien mit Leben:** Kein Voxel eines Materials sieht aus wie der nächste. Jede Materialfarbe hat eine weltfest liegende Textur von 64 x 64
Voxeln (ein Chunk), aus der jede Voxel-Fläche ihren Ton nimmt - Ziegel versetzt mit eigenem Ton je Stein, Dachziegel in Reihen, Holz mit Maserung,
Platten mit Fugen, Putz und Beton mit ruhigen Flecken, Gras und Erde mit Körnung. Dazu je Gebäude (aus Gebäude-ID und Seed) eine Farbvariante und eine
Dreckstufe (sauber bis stark verrußt: dunkler, Flecken, Laufspuren) für Wand und Dach. Alles prozedural; gleiche Flächen bleiben große Rechtecke, die
Abwechslung kommt aus der Textur.

**Rendering:** Pixel werden nearest-neighbor gerendert, aber antialiased. Das geschieht als „sharp bilinear“ direkt im Shader (Pixel-Art-AA über `fwidth`) statt mit vorab hochskalierten Texturen. Der Effekt ist derselbe, es braucht keinen zusätzlichen Speicher und funktioniert in jeder Entfernung.

## 4. Nacht-Atmosphäre

### Grundsatz: Klassische Straßenbeleuchtung

Die **Basis überall ist warmes, orangefarbenes Licht**, wie bei Natriumdampflampen (ca. 1800–2200 K). Neon und kaltes Licht sind **Akzente** in bestimmten Vierteln, nicht die Grundstimmung.

### Wetter und Himmel bestimmen die Nacht

Keine Nacht sieht gleich aus. Die Atmosphäre entsteht aus warmer Grundbeleuchtung × Wetter × Mond × Viertel-Mood. Details stehen in Abschnitt 5.

Referenzszene: **kleine Zechensiedlung in nebliger Nacht.** Ziegelreihenhäuser, vereinzelte orange Laternen, Licht hinter Gardinen, sonst Dunkelheit. Daran wird die Beleuchtung abgestimmt. Weitere Referenzszenen für jede Wetterlage folgen (z. B. Regen auf der Kneipenmeile, klare Neumondnacht am Kanal).

### Mood pro Viertel (Akzente über der warmen Basis)

| Viertel-Typ | Akzente |
|---|---|
| Zechensiedlung / Vorort | Keine. Nur warme Laternen, Fensterlicht, Nebel |
| Industrie / Hütte / Hafen | Orange-rote Glut, Dampf, Flutlicht |
| Innenstadt / Kneipenmeile | Neonreklamen in Magenta und Cyan (Richtung Vice City) |
| Hochhaussiedlung / Gewerbe | Werbetafeln, vereinzelt kaltes LED-Licht (Richtung Cyberpunk) |

Technik dafür: Clustered Forward oder Deferred Rendering für viele Lichtquellen, emissive Voxel, volumetrischer Nebel, Bloom, nasse Straßen mit Reflexionen.

## 5. Wetter, Mond und Tageszeit

### Wetterlagen

| Wetterlage | Optik | Auswirkung |
|---|---|---|
| Trocken, klar | Sterne, scharfe Lichtkegel, bei Vollmond blaue Mondschatten | Normale Haftung, weite Sicht |
| Neblig | Volumetrischer Nebel, Halos um Laternen, Sichtweite stark reduziert | Gegner/Polizei erst spät sichtbar, gut für Fluchten |
| Nieselregen / Regen | Nasse Straßen, Spiegelungen der Laternen und Reklamen, Pfützen, Regen im Lichtkegel | Weniger Haftung, längerer Bremsweg, Aquaplaning in Pfützen |
| Starkregen / Gewitter | Blitze erhellen kurz die Szene, Wasserfilm, Sturzbäche an Bordsteinen | Stark eingeschränkte Sicht und Haftung |
| Schnee / Frost (selten) | Weiße Dächer, Glätte, gedämpftes Licht durch reflektierenden Schnee | Glatteis, rutschige Kurven |
| Wind / Sturm | Bewegte Bäume und Planen, treibender Regen | Seitenwind auf Brücken und Autobahn |

Wetter wechselt fließend: Nach Regen bleiben Straßen eine Weile nass, auf Regen folgt in Senken und an Flüssen oft Nebel.

### Uhrzeit: Echtzeit

- **Die Ingame-Uhr läuft in Echtzeit** und entspricht der deutschen Ortszeit (inkl. Sommer-/Winterzeit). Sonnenauf- und -untergang folgen dem echten Datum, im Dezember ist es also früh dunkel, im Juni lange hell.
- Das passt zur echten Karte, zum echten Wetter (DWD-Modus) und zur echten Mondphase.
- Folge: Wer immer zur selben Uhrzeit spielt, sieht immer dieselbe Tageszeit. Für ein Spiel mit Fokus auf die Nacht-Atmosphäre ist das vertretbar. Missionen und Events sollten deshalb nicht nur zu einer festen Tageszeit verfügbar sein.
- Der Zeitfaktor bleibt eine Server-Einstellung (Standard 1:1), damit er später ohne Umbau geändert werden kann.

### Mond und Himmel

- **Mondphase und Mondstand astronomisch korrekt**, berechnet aus dem echten Datum und der echten Uhrzeit.
- Neumond + Bewölkung = besonders dunkle Nacht. Außerhalb der Laternenkegel sieht man fast nichts.
- Vollmond bei klarem Himmel = helle Nacht mit Schatten.
- Bewölkung reflektiert nachts das orange Stadtlicht (typischer orangeroter Himmel über dem Ruhrgebiet), klarer Himmel bleibt dunkel.

### Wetterquelle

Zwei Modi, pro Server einstellbar:
- **Simuliert:** Deterministisch aus Seed und Zeit, mit regionalen Wetterzellen, die über die Karte ziehen.
- **Echt:** Live-Wetter von den offenen Daten des Deutschen Wetterdienstes (DWD), umgerechnet auf die Spielwelt. Lizenz und Verfügbarkeit prüfen.

Der Server ist für das Wetter autoritativ. Clients bekommen nur die Parameter (Wetterzellen, Zeit) und berechnen die Darstellung selbst.

### Technik

- Ein **Wetterzustand** (Bewölkung, Niederschlag, Nebeldichte, Nässe der Oberflächen, Wind, Temperatur) ist ein Eingang für Renderer, Physik und Gameplay.
- Nässe wird pro Fläche gespeichert, damit Unterführungen und überdachte Bereiche trocken bleiben.
- Render-Profile (Abschnitt 9) können pro Gebiet das Wetter lokal anpassen, z. B. Dampf an Hochöfen oder Nebel über dem Kanal.

### Gameplay-Wirkung

- Fahrphysik: Haftung, Bremsweg, Aquaplaning
- Sicht und Entdeckung: Polizei und Gegner sehen bei Nebel und Dunkelheit weniger
- Wirtschaft: Wetter beeinflusst die Kundschaft (bei Regen läuft die Pommesbude schlechter, der Lieferdienst besser)
- Missionen: Manche Missionen gibt es nur bei bestimmtem Wetter oder bei Neumond

## 6. Gameplay

### Grundlagen

- **Häuser mieten:** Jedes LoD2-Gebäude ist potenziell mietbar. Innenräume werden prozedural aus Grundriss und Nutzung erzeugt, erst beim ersten Betreten.
- **Zwielichtige Geschäfte:** Wirtschaftssimulation mit Tarnfirma, Umsatz, Polizei-Aufmerksamkeit und Konkurrenz durch Spieler. Der Standort zählt.
- **Missionen:** Ein Generator nutzt echte POIs als Ziele, dazu kommen handgebaute Story-Missionen an festen Orten.

### Fortbewegung

Wie in GTA: **Jeder startet zu Fuß.** Fahrzeuge muss man sich kaufen, leihen oder klauen.

| Kategorie | Beispiele | Woher |
|---|---|---|
| Zu Fuß | Laufen, Sprinten, Klettern | Von Anfang an |
| Fahrrad / E-Scooter | Hollandrad, Rennrad, Leih-Scooter | Fahrradladen, Leihstationen, klauen |
| Motorrad / Roller | Mofa, Vespa-Typ, Superbike | Motorradladen, klauen |
| Auto | Kleinwagen, Kombi, Tuning-Karre, Sportwagen, Transporter | Autohändler, Autoverleih, klauen |
| Nutzfahrzeuge | Lkw, Bus, Müllwagen, Polizei | Missionen, klauen |
| Öffentlicher Verkehr | S-Bahn, RE, Straßenbahn, Bus | Bahnhöfe und Haltestellen |
| Flugzeug | Linienflug als Schnellreise, später ggf. kleine Flugzeuge | Flughäfen |

- Fahrzeuge haben **Tank bzw. Akku, Zustand und Tuning**. Ein leerer Tank ist ein echtes Problem, deshalb sind Tankstellen wichtig.
- **Öffentlicher Verkehr fährt auf dem echten Netz** aus OSM und dient als Schnellreise durch NRW. Für das Streaming ist das praktisch: Das Ziel steht fest, also kann der Server die Zielregion während der Fahrt vorgenerieren.
- Fahrzeuge der Fantasie-Marken sind an echte Modelle angelehnt, ohne echte Marken- oder Modellnamen.

### Kampf und PvP

- **PvP ist möglich**, überall außerhalb von Schutzbereichen.
- **Waffen in allen Varianten:** Nahkampf, Pistolen, Gewehre, Sprengstoff. Dazu **sarkastische Waffen** mit Ruhrpott-Bezug, z. B. Kohlenschaufel, Gartenzwerg-Granate, Taubenschlag (Brieftauben als Ablenkung), Bierflaschen-Wurf, Grubenlampe als Blendgranate.
- **Fahndungslevel** wie in GTA: Gewalt und Diebstahl rufen die Polizei, je nach Schwere und Zeugen. Nebel und Dunkelheit (Abschnitt 5) machen Flucht leichter.
- **Schutz gegen Griefing:**
  - Eigene Wohnung, Hotelzimmer und bestimmte Gebäude sind Schutzbereiche.
  - Neue Spieler haben eine Schonfrist ohne PvP.
  - Spieler, die oft Schwächere angreifen, bekommen ein hohes Kopfgeld, das andere einsammeln können.

### Rennen

- **Legale Rennen** auf abgesperrten Strecken: Rennstrecken, Industriegelände, gesperrte Straßenabschnitte bei Events. Mit Startgeld, Preisgeld und Ranglisten.
- **Illegale Straßenrennen** im normalen Verkehr: Treffpunkte an Tankstellen und Parkplätzen, Wetten unter Spielern, die Polizei kann eingreifen. Die Route wird aus dem echten Straßengraphen erzeugt oder von Spielern gesetzt.
- Rennen sind **Missionen wie andere auch**: Sie können von Spielern ausgeschrieben werden und gelten für Wetter, Fahndung und Wirtschaft genauso.

### Spielerwerte

- **Vitalwerte** (schwanken, müssen gepflegt werden): Gesundheit, Hunger, Durst, Energie, Stress, Rausch
- **Fähigkeiten** (steigen durch Nutzung und Training): Fahren, Schießen, Ausdauer, Kraft, Verhandeln, Hacken
- **Ruf** in mehreren Szenen: Straße, Rennszene, Geschäftswelt, Polizei

### Kein dauerhafter Tod: höchstens Krankenhaus

- Ein Spieler **stirbt nie endgültig**. Sinkt die Gesundheit auf null (Kampf, Unfall, Absturz, Vernachlässigung der Vitalwerte), wacht er im **nächstgelegenen Krankenhaus** auf.
- Folgen sind spürbar, aber nicht vernichtend: Behandlungskosten, ein Teil des mitgeführten Bargelds oder der Gegenstände ist weg, Fahrzeug bleibt am Unfallort (oder wird abgeschleppt), Fahndungslevel ggf. zurückgesetzt oder in Polizeigewahrsam.
- Damit wird das Krankenhaus vom Kandidaten zum festen Gebäudetyp, auch mit Jobs (Rettungsdienst, Pflege).

### Offline-Spieler

- **Welt und Zeit laufen immer weiter**, auch wenn ein Spieler offline ist: Tag und Nacht, Wetter, Wirtschaft, andere Spieler.
- **Vitalwerte werden eingefroren.** Niemand verhungert, verdurstet oder stirbt durch Untätigkeit. Nach dem Einloggen geht es mit denselben Werten weiter.
- **Der Charakter verlässt beim Ausloggen die Welt.** Er steht nicht schutzlos herum. Gegen Kampf-Ausloggen gibt es eine kurze Wartezeit, wenn man gerade im Kampf ist oder gesucht wird.
- **Einkommen und Kosten laufen pro aktivem Tag.** Ein Tag ist der deutsche Kalendertag (00:00–24:00, passend zur Echtzeit-Uhr).
  - Loggt sich ein Spieler an einem Tag ein, wird dieser Tag **aktiv**: Einkommen und Kosten laufen für den ganzen Tag.
  - Was seit Tagesbeginn angefallen ist, wird **beim Einloggen sofort verbucht**. Der Rest des Tages läuft normal weiter, auch nach dem Ausloggen bis Mitternacht.
  - Ist ein Spieler über Mitternacht online, wird der neue Tag direkt aktiv.
  - **Tage ohne Login zählen nicht.** Weder Einkommen noch Kosten, Besitz steht still.
- **Wenige Posten laufen immer**, auch an inaktiven Tagen. Sie sind bewusst klein, damit niemand durch Abwesenheit ruiniert wird oder reich wird. Kandidaten:
  - Kosten: Grundsteuer und Versicherung für eigenen Besitz
  - Einkommen: Zinsen auf ein Sparkonto
- **Verträge zwischen Spielern** (z. B. Miete): Es zählen die aktiven Tage des Zahlenden. Der Mieter zahlt an seinen aktiven Tagen, der Vermieter bekommt das Geld dann gutgeschrieben, auch wenn er selbst offline ist.
- Eine AFK-Erkennung ist dafür nicht nötig: Länger eingeloggt bleiben bringt kein zusätzliches Einkommen.

### Gebäudetypen mit Funktion

Die Funktion eines Gebäudes kommt aus den **echten OSM-Tags** (z. B. `amenity=fuel`, `amenity=bar`, `shop=car`). Echte Orte bekommen also die passende Funktion. Echte Firmennamen und Logos werden durch Fantasie-Namen ersetzt.

| Gebäudetyp | Kaufen / Verkaufen | Wirkung auf Werte | Besonderheit |
|---|---|---|---|
| **Tankstelle** („Tanke“) | Sprit, Bier, Snacks, Zigaretten, Zeitung, Kleinkram | Hunger, Durst, Stress | **Kulturgut.** 24/7 geöffnet, Treffpunkt der Rennszene, Ort für Missionen, beliebtes Überfallziel. Eigene Atmosphäre: Leuchtreklame, Neonröhren, Typen am Stehtisch |
| Restaurant / Imbiss / Pommesbude | Essen, Getränke | Hunger, Durst, Gesundheit | Qualität und Preis unterschiedlich. Currywurst-Pommes-Schranke als Standard |
| Bar / Kneipe | Getränke | Durst, Stress, Rausch | Infos und Missionen von Stammgästen, Kontakte für Geschäfte |
| Disco / Club | Eintritt, Getränke | Stress, Energie, Rausch | Türsteher, Ruf entscheidet über Einlass, nachts Treffpunkt |
| Rotlicht-Etablissement | Eintritt, Getränke | Stress | Kann als zwielichtiges Geschäft betrieben werden. Inhalte bleiben angedeutet, nichts explizites |
| Spielothek | Automatenspiel | Stress, Geld | Kleines Glücksspiel, auch als Tarnfirma |
| Casino | Roulette, Poker, Blackjack | Stress, Geld | Großes Glücksspiel, Kleiderordnung, Heist-Missionen |
| Hotel | Zimmer | Energie (schlafen), Speicherpunkt | Zimmer ist ein Schutzbereich, gut ohne eigene Wohnung |
| Bahnhof | Tickets | – | Schnellreise auf dem echten Netz, Schließfächer als Lager |
| Flughafen | Flugtickets | – | Schnellreise über große Distanzen, Schmuggel-Missionen |
| Autoverleih | Auto mieten | – | Ohne Kauf sofort mobil, Kaution, Schaden kostet extra |
| Autohändler | Autos kaufen und verkaufen | – | Neu- und Gebrauchtwagen, Hehlerei mit gestohlenen Autos |
| Fahrradladen | Fahrräder, Teile | – | Billiger Einstieg in die Mobilität |
| Motorradladen | Motorräder, Roller, Ausrüstung | – | Helm und Kluft schützen bei Stürzen |
| Internetcafé | Zugang zu Rechnern | – | Darknet-Markt, Hacking-Missionen, anonyme Aufträge |
| Krankenhaus | Behandlung, Medikamente | Gesundheit | Hier wacht man auf, wenn die Gesundheit auf null fällt |
| Supermarkt | Nahrungsmittel, Getränke, Haushalt | Hunger, Durst | Vorräte für zu Hause, günstiger als Imbiss |
| Baumarkt | Baumaterial, Farben, Werkzeug, Gartenmöbel | – | Material und Farben für den Baumodus (Abschnitt 7) |
| Elektronikmarkt | Fernseher, Computer, Konsolen, Licht, Musikanlagen | Stress | Geräte mit Funktion für die eigene Wohnung |

Weitere Kandidaten: Werkstatt/Tuning, Waffenladen, Kiosk/Trinkhalle („Büdchen“), Apotheke, Fitnessstudio, Friseur/Kleidung, Pfandhaus, Polizeiwache.

### Jobs

Gebäude bieten auch **legale Jobs** an, als Gegenstück zu den zwielichtigen Geschäften. Gute Einstiegsmöglichkeit für neue Spieler, die zu Fuß und ohne Geld starten. Ein Job kann gleichzeitig Tarnung oder Zugang für illegale Aktionen sein.

| Gebäude | Beispiel-Jobs | Nebeneffekt |
|---|---|---|
| Tankstelle | Kassierer, Nachtschicht, Waschanlage | Kennt die Rennszene, Infos über Treffpunkte |
| Imbiss / Restaurant | Koch, Kellner, Lieferfahrer | Lieferfahrten = Fahrtraining, lernt die Stadt kennen |
| Bar / Disco | Barkeeper, Türsteher, DJ | Kontakte, Ruf in der Straßenszene |
| Hotel | Rezeption, Pagen-Dienst | Zugang zu Zimmern |
| Bahnhof / Flughafen | Lokführer, Busfahrer, Gepäckabfertigung | Zugang zu Lager- und Frachtbereichen |
| Autohändler / Verleih | Verkäufer, Überführungsfahrer | Zugang zu Fahrzeugen und Schlüsseln |
| Internetcafé | Aufsicht, IT-Support | Hacking-Fähigkeit steigt |

Jobs funktionieren als **wiederholbare Kurz-Missionen** (Schicht), bringen Lohn und Fähigkeiten und steigen mit der Zeit im Rang (Aushilfe → Schichtleiter → Filialleitung → Übernahme des Ladens).

### Öffentliche Verwaltung und Bauhöfe (später)

Öffentliche Einrichtungen bieten Jobs, die **echte Aufgaben in der Spielwelt übernehmen**. Was sonst der Server automatisch erledigt, kann ganz oder teilweise von Spielern gemacht werden. Ein Server läuft auch ohne diese Spieler, dann übernimmt die Automatik.

- **Stadtverwaltung / Bürgeramt / Ordnungsamt:**
  - Genehmigungen für Geschäfte, Events und legale Rennen
  - Knöllchen, Abschleppen, Kontrolle von Gewerben
  - Bestechlich: Genehmigungen lassen sich auch kaufen
- **Bauamt:**
  - Ändert öffentlichen Grund im Baumodus (Straßen, Plätze, öffentliche Gebäude)
  - Mit Freigabe einer höheren Instanz auch Besitz von Spielern (Abschnitt 7)
- **Bauhof / Straßenmeisterei:**
  - Zerstörte Bereiche reparieren. Das setzt Spieler-Deltas zurück auf den generierten Grundzustand (Abschnitt 7).
  - Baustellen einrichten, Straßen sperren, Schnee räumen und streuen (Abschnitt 5)
  - Müllabfuhr, Wracks entfernen
  - Gemeldete Darstellungsfehler (Abschnitt 9) vor Ort prüfen und **Korrekturvorschläge** einreichen. Diese landen im Override-Layer, aber erst nach einer Prüfung.

Grundsatz: Spieler können nur Aktionen auslösen, die das Spiel auch selbst ausführen könnte. Spieler-Bauten und Bauamt-Änderungen sind Deltas und lassen sich zurücksetzen. Korrekturen der generierten Welt selbst (Override-Layer) werden immer erst geprüft.

**Glücksspiel ist rein virtuell:** Gespielt wird nur mit Spielwährung. Die Währung kann nicht mit echtem Geld gekauft werden, Gewinne lassen sich nicht auszahlen, und es gibt keinen Handel gegen Echtgeld. Simuliertes Glücksspiel kann trotzdem die Altersfreigabe beeinflussen. Bei Waffen und Kriminalität wie in GTA ist ohnehin eine Freigabe ab 18 zu erwarten.

## 7. Bauen und Besitz

### Baumodus

Eigener Besitz (gekauft oder gemietet) lässt sich umbauen, wie in Minecraft. Der Baumodus ist **kein eigenes Spiel im Spiel**: Er tauscht nur HUD, Steuerung und Werkzeuge aus. Man bleibt in der Welt, andere Spieler sehen einen weiter.

**Bewusst einfach gehalten.** Werkzeuge im Grundumfang:

| Werkzeug | Funktion |
|---|---|
| Setzen / Entfernen | Einzelne Voxel oder ein aufgezogener Quader |
| Form | Voller Würfel oder Höhen-Schnitt (Schräge, Abschnitt 1) |
| Material | Auswahl aus wenigen Materialien (siehe unten) |
| Pinsel | Oberfläche einfärben, ohne die Struktur zu ändern |
| Objekt platzieren | Möbel, Geräte, Deko aus dem Inventar |
| Rückgängig / Wiederholen | Pflicht, mit Verlauf |

Erweiterungen (Kopieren/Einfügen, Spiegeln, Vorlagen) kommen erst, wenn der Grundumfang sitzt. Ein einfacher Baumodus hält auch die Datenstruktur einfach. Das hilft der Nachbesserbarkeit (Abschnitt 9).

### Materialien

Wenige Materialien mit **fester Oberflächenstruktur**. Die Farbe trägt man mit dem Pinsel auf.

| Material | Struktur (fest) | Standard |
|---|---|---|
| Beton | Krisselig, leichte Poren | Grau |
| Holz | Leicht gemasert | Naturholz |
| Glas | Glatt | Transparent, tönbar |
| Metall | Gebürstet oder matt (zwei Varianten) | Stahlgrau |
| Ziegel / Putz (Kandidaten) | Fugenraster bzw. leichte Körnung | Ruhrpott-Rot bzw. Weiß |

Die Strukturen sind dieselben parametrischen Materialfunktionen wie bei den Fassaden (Abschnitt 3). Pro Voxel werden nur **Material-ID + Farbindex** gespeichert (z. B. 1 Byte + 1 Byte aus einer Palette). Physikalische Werte wie die Bruchschwelle stehen in der Material-Tabelle (siehe Zerstörbarkeit).

### Baumaterial muss gekauft werden

- **Normale Spieler kaufen jedes Baumaterial im Baumarkt.** Material ist ein Inventar-Gegenstand mit Menge (Voxel je Material). Setzen verbraucht Material, Entfernen gibt einen Teil zurück (z. B. 50 %, Glas geht beim Abbau kaputt).
- Farben für den Pinsel werden ebenfalls gekauft, als Farbeimer mit begrenzter Reichweite.
- Ohne Material bleibt das Werkzeug gesperrt. Der Baumodus zeigt vorher an, wie viel Material ein Vorhaben braucht.
- **Bauamt und Bauhof** bauen auf öffentlichem Grund mit Material aus einem öffentlichen Lager, bezahlt aus der Stadtkasse. Die Stadtkasse ist Teil der Wirtschaft (Gebühren, Knöllchen, Steuern).
- Das hält die Wirtschaft geschlossen: Baumärkte haben echte Kundschaft, und große Bauten kosten echtes Spielgeld.

### Kaufbare Objekte

Was in Bau-, Super- und Elektronikmärkten gekauft wird, landet im Inventar und lässt sich im Baumodus platzieren:
- **Baumarkt:** Baumaterial (Pflicht für jeden Bau, siehe oben), Farben für den Pinsel, Werkzeug, Gartenmöbel
- **Elektronikmarkt:** Fernseher, Computer, Konsole, Musikanlage, Licht. Manche Geräte haben Funktionen (Computer für Hacking-Missionen, Licht als echte Lichtquelle)
- **Supermarkt:** Nahrungsmittel und Getränke für Vitalwerte, Vorrat im Kühlschrank zu Hause

Objekte sind eigene Modelle mit Position, keine Voxel. So bleiben sie beweglich und können Funktionen haben.

### Rechte

| Wer | Darf ändern |
|---|---|
| Eigentümer | Eigenes Gebäude und Grundstück, innen und außen |
| Mieter | Innenräume. Außen nur, wenn der Vermieter es erlaubt |
| Bauamt-Bedienstete | Öffentlichen Grund (Straßen, Plätze, Parks, öffentliche Gebäude) |
| Bauamt mit Freigabe einer höheren Instanz | Auch Besitz einzelner Spieler (Abriss, Umbau, Enteignung) |

- Die höhere Instanz ist eine ranghöhere Spielerrolle (z. B. Bauamtsleitung) oder ein Admin. Jede Freigabe wird protokolliert und ist für den betroffenen Spieler einsehbar.
- Grundstücksgrenzen kommen aus offenen Katasterdaten (ALKIS, Verfügbarkeit prüfen) oder werden aus Gebäudegrundrissen und Straßen abgeleitet.

### Technik: Gebäude änderbar machen

Das ist der schwierige Teil. Gebäude entstehen eigentlich deterministisch aus dem Generator. Sobald jemand baut, gilt:

1. **Materialisieren:** Beim ersten Eingriff wird das generierte Gebäude als eigenes **Voxel-Objekt** gespeichert, unter seiner Gebäude-ID. Ab dann ist diese gespeicherte Version die Quelle, nicht mehr der Generator.
2. **Änderungen als Deltas:** Weitere Bauaktionen werden als Deltas zu diesem Objekt gespeichert. Das ermöglicht Rückgängig, Protokoll und Rücksetzen.
3. **Konflikte mit Generator-Updates:** Ändert sich der Generator oder ein Override für ein materialisiertes Gebäude, wird es **nicht automatisch überschrieben**. Das Gebäude wird markiert, und der Eigentümer bzw. das Bauamt entscheidet, ob es neu generiert wird.
4. **Fassade nach dem Umbau:** Die Fassaden-Grammatik gilt nur für unveränderte Gebäude. Umgebaute Bereiche nutzen Material + Farbe pro Voxel.
5. **LOD:** Materialisierte Gebäude brauchen eigene vereinfachte Fernmodelle. Die werden nach dem Bauen im Hintergrund neu berechnet.

Spieler-Bauten sind **keine Overrides**. Sie liegen in der Delta-Ebene und lassen sich jederzeit zurücksetzen. Der Override-Layer (Abschnitt 9) bleibt für geprüfte, dauerhafte Korrekturen der generierten Welt.

### Zerstörbarkeit (später, aber jetzt schon vorbereitet)

Gebäude und Objekte sind zerstörbar, aber nur bei genug Kraft. Jedes Material hat eine **Schwelle**. Darunter passiert nichts (höchstens optische Spuren), darüber wird abhängig von der Kraft zerstört.

| Material | Schwelle (relativ) | Verhalten über der Schwelle |
|---|---|---|
| Glas | Sehr niedrig | Splittert sofort, auch durch Schüsse oder Würfe |
| Holz | Niedrig–mittel | Bricht und splittert |
| Ziegel / Putz | Mittel–hoch | Bröckelt, Löcher, einzelne Steine fallen |
| Beton | Hoch | Nur durch große Energie, bricht in Brocken |
| Metall | Hoch | Verbeult erst, reißt bei sehr großer Energie |

**Ergebnis:**
- Spieler können fremde Gebäude **nicht einfach einreißen**. Fäuste, Werkzeuge und normale Waffen bleiben unter den Schwellen von Mauern (Glas ausgenommen).
- **Große Ereignisse** liegen darüber: ein explodierendes Auto, Sprengstoff, ein Lkw oder ein Auto mit 150 km/h. Zum Vergleich: Ein Auto mit 1,5 t bei 150 km/h trägt etwa 1,3 MJ Bewegungsenergie.
- Bei einem Aufprall verteilt sich die Energie auf die getroffenen Voxel und wird dabei aufgezehrt. Ein schnelles Auto bricht durch eine Holzwand, bleibt aber in einer Betonwand stecken.

**Was jetzt schon in der Basis offen gehalten wird:**
1. **Material-Tabelle mit physikalischen Werten** (Schwelle, Zähigkeit, Dichte) statt nur Optik. Pro Voxel reicht weiter die Material-ID, die Werte kommen aus der Tabelle.
2. **Zerstörung ist ein eigener Delta-Typ**, mit Ursache (Spieler, Fahrzeug, Explosion), Zeit und Region. So kann der Bauhof sie gezielt reparieren, und eine Versicherung oder ein Rücksetzen nach Zeit ist später möglich.
3. **Schaden pro Voxel optional:** Ein Feld für Teilschaden (angeknackst, gerissen) ist im Format vorgesehen, wird aber anfangs nicht genutzt.
4. **Generierte Gebäude werden bei Zerstörung materialisiert**, genau wie beim ersten Umbau. Es gibt also nur einen Weg, wie Gebäude vom Generator getrennt werden.
5. **Physik-Ereignisse** (Aufprall, Explosion) liefern immer Energie und Trefferpunkt, auch wenn anfangs nichts zerstört wird. Dann muss später nur die Auswertung ergänzt werden.

Später: Statik (frei schwebende Teile stürzen ein), Trümmer als physikalische Objekte, Brand.

## 8. Multiplayer und Server-Architektur

Ganz NRW als eine zusammenhängende Welt mit möglichst vielen gleichzeitigen Spielern. Ein einzelner Server schafft das nicht. Die Karte wird deshalb auf viele Server verteilt.

### Aufbau

```
                    ┌──────────────────────┐
                    │  Koordinator (Main)  │  Aufteilung, Lastverteilung,
                    └──────────┬───────────┘  Übergaben, Server-Liste
          ┌────────────────────┼────────────────────┐
   ┌──────┴──────┐      ┌──────┴──────┐      ┌──────┴──────┐
   │ Regionsserver│ ⇄  │ Regionsserver│ ⇄  │ Regionsserver│  Simulation
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          └──────────── Client: verbunden mit aktueller + umliegenden Regionen

   Globale Dienste (getrennt): Konten, Inventar, Wirtschaft/Märkte, Chat, Wetter
   Datenbanken: Zwischenlayer (PostGIS), Deltas/Gebäude (Key-Value)
```

- **Koordinator:** Teilt die Karte in Regionen auf und weist sie Regionsservern zu. Er simuliert selbst nichts und ist damit kein Flaschenhals.
- **Regionsserver:** Autoritativ für alles in ihrer Region (Spieler, Fahrzeuge, NPCs, Bauen). Sie schreiben Deltas in die gemeinsame Datenbank.
- **Globale Dienste:** Alles, was nicht an einen Ort gebunden ist, läuft getrennt von den Regionen. Ein Geldbetrag darf nicht doppelt existieren, nur weil ein Spieler gerade die Region wechselt.

### Aufteilung der Karte

- Regionen bestehen aus **ganzen Kacheln** (256 m), damit Weltdaten und Zuständigkeit zusammenpassen.
- **Dynamisch nach Spielerdichte** statt festem Raster, z. B. als Quadtree: Die Dortmunder Innenstadt wird in viele kleine Regionen geteilt, das Sauerland bleibt eine große Region. Leere Regionen werden zusammengelegt.
- Aufteilen und Zusammenlegen passieren im laufenden Betrieb. Dabei wechselt nur die Zuständigkeit, die Daten liegen ohnehin in der Datenbank.

### Client-Verbindungen

- Der Client ist immer mit seiner **aktuellen Region und allen umliegenden** verbunden.
- 1 + 4 reicht nur an Kanten. An Ecken grenzen bei einem Raster 8 Regionen an, bei dynamischer Aufteilung auch mehr oder weniger. Deshalb gilt: **verbunden mit allen Regionen innerhalb des Sicht- bzw. Interessenradius**, typischerweise 1 + 3 bis 1 + 8.
- Von Nachbarregionen bekommt der Client nur, was in seinem Radius liegt, und nur lesend. Gesteuert wird immer über die aktuelle Region.

### Grenzen und Übergaben

- **Randzone:** Regionen tauschen Objekte nahe der Grenze untereinander aus (Ghost-Objekte). So sehen und treffen sich Spieler über die Grenze hinweg.
- **Übergabe der Zuständigkeit:** Fährt ein Fahrzeug über die Grenze, übernimmt die neue Region mit einem klaren Handover-Protokoll. Bei 55 m/s muss das ohne Ruckeln gehen, deshalb wird mit etwas Überlappung (Hysterese) übergeben, damit niemand an der Grenze hin- und herspringt.
- **Interaktionen über die Grenze** (Schuss, Kollision) entscheidet die Region des Verursachers, die Zielregion wendet das Ergebnis an.
- **Globale, eindeutige IDs** für alle Objekte, von Anfang an.

### Weiterhin gilt

- Fahrzeuge laufen mit Client-Prediction.
- Zerstörung und Umbau werden als Deltas zum Grundzustand übertragen und gespeichert.

### Einstieg

Am Anfang läuft alles auf einem Rechner: ein Koordinator, ein Regionsserver. Protokoll, IDs und Übergaben werden aber gleich so gebaut, dass später mehrere Regionsserver möglich sind. Nachrüsten wäre deutlich teurer.

## 9. Nachbesserbarkeit für schwierige Bereiche

Automatische Generierung wird an vielen Stellen schlecht aussehen: Autobahnkreuze, Brücken, Stadien, Hochöfen, Fördertürme, Bahnhöfe. Die Struktur muss erlauben, diese Bereiche gezielt nachzubessern, ohne den Rest anzufassen.

### Override-Layer

Zwischen Zwischenlayer und Voxelisierung liegt ein **Override-Layer** mit handgepflegten Korrekturen. Er ist versioniert und liegt im Repo, nicht nur in der Datenbank.

- **Daten-Overrides:** Attribute des Zwischenlayers korrigieren (Gebäudehöhe, Dachtyp, Fassaden-Parameter, Straßenbreite).
- **Spezial-Generatoren:** Für bestimmte Objekttypen oder Gebiete übernimmt ein eigener Generator (z. B. `Autobahnkreuz`, `Brücke`, `Förderturm`). Er wird über Tags oder Polygone registriert, die Standard-Generatoren sind nur der Fallback.
- **Handgebaute Assets:** Voxelmodelle für Landmarken (Dortmunder U, Zeche Zollverein), die an einer Stelle eingesetzt werden.
- **Render-Profile:** Lokale Einstellungen für Licht, Nebel, Mood, LOD-Distanzen, Spezial-Shader. Ein Gebiet kann einen eigenen Render-Pfad bekommen, ohne dass der globale Renderer sich ändert.

### Versionierung und Neu-Generierung

- Jede Kachel speichert die **Generator-Version** und den Hash der verwendeten Overrides.
- Ändert sich ein Generator oder Override, werden nur die betroffenen Kacheln ungültig und neu erzeugt. Clients verwerfen ihren Cache für diese Kacheln.
- **Spieler-Deltas** (Zerstörung, Umbau, Mietobjekte) hängen an stabilen IDs (Gebäude-ID, Straßen-ID) und nicht nur an Voxel-Koordinaten. So überleben sie eine Neu-Generierung.

### Werkzeuge

- Debug-Ansicht im Client: Welcher Generator, welche Overrides und welches Render-Profil gelten hier?
- Meldefunktion („sieht falsch aus“) mit Position, als Arbeitsliste für Nachbesserungen.

## 10. Was fire leisten muss

Das Projekt soll die Sprache in allen Bereichen belasten:

- Nebenläufigkeit: Generierungs-Worker, Server-Tick, Streaming
- Verteilte Systeme: Regionsserver, Übergaben, Koordinator, globale Dienste
- Netzwerk-I/O: Spielerprotokoll, Datenbankanbindung
- GPU-Anbindung: Rendering, ggf. Compute für Meshing
- Speicherlayout: dichte Voxel-Daten, Bricks, Kompression
- Serialisierung: Zwischenlayer, Deltas, Netzwerkpakete
- Werkzeuge: Import der Geodaten, Fassaden-Tool
