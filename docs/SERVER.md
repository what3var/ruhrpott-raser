# Server: Stand M4 (autoritativ, Protokoll v2)

Wie Spieler, Launcher und Server zusammenspielen. Grundlage ist das Konzept, Abschnitt 8 (Koordinator, Regionsserver, globale Dienste) und
die Roadmap, M4. Hier steht, was jetzt gebaut ist und was später kommt.

```
 Launcher ──HTTP 7480──►┌──────────────────────── raser-server (ein Prozess) ────────────────────────┐
  (Konto, Updates,      │  LauncherApi (eigener Thread)   Konten + Sitzungen (SQLite, data/raser.db) │
   News, Status)        │                                                                            │
 Spiel ──TCP 7481──────►│  Gateway ─► Coordinator ─► RegionServer "ruhr-1"   (Hauptthread, 30 Takte/s)│
  (raser-game           │                │            Raser.SimWorld: Physik, Fahrzeuge, Inventar    │
   --server host:7481)  │                └──────────► globale Dienste: Uhr + Wetter, Chat, Befehle   │
                        └────────────────────────────────────────────────────────────────────────────┘
```

## Prozesse und Ports

| Teil | Jetzt | Später |
|---|---|---|
| Launcher-API (HTTP) | Port **7480**, Thread im Server | eigener Dienst hinter einem Reverse-Proxy mit TLS |
| Spielprotokoll (TCP) | Port **7481**, Gateway im Hauptthread | der Koordinator nimmt an und nennt dem Client seine Regionsserver (je eigener Port, z. B. 7490 ff.) |
| Koordinator | eine Klasse: alle Kacheln gehören zur Region 1 | eigener Prozess, teilt die Karte nach Spielerdichte (Quadtree aus ganzen Kacheln) |
| Regionsserver | einer (`ruhr-1`, Server-Nummer 1) | viele Prozesse, je Region einer, mit Randzone und Übergabe |
| Globale Dienste | Konten (SQLite), Uhr + Wetter, Chat | eigene Dienste; Inventar, Wirtschaft |

Die Teile sind schon getrennte Klassen (`LauncherApi`, `Accounts`, `Gateway`, `Coordinator`, `RegionServer`, `WorldClock`, `CommandRunner`) und reden
über Nachrichten, die Region und Kachel schon tragen. Teilen heißt später: die Aufrufe zwischen ihnen werden Nachrichten über das Netz.

Start:

```bash
raser-server [--data data] [--release release] [--admin name] [--http 7480] [--game 7481] [--time 14:00] [--weather klar] [--timescale 1]
             [--world world]
```

- `--data`: das Verzeichnis für die Datenbank (`raser.db`) und ggf. `news.json`.
- `--release`: der aktuelle Client-Build (alle Dateien darunter) und optional `version.txt` (erste Zeile Version, der Rest Hinweise) und `news.json`.
- `--admin name`: dieses Konto wird Admin (beim Start oder sobald es registriert wird). Ohne die Option wird das erste Konto Admin.
- `--world`: das Verzeichnis der Welt (die Kacheln unter `world/tiles`, nur das JSON des Zwischenlayers). Damit rechnet der Server mit
  Gebäuden, Pfosten und Durchfahrten, setzt Spieler auf die nächste Straße und parkt Fahrzeuge am Straßenrand. Ohne: eine leere Ebene.

## Konten, Sitzungen, Rollen

- Name: 3 bis 16 Zeichen aus `A-Z a-z 0-9 _ -`, ohne Rücksicht auf Groß- und Kleinschreibung eindeutig. Passwort: 6 bis 128 Zeichen.
- Passwort: PBKDF2-HMAC-SHA-256 (RFC 8018) mit 16 Byte Salz aus dem Zufall des Systems und 20 000 Runden, gespeichert als Hex mit Rundenzahl
  (später mehr Runden: die Zahl steht je Konto).
- Sitzung: 32 Zufallsbytes als Hex (`Net.SecureRandom`), 24 h gültig. In der Datenbank steht nur ihr SHA-256 - wer die Datei liest, kann sich
  damit nicht anmelden. Jede Anmeldung macht eine neue Sitzung; abgelaufene werden beim Start und bei jeder Anmeldung gelöscht.
- Rollen: `player` und `admin`. Admin ist eine Spalte des Kontos; `/admin name` macht ein weiteres Konto zum Admin. Geprüft wird immer auf dem Server.

## Launcher-API (HTTP, Port 7480)

Feste Schnittstelle für den Launcher. JSON in UTF-8, Fehler als `{"error": "..."}`.

