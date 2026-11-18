# Inventar und Karte

Was der Spieler bei sich trägt, wie das Fenster funktioniert und wie das Inventar später über den Server läuft. Die Regeln stehen in
`src/Raser.Core/inventory.fire` (ohne Szene und Fenster, mit Tests in `src/Raser.Core/testing/core_tests.fire`), das Fenster in
`src/Raser.Client/inventory_ui.fire`, die Symbole in `src/Raser.Client/item_icons.fire`, die Karte in `src/Raser.Client/minimap.fire`, das
Zusammenspiel im Spiel in `src/Raser.Game/items.fire`.

## Was der Spieler trägt

| Platz | Plätze | Was hinein darf | Wirkung |
|---|---|---|---|
| Hosentaschen | 5 (`new Raser.Inventory(store, drops, 5, 4)`) | nur Kleines (Größe 1) | alle belegt: `pocketsFull` (6 %) langsamer |
| Hände (Überladung) | 4 | alles, auch Sperriges (Kanister) und einen zweiten Rucksack | bremst: der k-te belegte Platz kostet k × `handStep` (0,04: 4, 12, 24, 40 %), dazu `handKg` (0,02) je kg in den Händen (der Kanister: 11 %); Rennen: das Quadrat |
| Rücken | 1, links im Fenster | nur ein Rucksack | mit Rucksack erscheint sein Raster oben im Fenster |
| Handy | 1, unter dem Rücken | nur das Handy | H zeigt das Handy (noch ein Platzhalter) |
| Rucksack | Turnbeutel 6, Rucksack 16 (8 je Reihe), Trekkingrucksack 27 (9 je Reihe) | Kleines und Mittleres, nie ein Rucksack | bremst nie |

Größen: 1 klein (Handy, Schlüssel, Brötchen, Taschenlampe, Zigaretten), 2 mittel (Pommes, Wasser, Schraubenschlüssel), 3 sperrig (Kanister,
Rucksäcke). Stapel: Zigaretten 10, Brötchen 6, Wasser 4, Pommes 2, sonst 1. Das Tempo (`Inventory.SpeedFactor`, höchstens bis 30 %) hängt nur an den
Händen und an vollen Hosentaschen; alle Zahlen sind Felder des Inventars. Das Fenster zeigt das Gesamtgewicht.

**Geld** ist Bargeld am Spieler (`Inventory.cash`, Cent; in der Leiste und im Fenster). Am Boden liegt es als Gegenstand „Geld“ mit dem Betrag
als Anzahl; aufgehoben (F) wird es Bargeld, nie ein Stapel im Inventar. Es gibt kein Konto.

Am Start hat der Spieler Handy, Schlüssel, 23,50 €, 3 Brötchen, 7 Zigaretten und einen Rucksack mit Wasser, Taschenlampe und Schraubenschlüssel.
Links neben dem Wagen liegen zum Ausprobieren ein Turnbeutel (mit Pommes, Wasser, Zigaretten), ein leerer Trekkingrucksack, ein voller Kanister,
12,50 €, Brötchen und Pommes; 22 m voraus steht am rechten Straßenrand ein Passant (orange Jacke) zum Umfahren.

## Benutzen und Körper

Benutzen ist eine Operation (`InvOp` Use, Art 7; Art 5 und 6 sind im Protokoll Öffnen/Schließen eines Rucksacks am Boden). `Inventory.Use` prüft und
wirkt; das Fahrzeug für Kanister und Werkzeug ist `Inventory.vehicle` (der Client nimmt das nächste bis 4 m, der Server setzt sein eigenes):

| Gegenstand | Wirkung |
|---|---|
| Brötchen, Pommes | eins weniger; Sättigung +30 bzw. +45 (Pommes: Durst +5) |
| Wasser | eine Flasche weniger; Durst -45 |
| Zigaretten | eine weniger; ein paar Sekunden Rauch an der Figur (nur fürs Bild, keine Wirkung) |
| Taschenlampe | an/aus; leuchtet (Punktlicht 3 m vor dem Spieler), solange eine heile in Händen oder Hosentaschen ist; kaputt geht sie nicht an |
| Benzinkanister | tankt das Fahrzeug in Reichweite: ein voller gibt 40 % Tank, nur so viel, wie fehlt; der Füllstand steht in `data` (verbrauchte %, im Platz als Balken), der leere Kanister bleibt; das Fahrrad braucht keinen Sprit |
| Schraubenschlüssel | repariert das Fahrzeug in Reichweite um 25 % (bis heil), bleibt |
| Handy | zeigt das Handy (nur im Client, keine Operation) |

