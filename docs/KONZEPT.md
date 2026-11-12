# Konzept: Ruhrpott-Raser

## 1. Voxel-Größe und Fahren

- **Voxelgröße 25 cm** (1/4 Minecraft). Pro Volumen sind das 64× mehr Voxel als bei Minecraft.
  - Chunks/Bricks deshalb größer wählen (z. B. 64³ = 16 m Kantenlänge).
  - LOD ist ab Tag 1 Pflicht.
- **Diagonale Höhen-Schnitte:** Ein Voxel darf oben schräg abgeschnitten sein. Die Oberseite ist über **vier Eckhöhen** definiert, quantisiert in 1/4-Voxel-Schritten (6,25 cm).
  - Benachbarte Voxel teilen sich die Eckhöhen. So entstehen durchgehende, lückenlose Flächen ohne Treppen.
  - Straßen, Rampen, Böschungen und Dächer sind damit direkt im Voxelmodell abbildbar.
  - Speicher: 4 × 2 Bit = 1 Byte zusätzlich pro geschnittenem Voxel (nur Oberflächen-Voxel, Rest bleibt voller Würfel).
  - Später möglich: diagonale Schnitte im Grundriss (Viertelkeile) für schräge Fassaden und Bordsteine.
- **Fahrphysik auf derselben Geometrie:** Das Kollisionsmesh für Fahrzeuge entsteht aus denselben geschnittenen Voxeln wie die Optik. Was man sieht, ist auch das, worauf man fährt. Wo Fahrzeuge ganz glatte Flächen brauchen (Autobahn, enge Kurven), darf ein Override-Mesh aus dem Zwischenlayer einspringen (siehe Abschnitt 8).

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

### Mond und Himmel

- **Mondphase und Mondstand astronomisch korrekt**, berechnet aus Datum und Uhrzeit.
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
- Render-Profile (Abschnitt 8) können pro Gebiet das Wetter lokal anpassen, z. B. Dampf an Hochöfen oder Nebel über dem Kanal.

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

Weitere Kandidaten: Werkstatt/Tuning, Waffenladen, Kiosk/Trinkhalle („Büdchen“), Krankenhaus, Apotheke, Fitnessstudio, Friseur/Kleidung, Pfandhaus, Polizeiwache.

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
- **Bauhof / Straßenmeisterei:**
  - Zerstörte Bereiche reparieren. Das setzt Spieler-Deltas zurück auf den generierten Grundzustand (Abschnitt 7).
  - Baustellen einrichten, Straßen sperren, Schnee räumen und streuen (Abschnitt 5)
  - Müllabfuhr, Wracks entfernen
  - Gemeldete Darstellungsfehler (Abschnitt 8) vor Ort prüfen und **Korrekturvorschläge** einreichen. Diese landen im Override-Layer, aber erst nach einer Prüfung.

Grundsatz: Spieler können nur Aktionen auslösen, die das Spiel auch selbst ausführen könnte. Bleibende Änderungen an der Welt (Override-Layer) werden immer erst geprüft.

**Glücksspiel und Echtgeld:** Die Spielwährung kann nicht mit echtem Geld gekauft werden. Sonst gelten für Spielothek und Casino Glücksspiel- und Jugendschutzregeln. Vor einem Release rechtlich prüfen.

## 7. Multiplayer

- Der Server ist autoritativ, Fahrzeuge laufen mit Client-Prediction.
- Interest-Management pro Kachel: Synchronisiert wird nur, was in der Nähe ist.
- Zerstörung und Umbau werden als Deltas zum deterministischen Grundzustand übertragen und gespeichert.

## 8. Nachbesserbarkeit für schwierige Bereiche

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

## 9. Was fire leisten muss

Das Projekt soll die Sprache in allen Bereichen belasten:

- Nebenläufigkeit: Generierungs-Worker, Server-Tick, Streaming
- Netzwerk-I/O: Spielerprotokoll, Datenbankanbindung
- GPU-Anbindung: Rendering, ggf. Compute für Meshing
- Speicherlayout: dichte Voxel-Daten, Bricks, Kompression
- Serialisierung: Zwischenlayer, Deltas, Netzwerkpakete
- Werkzeuge: Import der Geodaten, Fassaden-Tool