| Anfrage | Antwort |
|---|---|
| `POST /api/register` `{"user": "...", "password": "..."}` | 200 `{"token": "...", "user": "...", "admin": false, "expires": "2026-11-18T12:00:00Z"}`; 409 Name vergeben; 400 ungültig |
| `POST /api/login` (dasselbe) | 200 wie bei register; 401 falsch |
| `GET /api/version` | 200 `{"version": "0.1.3", "notes": "...", "files": [{"path": "bin/game", "size": 12345, "sha256": "<hex>"}, ...]}` |
| `GET /files/<pfad>` | 200 die Bytes dieser Datei des Release (`..` wird abgelehnt), sonst 404 |
| `GET /api/news` | 200 `[{"date": "2026-11-17", "title": "...", "text": "..."}]` (`news.json` aus Release oder Daten, sonst `[]`) |
| `GET /api/status` | 200 `{"players": 0, "region": "ruhr-1", "uptime": 123}` (Sekunden) |

Der Launcher startet das Spiel mit `--server <host>:7481 --token <token> --user <name>`. Die Liste der Dateien (Größe, SHA-256) entsteht beim Start
des Servers; ein neuer Build heißt: Server neu starten.

## Spielprotokoll (TCP, Port 7481), Version 3

**Rahmen:** 2 Byte Länge (Little Endian), dann so viele Bytes Nachricht: 1 Byte Art, dann die Felder (`Raser.ByteWriter`: Varints, ZigZag für
Vorzeichen, Texte als Länge + UTF-8, `Float64` bitgenau). Lage in cm (UTM 32, Ost/Nord), Richtung in 1/100 Grad, Tempo in cm/s. Ein Client darf
höchstens 1 KiB je Rahmen schicken, der Server bis 64 KiB.

Der Server ist maßgeblich: der Client schickt keine Lagen mehr, nur seine **Eingaben je Takt** und **Operationen am Inventar**. Ein Client mit
Protokoll 1 oder 2 bekommt beim Hello ein Reject ("Protokoll 2 passt nicht, der Server spricht 3: bitte den Launcher aktualisieren."); eine State-Nachricht
(Lage wie in v1) wirft hinaus.

| Art | Richtung | Inhalt |
|---|---|---|
| 1 Hello | C → S | Protokollversion (2), Token, Name\|Client-Version, Fahrzeugart zum Start (0 zu Fuß, 1 Auto, 2 Transporter, 3 Motorrad, 4 Fahrrad), gewünschter Startpunkt (Ost, Nord) |
| 3 Chat | C → S | Text (höchstens 200 Zeichen) |
| 4 Command | C → S | Befehlszeile (`/kick name`) |
| 5 Bye | C → S | - |
| 6 Input | C → S | Folgenummer der ersten Eingabe, Anzahl (1 bis 8), je Eingabe: Gas 0..100, Bremse 0..100 (je 1 Byte), Lenkung, Gehen, Drehen (-100..100, ZigZag), Flags (Rückwärtsgang, Handbremse, Rennen, E = ein-/aussteigen) |
| 7 InvOp | C → S | Folgenummer, `Raser.InvOp` (Art 1 Move, 2 Swap, 3 Drop, 4 PickUp, 5 Öffnen eines Rucksacks am Boden, 6 Schließen, 7 Use; Quelle, Platz, Ziel, Platz, Anzahl, Gegenstand am Boden), davor die letzte Eingabe des Clients (der Server rechnet die Operation erst nach ihr) |
| 10 Welcome | S → C | Spieler-ID (global, `Raser.IdAllocator`), Region, Serverzeit (ms), Admin ja/nein, Name, Takte je s (30), Takt des Servers |
| 11 Reject | S → C | Grund (danach schließt der Server) |
| 12 Snapshot | S → C | Takt, Serverzeit, Region, die zuletzt gerechnete Eingabe, das eigene Bargeld (Cent); der eigene Spieler (bitgenau, `Float64`): Fahrzeug-ID, Lage, Richtung, Tempo, Schrittweg, Last; im Fahrzeug dessen ganzer Zustand (Art, Lage, Richtung, Tempo, Lenkeinschlag, Stoß, Schräglage, Zustand, Tank, Grip, rutscht); dann die **Entitäten** (neu oder geändert) und die IDs der **verschwundenen** |
| 13 Join | S → C | ID und Name eines Spielers (beim Eintritt an alle, beim Welcome die schon Anwesenden) |
| 14 Leave | S → C | ID |
| 15 Chat | S → C | Absender, Text, Art (0 Spieler, 1 System, 2 Antwort nur an diesen Client, 3 Fehler) |
| 16 Weather | S → C | Jahr, Tag, Uhrzeit (Minuten am Tag × 60, also Sekunden), Wetter (Name), Zeitraffer |
| 18 Kick | S → C | Grund (danach schließt der Server) |
| 20 InvSet | S → C | die zuletzt geprüfte Operation (Folgenummer) und ob sie angenommen ist, Taschenlampe an, Bargeld (Cent); die IDs der eigenen Behälter (Taschen, Hände, Rücken, Handy, Maus), des geöffneten Rucksacks am Boden und seines Gegenstands; alle Behälter, an die der Spieler kommt (`Container.Write`) |
| 22 Event | S → C | Art (1: Spieler umgehauen), um wen, Verursacher, Lage |

