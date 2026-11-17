# Server: Stand M4 (Grundgerüst)

Wie Spieler, Launcher und Server zusammenspielen. Grundlage ist das Konzept, Abschnitt 8 (Koordinator, Regionsserver, globale Dienste) und
die Roadmap, M4. Hier steht, was jetzt gebaut ist und was später kommt.

```
 Launcher ──HTTP 7480──►┌──────────────────────── raser-server (ein Prozess) ────────────────────────┐
  (Konto, Updates,      │  LauncherApi (eigener Thread)   Konten + Sitzungen (SQLite, data/raser.db) │
   News, Status)        │                                                                            │
 Spiel ──TCP 7481──────►│  Gateway ─► Coordinator ─► RegionServer "ruhr-1"   (Hauptthread, 20 Hz)    │
  (raser-game           │                │            Spieler, Interesse je Kachel, Snapshots        │
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
```

- `--data`: das Verzeichnis für die Datenbank (`raser.db`) und ggf. `news.json`.
- `--release`: der aktuelle Client-Build (alle Dateien darunter) und optional `version.txt` (erste Zeile Version, der Rest Hinweise) und `news.json`.
- `--admin name`: dieses Konto wird Admin (beim Start oder sobald es registriert wird). Ohne die Option wird das erste Konto Admin.

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

## Spielprotokoll (TCP, Port 7481), Version 1

**Rahmen:** 2 Byte Länge (Little Endian), dann so viele Bytes Nachricht: 1 Byte Art, dann die Felder (`Raser.ByteWriter`: Varints, ZigZag für
Vorzeichen, Texte als Länge + UTF-8). Lage in cm (UTM 32, Ost/Nord), Richtung in 1/100 Grad, Tempo in cm/s. Ein Client darf höchstens 1 KiB je
Rahmen schicken, der Server bis 64 KiB.

| Art | Richtung | Inhalt |
|---|---|---|
| 1 Hello | C → S | Protokollversion, Token, Name, Client-Version |
| 2 State | C → S | Folgenummer, Kachel (x, y), Ost, Nord, Richtung, Tempo, Fahrzeugart (0 zu Fuß, 1 Auto, 2 Transporter, 3 Motorrad, 4 Fahrrad) |
| 3 Chat | C → S | Text (höchstens 200 Zeichen) |
| 4 Command | C → S | Befehlszeile (`/kick name`) |
| 5 Bye | C → S | - |
| 10 Welcome | S → C | Spieler-ID (global, `Raser.IdAllocator`), Region, Serverzeit (ms), Admin ja/nein, Name |
| 11 Reject | S → C | Grund (danach schließt der Server) |
| 12 Snapshot | S → C | Serverzeit, Region, je Spieler in der Nähe: ID, Kachel, Lage, Richtung, Tempo, Fahrzeugart |
| 13 Join | S → C | ID und Name eines Spielers (beim Eintritt an alle, beim Welcome die schon Anwesenden) |
| 14 Leave | S → C | ID |
| 15 Chat | S → C | Absender, Text, Art (0 Spieler, 1 System, 2 Antwort nur an diesen Client, 3 Fehler) |
| 16 Weather | S → C | Jahr, Tag, Uhrzeit (Minuten am Tag × 60, also Sekunden), Wetter (Name), Zeitraffer |
| 17 Teleport | S → C | Ost, Nord, Richtung: der Server setzt die Lage (z. B. `/tp`, unplausible Sprünge) |
| 18 Kick | S → C | Grund (danach schließt der Server) |

Ablauf: Der Client schickt Hello; der Server prüft Version und Token (Konto aus der Datenbank) und antwortet Welcome, Weather und die Joins - oder
Reject. Ein zweiter Login desselben Kontos wirft den ersten hinaus. Danach schickt der Client etwa 10-mal je Sekunde State, der Server 10-mal je
Sekunde jedem Client einen Snapshot der Spieler auf seiner Kachel und den 8 Nachbarkacheln (Interesse je Kachel), alle 10 s und bei jeder Änderung
das Wetter.