`data` ist bei Rucksäcken die ID des Behälters, sonst der Zustand: 0 heil/voll, Kanister die verbrauchten %, Handy und Taschenlampe 1 = kaputt
(im Platz ein roter Sprung, beim Handy „Display kaputt“). Gestapelt wird nur mit data 0.

Der Körper (`Raser.Body`, Raser.Core/body.fire): **Puste** 0-1 - Rennen kostet sie (voll reicht 12 s), sonst kommt sie in 15 s wieder; ist sie alle,
geht Rennen erst ab 25 % wieder. **Essen** und **Trinken** 0-100 sinken (satt bis leer in 45 bzw. 30 min, beim Rennen doppelt so schnell); unter 15
kommt die Puste nur mit einem Drittel des Tempos wieder. Die Leiste zeigt alle drei.

## Umhauen

`Raser.Knockdown.Apply(inv, seed, impact)` (Raser.Core/knockdown.fire) - rein und deterministisch, der Zufall kommt aus dem Samen (der Server
entscheidet ihn): alles, was der Spieler trägt (Maus, Hände, Hosentaschen, Handy, der Rucksack ganz mit Inhalt), fällt in 0,6 bis 2,2 m um ihn zu
Boden; 20 bis 60 % des Bargelds liegen als ein bis drei Häufchen Geld daneben. Je nach Wucht (ab 2 m/s, voll ab 16 m/s) geht etwas kaputt: Handy
(70 %) und Taschenlampe (40 %) bekommen data 1, der Kanister leckt (15 %, die Hälfte des Rests ist weg), Brötchen (30 %), Pommes (60 %), Wasser
(40 %), Zigaretten (20 %) je Stück weg; im Rucksack halb so oft; Schlüssel, Werkzeug, Rucksäcke nie. Das Ergebnis (`KnockResult`) nennt Stapel am
Boden, Kaputtes, Verlorenes und die IDs der neuen Gegenstände am Boden. Offline: den Passanten anfahren (ab 2 m/s), er liegt 6 s; ohne Fenster
`--hit-passant 12` bzw. `--knock 14` (der Spieler selbst). Online ruft das der Server beim Ereignis KnockedDown.

## Bedienung

Unten in der Mitte steht immer die **Leiste** mit dem Hauptinventar, von links nach rechts: Tasche (Rücken) 1, Handy 2, Hände 3-6, dann die fünf
Hosentaschen. Der ausgewählte Platz ist weiß umrandet, sein Name steht kurz darüber; die Figur hält den Gegenstand in der rechten Hand. Darüber
links Puste, Essen, Trinken, rechts das Bargeld (und das Tempo, wenn die Last bremst).

| Taste | Wirkung |
|---|---|
| 1 / 2 / 3-6 | Tasche / Handy / Hände wählen |
| Y / X (engl. Z / X) | einen Platz nach links / rechts - nach Scancode (die Taste unten links, 29 und 27), also auf QWERTZ und QWERTY dieselbe; am Ende geht es auf der anderen Seite weiter |
| Q | der zuletzt gewählte Platz |
| Mausrad (Inventar zu) | wählen |
| U oder rechte Maustaste (Inventar zu) | benutzen: die Tasche öffnet das Inventar, das Handy zeigt das Handy, sonst `InvOp` Use |
| T | wegwerfen: offen den Stapel unter der Maus, zu den ausgewählten |
| I oder Tab | Inventar auf und zu (offen steht das Fahrzeug bzw. der Spieler still, die Maus ist frei) |
| Escape | schließt Inventar und Handy |
| Linksklick | Stapel aufnehmen; mit Stapel an der Maus: ablegen, aufstocken oder tauschen |
| Rechtsklick | die Hälfte aufnehmen (aufgerundet); mit Stapel: eins ablegen |
| Umschalt + Linksklick | den Stapel in den anderen Bereich (Taschen/Hände ↔ Rucksack bzw. geöffneter Rucksack am Boden) |
| Klick neben das Fenster | den Stapel an der Maus wegwerfen (rechts: eins) |
| F (zu Fuß) | den nächsten Gegenstand (2,5 m) aufheben; ein Rucksack kommt auf den Rücken, wenn der frei ist, sonst wird er geöffnet; Geld wird Bargeld |
| B (zu Fuß) | den Rucksack absetzen - er liegt mit seinem Inhalt am Boden |
| H | Handy (Platzhalter; mit kaputtem Display gesprungen) |
| M | Karte: gedreht → genordet → aus |
| + / - | Zoom der Karte (0,5 / 1 / 2 m je Pixel) |
| F9 / F10 | Uhr vor / zurück (Testtasten; vorher T/G - T ist jetzt Wegwerfen) |

E bleibt Ein- und Aussteigen, Enter der Chat, ^ die Konsole; Chat und Konsole bekommen die Tasten zuerst.