**Entitäten** (`Raser.Entity`, je Eintrag): ID, Art, Variante, Zustandsbits, Lage, Richtung, Tempo und zwei Zahlen `a`, `b` je nach Art -
von Anfang an allgemein, damit der Verkehr später ohne neue Nachricht hineinpasst:

| Art | Variante | Bits | a | b |
|---|---|---|---|---|
| 1 Spieler | - | 1 im Fahrzeug, 4 liegt (umgehauen), 16 Taschenlampe leuchtet | Fahrzeug-ID | - |
| 2 Fahrzeug (der Spieler, auch geparkt) | Fahrzeugart | 2 rutscht | Fahrer (Spieler-ID, 0 frei) | Schräglage in 1/10 Grad |
| 3 NPC-Auto | Art/Farbe (Verkehr) | Zustand, 8 steht | frei | frei |
| 4 Fußgänger | Aussehen (Verkehr) | 4 liegt, 8 steht | frei | frei |
| 5 Gegenstand am Boden | Art (`Raser.Items`) | - | Anzahl | data (ein Rucksack: sein Behälter) |

**Takt:** Server und Client rechnen mit festen **30 Takten je s** (`Raser.SimWorld.Tick`). Der Client schickt je Takt eine Eingabe (ein Rahmen
mit 13 Bytes); der Server schickt jedem Client jeden 2. Takt einen Snapshot (**15 je s**), dazu alle 10 s und bei jeder Änderung das Wetter.

**Interesse und Deltas:** Ein Snapshot enthält, was auf der Kachel des Spielers und den 8 Nachbarn ist: die anderen Spieler, alle Fahrzeuge
(ohne das eigene - das steht bitgenau im eigenen Zustand), die Gegenstände am Boden und die NPCs des Verkehrs (bis 200 m). Der Server merkt sich je Client den
Fingerabdruck jeder Entität (quantisiert, wie sie über die Leitung geht): Unverändertes geht nur alle 2 s noch einmal, was aus dem Interesse fällt
(oder verschwindet), steht in der Liste der verschwundenen. Gemessen (Bots, 2–3 Spieler, ein paar geparkte Fahrzeuge): **etwa 1,4 bis 3,5 KB/s
je Client vom Server, 0,4 KB/s zum Server** - ohne Verkehr. Mit Welt und Verkehr (10 bis 14 Autos, gut 30 Fußgänger in Sicht, die sich fast alle
in jedem Snapshot bewegen) sind es **etwa 21 bis 25 KB/s** je Client; da hilft später ein Delta gegen den letzten bestätigten Stand statt nur
"geändert ja/nein".

Ablauf: Der Client schickt Hello; der Server prüft Version und Token (Konto aus der Datenbank), setzt den Spieler in die Region und antwortet
Welcome, Weather, InvSet und die Joins - oder Reject. Ein zweiter Login desselben Kontos wirft den ersten hinaus.

**Prüfungen auf dem Server:** Hello innerhalb von 5 s, sonst zu. Unbekannte Art, zu langer Rahmen, Felder, die nicht passen (auch Eingaben
außerhalb der Grenzen), eine Lage (State, v1) oder etwas vor dem Hello: Kick. Eingaben: siehe unten (höchstens 30 je s gerechnet, Kick über 150
je s). Chat und Befehle: höchstens 5 auf einmal, dann einer je s; Text ohne Steuerzeichen, höchstens 200 Zeichen. Operationen am Inventar:
höchstens 20 je s. Wer 30 s nichts schickt, fliegt. Der Startpunkt aus dem Hello muss in der Region liegen (sonst der Standard); später kommt er
aus der Datenbank.

## Autoritative Simulation

Der Regionsserver rechnet die Welt mit **demselben Code wie der Client** (Bibliothek `Raser.Sim`): `Raser.Physics` (Fahrzeuge mit
`Raser.Vehicle.Step`, `Collide`, Schaden, Tank, Schräglage; Teilschritte von höchstens 0,5 m; Stöße zwischen Fahrzeugen mit `Vehicle.Shove`;
Gehen mit `Raser.Walker`; Aus- und Einsteigen), `Raser.Obstacles` (Grundrisse mit Durchfahrten und Pfosten der Kacheln - früher in
`client.fire`, dort bleibt `Obstacles` als dünne Unterklasse), `Raser.SimWorld` (Fahrzeuge mit IDs, `Control` = ein Takt eines Spielers mit
einer Eingabe, `Coast` = die Fahrzeuge ohne Fahrer rollen aus). Die Kacheln lädt der Server bei Bedarf (dort, wo Spieler sind) und vergisst alle
10 s die, auf denen und neben denen niemand ist.