**Prüfungen auf dem Server:** Hello innerhalb von 5 s, sonst zu. Unbekannte Art, zu langer Rahmen, Felder, die nicht passen, oder etwas vor dem Hello:
Kick. State höchstens 30 je s (darüber wird verworfen, bei 100 je s Kick), Lage muss zur Kachel passen, Tempo bis 100 m/s, ein Sprung weiter als
das Tempo erlaubt (plus 20 m) wird nicht übernommen (Teleport zurück). Chat und Befehle: höchstens 5 auf einmal, dann einer je s; Text ohne
Steuerzeichen, höchstens 200 Zeichen. Wer 30 s nichts schickt, fliegt.

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
Kacheln) und `Raser.Traffic` (Simulation). Keine Uhr, keine Threads, Zufall nur aus Seeds (`Raser.TrafficRandom`, je Auto und Fußgänger
eigener): derselbe Seed, dieselben Kacheln und dieselben Eingaben geben dasselbe Ergebnis. Der Graph wird nach Straßen-ID sortiert gebaut -
die Folge, in der Kacheln kommen, ändert nichts.

**Einbinden im Regionsserver** (je Region ein `Raser.Traffic`):

1. Start: `var traffic = new Raser.Traffic(maxCars, maxPeople, seed)` - `maxCars`/`maxPeople` gelten je Spieler-Umkreis (Erscheinen
   80 .. 250 m bzw. 40 .. 150 m um *jeden* Spieler, verschwinden über 300 bzw. 190 m von *allen*). Vorschlag: 24 und 30.
2. Kacheln: der Server lädt für jeden Spieler die 3 x 3 Kacheln um ihn mit `Raser.FileTileStore.Load(key)` (dieselbe Datei wie der Client:
   `<world>/tiles/<x>_<y>.json`; Load setzt auch die Grünstreifen, die die Lage der Gehwege bestimmen) und gibt sie
   `traffic.graph.AddTile(tile)`. Kacheln, die kein Spieler mehr braucht: `traffic.graph.Keep(liste der Kachelnamen)`. Ist danach
   `traffic.graph.dirty`, einmal `traffic.graph.Build()` (9 Kacheln: rund 100 ms - am besten nach allen neuen Kacheln eines Ticks, oder in
   einem eigenen Thread mit einem zweiten Graphen, der dann getauscht wird). Die Kachel-Objekte braucht der Graph danach nicht mehr.
3. Je Tick (fest, z. B. 20 Hz): `traffic.wetness = wetter.wetness` und `traffic.Step(dt, spieler)`. `spieler` ist eine `List<float>` mit
   7 Zahlen je Eintrag: Ost, Nord, Richtung (Grad, vorwärts (-sin, cos)), Tempo (m/s), Radius (m), spread (m, zwei Kreise davor und dahinter
   wie `Raser.Vehicle`), Art (0 zu Fuß, 1 fährt ein Fahrzeug, 2 abgestelltes Fahrzeug). Für Fahrzeuge Radius und spread aus `Raser.Vehicle.Of(art)`
   (Auto 1,0 / 1,1 m), zu Fuß 0,35 / 0. Abgestellte Fahrzeuge der Spieler als Art 2 (die Autos fahren um sie herum). Was im Tick geschah,
   steht in `traffic.events` ("hup", "unfall", "umgefahren").
4. Stöße rechnet die Simulation selbst: fährt ein Spieler (Art 1) mit mehr als 0,5 m/s in ein Auto, wird es ein Unfallwagen (Physik mit
   `Raser.Vehicle`, rutscht aus, hupt, fährt nach 6 s weiter), läuft er einen Fußgänger um, fällt der (liegt 9 s). Den Abprall des
   Spielerfahrzeugs rechnet, wer die Fahrphysik des Spielers rechnet (Client mit Vorhersage bzw. Server), gegen die NPC-Zustände - wie es
   `TrafficView.Contact` im Spiel zeigt. Wände für Unfallwagen kennt die Simulation nicht: der Server prüft sie wie das Spiel mit den
   Gebäuden der Kacheln (`TrafficView.Simulate`, "Unfallwagen gegen die Wände") oder lässt es fürs Erste.
5. Snapshot je Spieler: `traffic.States(liste, ost, nord, 300.0)` füllt `Raser.NpcState` für alle NPCs im Umkreis (die Objekte gehören der
   Simulation und werden beim nächsten Aufruf überschrieben - gleich kodieren). Je NPC `state.Encode(writer)`:

