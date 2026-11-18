# Inventar und Karte

Was der Spieler bei sich trägt, wie das Fenster funktioniert und wie das Inventar später über den Server läuft. Die Regeln stehen in
`src/Raser.Core/inventory.fire` (ohne Szene und Fenster, mit Tests in `src/Raser.Core/testing/core_tests.fire`), das Fenster in
`src/Raser.Client/inventory_ui.fire`, die Symbole in `src/Raser.Client/item_icons.fire`, die Karte in `src/Raser.Client/minimap.fire`, das
Zusammenspiel im Spiel in `src/Raser.Game/items.fire`.

## Was der Spieler trägt

| Platz | Plätze | Was hinein darf | Wirkung |
|---|---|---|---|
| Hosentaschen | 5 (`new Raser.Inventory(store, drops, 5, 4)`) | nur Kleines (Größe 1) | - |
| Hände (Überladung) | 4 | alles, auch Sperriges (Kanister) und einen zweiten Rucksack | jeder belegte Platz bremst mehr: der k-te kostet k × `handStep` (0,04), also 96, 88, 76, 60 % Gehtempo; Rennen: das Quadrat |
| Rücken | 1, links im Fenster | nur ein Rucksack | mit Rucksack erscheint sein Raster oben im Fenster |
| Handy | 1, unter dem Rücken | nur das Handy | H zeigt das Handy (noch ein Platzhalter) |
| Rucksack | Turnbeutel 6, Rucksack 16 (8 je Reihe), Trekkingrucksack 27 (9 je Reihe) | Kleines und Mittleres, nie ein Rucksack | - |

Größen: 1 klein (Handy, Schlüssel, Münzen, Brötchen, Taschenlampe, Zigaretten), 2 mittel (Pommes, Wasser, Schraubenschlüssel), 3 sperrig (Kanister,
Rucksäcke). Stapel: Münzen 100, Zigaretten 10, Brötchen 6, Wasser 4, Pommes 2, sonst 1. Jeder Gegenstand hat ein Gewicht (das Fenster zeigt die
Summe; es bremst noch nicht).

Am Start hat der Spieler Handy, Schlüssel, 23 Münzen, 3 Brötchen, 7 Zigaretten und einen Rucksack mit Wasser, Taschenlampe und Schraubenschlüssel.
Links neben dem Wagen liegen zum Ausprobieren ein Turnbeutel (mit Pommes, Wasser, Zigaretten), ein leerer Trekkingrucksack, ein Kanister, Münzen,
Brötchen und Pommes.

## Bedienung

| Taste | Wirkung |
|---|---|
| I oder Tab | Inventar auf und zu (offen steht das Fahrzeug bzw. der Spieler still, die Maus ist frei) |
| Escape | schließt Inventar und Handy |
| Linksklick | Stapel aufnehmen; mit Stapel an der Maus: ablegen, aufstocken oder tauschen |
| Rechtsklick | die Hälfte aufnehmen (aufgerundet); mit Stapel: eins ablegen |
| Umschalt + Linksklick | den Stapel in den anderen Bereich (Taschen/Hände ↔ Rucksack bzw. geöffneter Rucksack am Boden) |
| Klick neben das Fenster | den Stapel an der Maus wegwerfen (rechts: eins) |
| Q | den Stapel unter der Maus wegwerfen |
| F (zu Fuß) | den nächsten Gegenstand (2,5 m) aufheben; ein Rucksack kommt auf den Rücken, wenn der frei ist, sonst wird er geöffnet |
| B (zu Fuß) | den Rucksack absetzen - er liegt mit seinem Inhalt am Boden |
| H | Handy (Platzhalter) |
| M | Karte: gedreht → genordet → aus |
| + / - | Zoom der Karte (0,5 / 1 / 2 m je Pixel) |

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

## Bilder ohne Fenster

```bash
raser --world world --near 1 --far 3 --workers 1 --auto 0.1 --foot 1 --inventory-shot inventar.png [--phone 1] [--inventory-test 1]
raser --world world --near 1 --far 3 --workers 1 --auto 3 --minimap 1 --shot bild.png     # --minimap north: genordet, --map-zoom 0|1|2
```

`--inventory-shot` hebt den Kanister auf, öffnet den Turnbeutel am Boden und nimmt die Brötchen an die Maus; `--inventory-test 1` spielt vorher
Tasten und Klicks wie vom Fenster durch (aufnehmen, wegwerfen, F, B, Umschalt+Klick) und druckt, was geschah.

## Fehlt noch

- Benutzen (essen, trinken, Taschenlampe an, Kanister in den Tank), Handel, Kauf.
- Gewicht bremst noch nicht (nur die Hände).
- Das Handy ist nur ein Platzhalter.
- Gegenstände am Boden sind einfache Kisten (Rucksäcke mit Deckel), ohne Schatten auf das Symbol.
- Ziehen mit gedrückter Maus über mehrere Plätze (Minecraft: verteilen) und Doppelklick (sammeln).
- Die Karte zeichnet Kacheln im Hauptthread (gut 100 ms beim Betreten neuer Kacheln); besser in einem Worker.