- **Fahrzeuge** gehören der Region und haben IDs (`Raser.IdKind.Vehicle`): beim Eintritt bekommt der Spieler eines der gewünschten Art (auf der
  nächsten Straße, er sitzt darin), auf jeder Kachel, die ein Spieler zuerst betritt, parkt der Server bis zu 6 am Straßenrand
  (`Raser.Physics.Parking`). E (Flag in der Eingabe, gewechselt bei der Flanke) steigt im Stand aus bzw. in das nächste freie Fahrzeug (3,5 m)
  ein. Geht der Spieler, bleibt sein Fahrzeug stehen; das für ihn erzeugte verschwindet, wenn niemand darin sitzt.
- **Eingaben:** je Spieler eine Warteschlange (höchstens 32; nur neuere Folgenummern). Je Takt bekommt jeder Spieler ein Guthaben von einer
  Eingabe (höchstens 8 angespart): nach einer Lücke im Netz holt der Server bis zu 8 auf einmal nach, aber über die Zeit nie mehr als 30 je s -
  wer schneller schickt, fährt nicht schneller (die Bots messen das: doppelt so viele Eingaben, dieselbe Strecke). Über 150 Eingaben je s: Kick.
  Werte außerhalb der Grenzen (Gas 101, Flags 16 ...) lehnt schon `Raser.Wire` ab: Kick.
- **Spieler gegen Fahrzeug:** zu Fuß hält ihn das Fahrzeug auf (`Physics.Walk`); erwischt ihn eines mit mehr als 5 m/s, ist er **umgehauen**
  (`RegionServer.KnockedDown(Opfer, Verursacher, Fahrzeug)`: er liegt 3 s, die Eingaben zählen nicht, alle in der Nähe bekommen das Ereignis).
  Was er verliert, entscheidet der Server mit `Raser.Knockdown.Apply` (Raser.Core: Inventar zu Boden, ein Teil des Kleingelds, Kaputtes; der
  Zufall aus Takt und ID); er bekommt danach den neuen Stand seines Inventars.
- **Verkehr:** `RegionServer.Npcs()` rechnet in jedem Takt nach den Spielern und vor den freien Fahrzeugen `Traffic.Step` um alle Spieler,
  `RegionServer.NpcEntities(p, list)` gibt die NPCs in der Nähe von p in die Snapshots (Entitäten 3 und 4) - siehe "Verkehr und Fußgänger".

## Vorhersage, Abgleich, Interpolation (Client)

- **Vorhersage** (`Raser.Prediction` in Raser.Net): der Client rechnet jede Eingabe sofort mit `SimWorld.Control` - dieselben Kacheln, dieselbe
  Rechnung, die Eingaben als ganze Zahlen (Hundertstel), also bitgleich zum Server. Die Eingaben bleiben gemerkt, bis ein Snapshot sie
  bestätigt (höchstens 4 s).
- **Abgleich:** mit jedem Snapshot setzt der Client den eigenen Spieler (und sein Fahrzeug) auf den bitgenauen Zustand des Servers, die anderen
  Fahrzeuge auf ihren letzten Stand vom Server, und rechnet die noch offenen Eingaben noch einmal. Der Unterschied zur Vorhersage davor ist der
  Fehler: bis 4 m läuft die Anzeige mit einem Versatz weiter, der mit einer Zeitkonstante von 50 ms schwindet (nach ~100 ms fast weg), darüber
  (ein `/tp`, ein Fahrzeug, das ein anderer schon genommen hat) springt sie. Zwischen zwei Takten wird die Anzeige zwischen den letzten beiden
  Lagen geglättet. Ohne Abweichung (allein auf der Straße) ist der Fehler genau 0 - die Bots drucken den größten.
- **Interpolation** (`Raser.Interpolator`, `Raser.ServerClock`): die anderen zeigt der Client 100 ms in der Vergangenheit, zwischen den beiden
  Snapshots davor und danach (Richtung über 180° hinweg); fehlt der nächste, geht es mit dem Tempo bis 0,25 s weiter. Die Uhr des Servers kommt
  aus den Takten der Snapshots (geglättet; frühe Snapshots ziehen schneller).