| Feld | Kodierung | Inhalt |
|---|---|---|
| id | Varint | eindeutig je Simulation (zählt hoch) |
| Art + Zustand + Hupe | 1 Byte: Art + 4 x Zustand + 128 x hupt | Art 0 Auto, 1 Transporter, 2 Fußgänger; Zustand 0 normal, 1 steht/wartet, 2 Unfall, 3 kaputt, 4 liegt, 5 springt zur Seite |
| Ost, Nord | SignedVarint, cm | Lage (UTM 32) |
| Richtung | Varint, 1/100 Grad (0 .. 36000) | wie `Raser.Vehicle` |
| Tempo | SignedVarint, cm/s | |
| Farbe | Varint 0xRRGGBB | Lack bzw. Hemd |
| nur Fußgänger: Hose, Haare, Haut, Größe | Varint, Varint, Varint, Varint (cm) | Aussehen |

   Ein Auto braucht etwa 16 Byte, ein Fußgänger etwa 24; 24 Autos und 30 Fußgänger also rund 1,1 KB je Snapshot (vor einem
   Delta-Verfahren: das Aussehen ändert sich nie und könnte nur beim ersten Mal kommen). Lesen: `Raser.NpcState.Decode(reader)`.
6. Client: die Snapshots in `Raser.NpcBuffer.Push(serverzeit, liste)`, je Bild `Sample(bildzeit, liste)` mit der Bildzeit etwa 100 ms
   hinter dem neuesten Snapshot (Lage linear, Richtung auf dem kürzeren Weg, den Schritt der Fußgänger zählt der Client), dann
   `TrafficView.Remote(dt, liste, wagen, spieler, zuFuss, gelände, ansicht)` statt `Update` - die Ansicht zeichnet nur die Zustände und
   meldet Unfall, Sturz und Hupen am Wechsel der Zustände. Offline: `TrafficView.Update` (Simulation + `States` + dieselbe Darstellung).

## Persistenz

Jetzt: SQLite-Datei `data/raser.db` mit den Tabellen `accounts` (id, name, salt, hash, rounds, admin, created) und `sessions` (Hash des Tokens,
Konto, Ablauf). Spielerlagen werden noch nicht gespeichert. Später: Konten und Inventar in einer gemeinsamen Datenbank der globalen Dienste,
Deltas der Welt im Key-Value-Store (Konzept, Abschnitt 8).

## Jetzt gebaut - und später

| Jetzt | Später |
|---|---|
| ein Prozess, ein Regionsserver | Koordinator, mehrere Regionsserver, Randzone, Übergabe mit Hysterese |
| Clients schicken ihre Lage, der Server prüft nur Plausibilität | autoritative Fahrphysik auf dem Server (`Raser.Vehicle` ist schon ohne Szene), Client-Prediction |
| TCP mit eigenem Rahmen | UDP für Lagen, TCP für Zuverlässiges |
| HTTP ohne TLS | TLS (Reverse-Proxy oder `Http.Server.UseTls`), sonst gehen Passwort und Token im Klartext |
| keine Begrenzung der Anmeldeversuche | Sperre nach Fehlversuchen je Name und Adresse |
| Wetter aus Presets | Wetter per Seed, optional echtes DWD-Wetter |

## Code

| Projekt | Inhalt |
|---|---|
| `src/Raser.Net` | das Protokoll (`Raser.Packet`, `Raser.Wire`, `Raser.FrameReader`, `Raser.Link`), Befehle (`Raser.Commands`), Passwörter (`Raser.Passwords`) - mit Tests |
| `src/Raser.Server` | `raser-server`: Launcher-API, Konten, Gateway, Koordinator, Regionsserver, Uhr und Wetter |
| `src/Raser.Client` | `NetSession` (Verbindung, Chat, Konsole), `ChatOverlay` |
| `src/Raser.Game` | `online.fire`: die anderen Spieler in der Szene; `--bot`: ein Client ohne Welt und Fenster (für Tests); `npcs.fire`: der Verkehr in der Szene |
| `src/Raser.Traffic` | Spurgraph und Simulation von Autos und Fußgängern (`Raser.RoadGraph`, `Raser.Traffic`) - ohne Szene, mit Tests |

Probe von Hand: `tools/server-smoke.sh <raser-server> <raser-game>` startet den Server, registriert über HTTP, verbindet zwei Bots (`raser-game --bot 12 --say "..."`) und prüft, dass sie sich sehen, den Chat lesen, dass `/time` von einem Spieler abgelehnt wird und von einem Admin wirkt, und dass ein falsches Token abgelehnt wird.