## Daten: alles hängt an IDs

- Ein Stapel ist (Art, Anzahl, data): data ist bei einem Rucksack die ID des Behälters mit seinem Inhalt, sonst 0. Ein Rucksack wandert so mit
  Inhalt vom Rücken auf den Boden und zu einem anderen Spieler, ohne dass ein Objekt umzieht.
- `Raser.ContainerStore` hält alle Behälter (Hosentaschen, Hände, Rücken, Handy, die Maus des Spielers, alle Rucksäcke); `Raser.Inventory` kennt
  nur die IDs seiner Behälter. `Raser.ItemDrops` sind die Gegenstände am Boden (Lage, Art, Anzahl, data).
- Alles lässt sich als Bytes schreiben (`Raser.ByteWriter`, Varints): `Container.Write` (ID, Art, Größe, je Platz Art und - wenn belegt - Anzahl
  und data), `ContainerStore.Write`, `ItemDrops.Write` (Lage in cm), `Inventory.Write` (die IDs seiner Behälter), `InvOp.Write`.

## Operationen

Jede Änderung ist eine `Raser.InvOp`, und `Inventory.Apply` prüft sie vollständig, bevor sich etwas ändert:

| Art | Felder | geprüft |
|---|---|---|
| Move (1) | Quelle (Behälter, Platz), Ziel (Behälter, Platz), Anzahl | beide Behälter erreichbar, Anzahl ≤ Stapel, das Ziel nimmt die Art, Ziel leer oder dieselbe Art ohne data und nicht über `maxStack`, ein Rucksack nur ganz und nie in sich selbst |
| Swap (2) | Quelle, Ziel | erreichbar, jede Seite nimmt die Art der anderen |
| Drop (3) | Quelle, Anzahl | erreichbar; die Lage ist die des Spielers; ergibt die ID des neuen Gegenstands am Boden |
| PickUp (4) | Gegenstand am Boden | in Reichweite (2,5 m); so viel, wie passt (Rücken, Handy, Taschen, Rucksack, zuletzt die Hände) |

„Erreichbar“: die eigenen Behälter, der Rucksack auf dem Rücken und ein geöffneter Rucksack am Boden, solange er noch daliegt und der Spieler
daneben steht. Ein Klick im Fenster (`Inventory.Click`, wie in Minecraft) wird zu genau einer Operation; das Fenster sammelt die ausgeführten
(`InventoryScreen.done`), damit der Client sie später schicken kann.

## Später über den Server

Der Server führt die Inventare (globaler Dienst, siehe [SERVER.md](SERVER.md)); der Client sagt nur, was er tun will.

1. **Laden:** Nach dem Welcome schickt der Server `Inventory` (neue Art im Protokoll): die Behälter des Spielers (`Container.Write` je Behälter,
   samt Inhalt des Rucksacks auf dem Rücken) und die IDs (`Inventory.Write`). Behälter-IDs vergibt der Server (`Raser.IdAllocator`, global
   eindeutig), nicht mehr der `ContainerStore` des Clients.
2. **Ändern:** Der Client führt eine Operation sofort selbst aus (Vorhersage) und schickt sie als `InvOp` mit einer Folgenummer (C → S, wenige
   Bytes). Der Server prüft mit demselben `Inventory.Apply` - Reichweite und Lage nimmt er aus seinem eigenen State des Spielers, nicht vom
   Client - und antwortet `InvAck` (Folgenummer, ok) oder, abgelehnt, mit den betroffenen Behältern in ihrem echten Zustand (`InvSet`); der Client
   übernimmt sie (die Vorhersage ist dann verworfen). Ein Drop bekommt seine ID am Boden vom Server.
3. **Boden:** Gegenstände am Boden gehören zur Region (Interesse je Kachel wie die Spieler): der Snapshot nennt neue und verschwundene
   (`ItemDrop`: ID, Lage, Art, Anzahl). Den Inhalt eines Rucksacks am Boden schickt der Server erst, wenn ein Spieler ihn öffnet (in Reichweite);
   Änderungen daran gehen an alle, die ihn offen haben. Zwei Spieler am selben Rucksack: wer zuerst beim Server ist, gewinnt, der andere bekommt
   ein `InvSet`.
4. **Speichern:** Behälter als Bytes je ID in der Datenbank der globalen Dienste (eine Zeile je Behälter: ID, Besitzer bzw. Lage am Boden, Bytes),
   geschrieben beim Ändern (gebündelt) und beim Abmelden; Gegenstände am Boden verfallen nach einer Zeit (außer Rucksäcken mit Inhalt?).
5. **Schutz:** Operationen höchstens ~20 je s; jede, die nicht passt, wird nicht ausgeführt (kein Kick: das passiert bei Verzögerung
   ehrlich). Wer Gegenstände erzeugt, ist nur der Server (Händler, Missionen, Admin-Befehl `/give`).