- Im Spiel: `Online.Control` (main.fire ruft es am Server statt der eigenen Physik) schickt die Tasten in Takten und legt die Lage der Vorhersage in
  Wagen und Spieler; die Fahrzeuge des Servers (auch das eigene) und die anderen Spieler zeigt `Online.Drive`.

## Befehle

Befehle beginnen mit `/` (im Chat oder in der Konsole des Spiels, Taste `^`). Die Antwort geht nur an den, der gefragt hat.

| Befehl | Wer | Wirkung |
|---|---|---|
| `/help` | alle | die Befehle, die man selbst darf |
| `/players` | alle | wer da ist (mit Kachel) |
| `/kick <name>` | Admin | wirft den Spieler hinaus |
| `/say <text>` | Admin | Systemnachricht an alle |
| `/time <HH:MM>` | Admin | stellt die Uhr der Welt |
| `/weather <wetter>` | Admin | klar, wolkig, bedeckt, niesel, regen, starkregen, dunst, nebel, dichter-nebel |
| `/tp <name>` | Admin | springt zu dem Spieler |
| `/admin <name>` | Admin | macht das Konto zum Admin |

Unbekannt oder nicht erlaubt: eine Fehlermeldung an diesen Client.

## Uhr und Wetter

Der Server ist für Uhr und Wetter maßgeblich (`WorldClock` mit `Raser.Weather` aus Raser.Core): Datum und Uhrzeit laufen mit dem Zeitraffer
(`--timescale`, 1 = Echtzeit), das Wetter ist ein Preset. Die Clients übernehmen beides und stellen die eigenen Tasten (T/G/R) zurück, sobald der
Server das nächste Mal schickt.

## Verkehr und Fußgänger

Im Mehrspieler simuliert der Server alle NPCs (Autos und Fußgänger), die Clients zeichnen nur, was in den Snapshots kommt. Offline (ohne
`--server`) rechnet das Spiel selbst mit demselben Code. Die Simulation steckt in der Bibliothek `src/Raser.Traffic` (Import
`raser.traffic`, Referenzen: Raser.Core, Raser.World, Raser.Mesh - alle ohne scene3d): `Raser.RoadGraph` (Spurgraph aus den Straßen der
Kacheln) und `Raser.Traffic` (Simulation). Die Simulation hat keine Uhr und keine Threads (nur der Bau des Graphen läuft in einem Worker, siehe 2.), Zufall nur aus Seeds (`Raser.TrafficRandom`, je Auto und Fußgänger
eigener): derselbe Seed, dieselben Kacheln und dieselben Eingaben geben dasselbe Ergebnis. Der Graph wird nach Straßen-ID sortiert gebaut -
die Folge, in der Kacheln kommen, ändert nichts.

**Im Regionsserver** (`RegionServer` in `src/Raser.Server/world.fire`, eingebaut; `raser-server --traffic 24 --people 30 --traffic-seed 1`,
`--traffic 0 --people 0` schaltet ab, ohne `--world` gibt es keinen Verkehr):

1. Start: `RegionServer.SetTraffic(autos, fussgaenger, seed)` legt ein `Raser.Traffic` an. Die IDs der NPCs sind Laufzeit-IDs der Art
   `IdKind.Npc` dieses Servers (`traffic.idBase`, darüber zählt die Simulation hoch) - sie stoßen nie mit Spielern, Fahrzeugen oder
   Gegenständen zusammen. Die Höchstzahlen gelten je Spieler-Umkreis: Autos erscheinen 80 .. 250 m, Fußgänger 40 .. 150 m um *jeden*
   Spieler und verschwinden über 300 bzw. 190 m von *allen*.
2. Kacheln und Graph (`FeedTraffic`, je Takt): ändert sich die Menge der 3 x 3 Kacheln um alle Spieler, bestellt der Server den Graphen beim
   Worker (`Raser.GraphWorker`, ein eigener Thread mit `fire dedicated`): der lädt die Kacheln selbst (`FileTileStore.Load`, dieselben Dateien
   `<world>/tiles/<x>_<y>.json` mit Grünstreifen und Höhen), hält je Kachel ihre Straßen zwischengespeichert, fügt die gewünschten sortiert
   zusammen und baut (9 Kacheln: 100 .. 400 ms im Worker). Der Takt läuft weiter; der Verkehr fährt auf dem alten Graphen. **Übernommen**
   (`Traffic.Adopt`, dann findet jeder NPC seine Spur wieder) wird genau `TrafficDelay` = 90 Takte (3 s) nach der Bestellung - ist der Graph
   dann noch nicht fertig, wartet der Takt dort auf ihn (das Log sagt wie lange). Damit hängt der Verkehr nicht vom Timing des Threads ab:
   dieselben Eingaben geben denselben Verkehr. Der Graph hängt nur von der Menge der Kacheln ab (nicht von früheren Aufträgen) - derselbe wie
   synchron (Test `WorkerTests`).
3. Je Takt (`Npcs`, nach den Eingaben der Spieler und `Knocks`, vor `Coast`): `traffic.wetness` aus dem Wetter der Uhr, dann
   `traffic.Step(1/30 s, spieler)`. `spieler` ist eine `List<float>` mit 7 Zahlen je Eintrag: Ost, Nord, Richtung (Grad, vorwärts (-sin, cos)),
   Tempo (m/s), Radius (m), spread (m, zwei Kreise davor und dahinter wie `Raser.Vehicle`), Art (0 zu Fuß, 1 Fahrzeug mit Fahrer, 2 Fahrzeug
   ohne Fahrer). Eingetragen werden alle Spieler zu Fuß und alle Fahrzeuge der Welt.
4. Stöße: fährt ein Fahrzeug (Art 1) mit mehr als 0,5 m/s in ein NPC-Auto, rechnet `Traffic.Impacts` den Stoß (unelastisch, Schaden wie
   `Raser.Vehicle`): das Auto wird ein Unfallwagen (rutscht aus, hupt, fährt nach 6 s weiter; kaputt bleibt es stehen). Fußgänger, die ein
   Fahrzeug über 1,5 m/s erwischt, fallen um (liegen 9 s). Danach prallt in `Npcs` jedes Fahrzeug an den NPC-Autos ab (`Vehicle.Collide`),
   Spieler zu Fuß hält ein NPC-Auto auf (`Walker.Avoid`). Die Vorhersage des Clients kennt die NPCs nicht: ein Aufprall wird beim Abgleich
   korrigiert. Wände für Unfallwagen prüft der Server noch nicht (offline: `TrafficView.Simulate`).
5. Snapshot je Spieler (`NpcEntities`): `traffic.States(liste, ost, nord, 200.0)` füllt `Raser.NpcState` für die NPCs bis 200 m (die Objekte
   gehören der Simulation und werden beim nächsten Aufruf überschrieben), daraus die Entitäten:

| Feld der Entität | NPC-Auto (Art 3) | Fußgänger (Art 4) |
|---|---|---|
| variant | Art (0 Auto, 1 Transporter) + 4 x Lack (0xRRGGBB) | Hemd + Hose x 2^24 + (Größe in cm - 100) x 2^48 |
| bits | 1 hupt, 8 steht, + 16 x Zustand (0 fährt, 1 steht, 2 Unfall, 3 kaputt) | 4 liegt, 8 steht, + 16 x Zustand (0 geht, 1 wartet, 4 liegt, 5 springt zur Seite) |
| Lage, Richtung, Tempo | wie jede Entität (cm, 1/100 Grad, cm/s) | |
| a | 0 | Haare + Haut x 2^24 |
| b | auf einer Brücke die Höhe (cm über NHN), sonst 0 | ebenso |

   Hin und zurück: `NpcState.EntityType`, `Variant`, `Bits`, `A`, `B` und `NpcState.FromEntity` (Raser.Traffic kennt Raser.Net nicht: die Zahlen
   der Arten stehen dort noch einmal). Ein NPC kostet etwa 25 .. 35 Byte; fahrende ändern sich jeden Snapshot (15 je s): mit 24 Autos und 30
   Fußgängern im Umkreis gut 20 KB/s je Client (gemessen: siehe Bots). Später: nur Spur und s schicken (die Lage folgt aus dem Graphen, den
   auch der Client baut) und das Aussehen nur beim ersten Mal.
6. Client: `Online.NpcStates()` macht aus den Entitäten 3 und 4 Zustände, interpoliert wie die anderen Entitäten (`Raser.Interpolator`, 100 ms
   in der Vergangenheit), den Schritt der Fußgänger zählt der Client; `TrafficView.Remote` zeichnet sie (main.fire ruft das am Server statt
   `Update`) und meldet Unfall, Sturz und Hupen am Wechsel der Zustände. Offline: `TrafficView.Update` (eigene Simulation + `States` + dieselbe
   Darstellung). Für einen anderen Transport gibt es auch `NpcState.Encode/Decode` und `Raser.NpcBuffer` (ungenutzt, mit Tests).
7. Probe: `tools/server-smoke.sh` mit Welt lässt in Runde 3 zwei Bots am selben Ort stehen; beide drucken alle 2 s die NPCs (ID, Lage in cm)
   zum selben Takt - das Skript vergleicht sie.