## Karte

Oben rechts, rund (168 Pixel), der Spieler in der Mitte: Straßen für Autos (Haupt- gelb, andere weiß, mit Rand), Wege braun, Gleise grau,
Gebäude als Grundriss, Grün, Wald, Wasser, Parkplätze; Fahrzeuge als blaue Punkte, Gegenstände am Boden als gelbe, der Spieler als Pfeil (im Wagen
rot, zu Fuß blau), N am Rand, ein Maßstab darunter.

Kosten: jede Kachel wird einmal als Bild (256 × 256, 1 Pixel je m) gezeichnet - mit dem Laden der Kachel (die auch Wände und Bäume braucht) gut
100 ms, höchstens eine je Bild; die 3 × 3 Kacheln um den Spieler liegen als Mosaik bereit (neu beim Wechsel der Kachel). Je Bild wird der runde
Ausschnitt abgetastet (gedreht, in Festkomma): gut 3 ms, nur wenn sich Lage oder Richtung geändert haben, beim Fahren jedes zweite Bild.

## Anzeige: Tacho, Schrift, Modelle

- **Tacho** unten rechts, nur im Fahrzeug (Raser.Client/speedometer.fire): dunkler, halb durchsichtiger Kreis, schlanke Striche und Zahlen über 270°,
  ein farbiger Bogen für das Tempo (türkis, ab 70 % orange, ab 90 % rot) mit schmalem Zeiger, die Zahl groß in der Mitte, unten schmale Bögen für
  Tank (links) und Zustand (rechts). Skala: Auto 200, Transporter 160, Motorrad 220, Fahrrad 40 km/h. Das Zifferblatt wird je Skala einmal mit Alpha
  gezeichnet und je Bild mit `BlitMode.Blend` aufgelegt. Die Textzeile unten links zeigt nur noch Uhrzeit, Wetter und Hinweise.
- **Schrift**: Rajdhani Medium und Bold (Indian Type Foundry, SIL Open Font License 1.1, `assets/fonts/` mit `OFL.txt`), als Ressource eingebettet
  (`HudStyle`): sie steckt im Programm, der Launcher liefert sie damit aus.
- **Modelle** (Raser.Client/item_models.fire): je Gegenstand ein Netz aus wenigen Quadern (`Model.FromArrays`) mit einer Palette als Textur - in
  der Szene ein Objekt je Gegenstand: Flasche, Brötchen, Pommesschale mit Ketchup und Mayo, Kanister mit Griffen und Ausguss, Taschenlampe,
  Maulschlüssel, Schlüssel, Schein und Münzen, Handy, Zigarettenschachtel; Turnbeutel, Rucksack (Deckel, Fronttasche, Schnallen) und
  Trekkingrucksack (Isomatte, Seitentaschen) mit Riemen - am Boden und getragen (die Riemen über die Schultern).

## Bilder ohne Fenster

```bash
raser --world world --near 1 --far 3 --workers 1 --auto 0.1 --foot 1 --inventory-shot inventar.png [--phone 1] [--inventory-test 1]
raser --world world --near 1 --far 3 --workers 1 --auto 3 --minimap 1 --shot bild.png     # --minimap north: genordet, --map-zoom 0|1|2
```

Dazu: `--select 10 --use 1` (Platz der Leiste wählen und benutzen, z. B. die Taschenlampe; `--time 21:30` für die Nacht), `--knock 14` (den
Spieler umhauen), `--hit-passant 12` (den Passanten umfahren). `--inventory-shot` hebt den Kanister auf, öffnet den Turnbeutel am Boden und nimmt die Brötchen an die Maus; `--inventory-test 1` spielt vorher
Tasten und Klicks wie vom Fenster durch (aufnehmen, wegwerfen, F, B, Umschalt+Klick, die Leiste mit 3, U, 1, X, Y, Q, T) und druckt, was geschah.

## Fehlt noch

- Handel, Kauf; Kanister an der Tankstelle füllen.
- Das Handy ist nur ein Platzhalter.
- Der umgehauene Spieler selbst liegt offline nicht (nur der Passant); online liegt er 3 s (der Server ruft `Raser.Knockdown.Apply` beim
  Ereignis KnockedDown). Arten im Protokoll: 1-4 wie oben, 5/6 Öffnen/Schließen eines Rucksacks am Boden, 7 Use.
- Ziehen mit gedrückter Maus über mehrere Plätze (Minecraft: verteilen) und Doppelklick (sammeln).
- Die Karte zeichnet Kacheln im Hauptthread (gut 100 ms beim Betreten neuer Kacheln); besser in einem Worker.