**Brücken:** Straßen und Bahnen mit OSM `layer` > 0 (Tunnel nimmt der Import nicht auf, Treppen bleiben am Boden) haben ein Deck
(`Raser.Bridges` in Raser.World - dieselbe Rechnung für Netz, Verkehr und Fahrphysik, auf dem Server wie im Client): je Meter die Höhe der
Oberkante, das Höchste aus Gelände + 15 cm, der Geraden zwischen den Enden (schließen beide an eine Straße der Ebene 0 an) und je Kreuzung mit
einer Straße oder Bahn darunter deren Gelände + lichte Höhe (Fahrbahn 4,5 m, Bahn 5,5 m, Fußweg 2,8 m) + 0,8 m Deck, zu den Seiten fallend
(8 % / 3,5 % / 12 %). Gezeichnet wird es als Netz (`Raser.BridgeMesher`: Belag, Unterseite, Brüstungen bzw. Geländer, Pfeiler alle 15 m wo
das Deck über 1 m hoch liegt und nicht auf einer Fahrbahn darunter, Widerlager an hohen Enden), nah und fern; das Gelände trägt den Belag der
Brücke nicht mehr. Der Verkehr: Knoten nur zwischen Straßen derselben Ebene (außer an den Enden), Spuren mit der Höhe des Decks, NPCs darauf
(`NpcState.z`, Entität `b` in cm) kümmern sich nur um ihre Ebene; erscheinen tut auf Brücken nichts.

**Spieler auf Brücken** (`Raser.Sim`): Fahrzeug und Spieler haben `bridge` (die ID der Brücke, 0: Gelände). Auf ein Deck kommt man nur an
seinen Enden (wo es höchstens 0,7 m über dem Gelände liegt: `Obstacles.Level`), darauf halten die Brüstungen (`Obstacles.PushBridge`), unten
fährt man durch; wo ein Deck niedrig ist (unter 2,5 m), ist seine Seite von unten eine Wand, die Pfeiler halten auf. Fahrzeuge stoßen nur
mit Fahrzeugen derselben Ebene zusammen. Im Protokoll (Version **3**) steht `bridge` im eigenen Zustand (Spieler und Fahrzeug, bitgenau wie der
Rest); andere Spieler und Fahrzeuge tragen das Bit `OnBridge` (16), der Client nimmt dann die höchste Brücke an ihrer Stelle
(`Obstacles.DeckUnder`). Die Höhe im Bild: `Ground.AtLevel` (Deck oder Gelände).

## Persistenz

Jetzt: SQLite-Datei `data/raser.db` mit den Tabellen `accounts` (id, name, salt, hash, rounds, admin, created, cash) und `sessions` (Hash des Tokens,
Konto, Ablauf). Spielerlagen werden noch nicht gespeichert. Später: Konten und Inventar in einer gemeinsamen Datenbank der globalen Dienste,
Deltas der Welt im Key-Value-Store (Konzept, Abschnitt 8).

## Inventar über den Server

Das Inventar (`Raser.Inventory` in Raser.Core, siehe [INVENTAR.md](INVENTAR.md)) führt der Regionsserver: ein Speicher für alle Behälter und
die Gegenstände am Boden der Region, IDs aus seinem `Raser.IdAllocator` (`Raser.IdKind.Item`), je Spieler ein `Inventory` darauf (Anfangsausstattung
wie offline). Nach dem Welcome schickt er `InvSet` mit den Behältern des Spielers.

- Der Client wendet eine Operation sofort an (vorhergesagt: das Fenster, F, B im Spiel) und schickt sie mit Folgenummer (`InvOp`).
- Der Server prüft mit **demselben** `Inventory.Apply` - Lage und Reichweite aus seinem eigenen Stand des Spielers; Ablegen, Aufheben und Öffnen nur
  zu Fuß (und nicht, solange er liegt), höchstens 20 Operationen je s. Er antwortet immer mit `InvSet` (angenommen oder nicht, dazu der echte Stand
  aller Behälter, an die der Spieler kommt). Der Client übernimmt den Stand und wendet die noch offenen Operationen noch einmal an (wie bei der
  Bewegung).
- **Benutzen** (Art 7, `Inventory.Use`): essen und trinken (der Körper `Raser.Body` des Spielers auf dem Server), rauchen, Taschenlampe an/aus
  (leuchtet sie, trägt die Entität des Spielers Bit 16), Kanister und Schraubenschlüssel am nächsten Fahrzeug der Region (tanken, reparieren -
  das Fahrzeug des Servers, es geht mit dem nächsten Snapshot an alle).
- **Bargeld** (`Inventory.cash`, Cent): Geld am Boden wird beim Aufheben Bargeld. Der Server schickt es mit jedem InvSet und Snapshot und
  speichert es im Konto (Spalte `cash` der Tabelle `accounts`, sobald es sich ändert und beim Gehen); wer neu ist (-1), bekommt das Startgeld. (Die Behälter selbst
  werden noch nicht gespeichert: nach dem Neuanmelden gibt es die Anfangsausstattung.)
- **Umgehauen** (`Raser.Knockdown.Apply`, Samen vom Server): was der Spieler trägt, fällt zu Boden, ein Teil des Bargelds als Geldhäufchen,
  manches geht kaputt; die Gegenstände kommen als Entitäten in die Snapshots, der Betroffene bekommt sein Inventar neu (InvSet).
- Gegenstände am Boden sind Entitäten im Snapshot (Art 5). Den Inhalt eines Rucksacks am Boden bekommt nur, wer ihn öffnet (Operation 5) oder
  aufhebt; wer ihn offen hat, bekommt jede Änderung. Gegenstände erzeugt nur der Server.
- Probe (Bots): Anna fährt Bernd um, er verliert Bargeld und alles, was er trägt, Anna sammelt es auf; ihr Bargeld ist nach dem
  Neuanmelden noch da. Anna setzt ihren Rucksack mit Inhalt ab, Bernd setzt seinen ab, geht hin, hebt Annas auf und sieht den Inhalt (2 Wasser,
  Schraubenschlüssel).

## Jetzt gebaut - und später

| Jetzt | Später |
|---|---|
| ein Prozess, ein Regionsserver | Koordinator, mehrere Regionsserver, Randzone, Übergabe mit Hysterese |
| der Server rechnet alles aus Eingaben (30 Takte je s), Client mit Vorhersage und Abgleich, die anderen interpoliert | Kacheln in einem eigenen Thread laden (jetzt hält der erste Besuch einer Kachel den Takt kurz an); Startpunkt und Inventar speichern (jetzt wählt der Client den Startpunkt beim Hello) |
| Spieler gegen Fahrzeuge nur beim Gehen und beim Umhauen | Kollision Fahrzeug gegen Spieler mit Rückstoß; Verzögerungsausgleich (Lag Compensation) für Treffer |
| TCP mit eigenem Rahmen | UDP für Lagen, TCP für Zuverlässiges |
| HTTP ohne TLS | TLS (Reverse-Proxy oder `Http.Server.UseTls`), sonst gehen Passwort und Token im Klartext |
| keine Begrenzung der Anmeldeversuche | Sperre nach Fehlversuchen je Name und Adresse |
| Wetter aus Presets | Wetter per Seed, optional echtes DWD-Wetter |

## Code

| Projekt | Inhalt |
|---|---|
| `src/Raser.Traffic` | Spurgraph und Simulation von Autos und Fußgängern (`Raser.RoadGraph`, `Raser.Traffic`) - ohne Szene, mit Tests |
| `src/Raser.Sim` | die Simulation ohne Szene: `Raser.Obstacles`, `Raser.Physics`, `Raser.SimWorld`, `Raser.Pawn`, `Raser.Controls` |
| `src/Raser.Net` | das Protokoll (`Raser.Packet`, `Raser.Entity`, `Raser.Wire`, `Raser.FrameReader`, `Raser.Link`), Vorhersage und Interpolation (`Raser.Prediction`, `Raser.Interpolator`, `Raser.ServerClock`), Befehle (`Raser.Commands`), Passwörter (`Raser.Passwords`) - mit Tests |
| `src/Raser.Server` | `raser-server`: Launcher-API, Konten, Gateway, Koordinator, Regionsserver (Simulation, Snapshots, Inventar), Uhr und Wetter |
| `src/Raser.Client` | `NetSession` (Verbindung, Takt, Vorhersage, Entitäten, Inventar, Chat, Konsole), `ChatOverlay` |
| `src/Raser.Game` | `online.fire`: Steuerung über den Server, die Entitäten in der Szene; `--bot`: ein Client ohne Fenster mit Plänen (für Tests); `npcs.fire`: der Verkehr in der Szene |

Probe von Hand: `tools/server-smoke.sh <raser-server> <raser-game> [arbeitsverzeichnis] [welt]` startet den Server, registriert über HTTP,
verbindet Bots (`raser-game --bot 12 --plan kreis|ablegen|aufheben|schummeln --say "..."`) und prüft, dass sie sich sehen, den Chat lesen, dass
`/time` von einem Spieler abgelehnt wird und von einem Admin wirkt, dass ein falsches Token abgelehnt wird, dass der Server die Wagen nach den
Eingaben bewegt, dass `/tp` die Lage setzt, dass ein Rucksack mit Inhalt von einem Spieler zum anderen wandert, dass doppelt so viele Eingaben
nicht schneller machen und eine Lage wie in v1 hinauswirft; dazu druckt sie den größten Fehler der Vorhersage und die Bandbreite je Client.
