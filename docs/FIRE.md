# Was Ruhrpott-Raser in fire findet

Das Projekt ist der Extremtest für fire. Hier steht, was dabei an fire auffällt: Fehler, Lücken und Umwege, mit dem Stand, auf dem es gefunden wurde.

| Fund | Umweg im Projekt | Stand |
|---|---|---|
| In einem `namespace` findet ein statischer Zugriff über den kurzen Klassennamen die Nachbarklasse nicht (`B.G()` in `namespace Raser` gibt E4022 „Unknown identifier 'B'“), obwohl die Doku sagt, dass der kurze Name innen reicht. `new B()` geht. Auch Enum-Werte (`Material.Air`) sind betroffen. | Statische Zugriffe voll qualifiziert (`Raser.Grid.FloorDiv`) | behoben (a2013b5); die vollen Namen bleiben im Code |
| `List<T>` hat kein `Sort`. | war `Raser.Sorting` | behoben (8a0292a), umgestellt auf `List.Sort()` |
| Statische Felder werden in Deklarationsreihenfolge initialisiert; ein Initialisierer, der ein später deklariertes statisches Feld liest, bekommt `undefined`. | Reihenfolge der Klassen in `voxel.fire` beachten | Verhalten, nicht dokumentiert |
| Ein Bibliotheksprojekt `Raser.Core` hat ohne `"import"` den Importnamen `Raser_Core` (Punkte werden zu `_`); `#import "Raser.Core"` meldet dann nur „not a known extension“, ohne den echten Namen zu nennen. | `"import": "raser.core"` in jedem Projekt (bleibt: kurz und wie die Standardpakete) | behoben (8a0292a): Punkte bleiben, die Meldung nennt die Importnamen; seit df5ad3c sind Namen außerhalb eines Namespace über den Importnamen qualifiziert |
| `where` und `under` sind Schlüsselwörter; als Variablenname gibt es nur „Expected an identifier“. | Umbenannt | Meldung könnte das Schlüsselwort nennen |
| Ein Ausdruck kann nicht mit `&&` auf der nächsten Zeile weitergehen (Zeilenende beendet die Anweisung). | Eine Zeile | Verhalten |
| Ein Objekt, das einem Konstruktor übergeben und in einem Feld gespeichert wird, stirbt mit dem Aufrufer, wenn es ein Temporärwert war (`new Voxelizer(Sample.Make(), ...)`). | `try x.TakeTo(this)` in den Konstruktoren | Absicht (Besitzmodell); leicht zu vergessen, ein Hinweis des Typprüfers wäre hilfreich |
| `from` ist ein Schlüsselwort; als Parametername „Expected a parameter name“. | Umbenannt | Meldung könnte das Schlüsselwort nennen |
| Keine Bit-Umwandlung Float ↔ Int und keine typisierten Lese-/Schreibfunktionen auf Byte-Puffern (Int16/32/64, Float32/64, Byte-Reihenfolge). | war IEEE-754 von Hand | behoben (d0c120a): GeoTIFF, `ByteWriter`/`ByteReader` und WKB nutzen `ReadFloat32/64`, `WriteInt32/64`, `Bits` |
| Kein schnelles Kopieren/Suchen in Byte-Puffern (`Copy`, `Slice`, `IndexOf`); XML-Parser, LZW und `ByteWriter` laufen Byte für Byte in der VM. | waren Schleifen | behoben (d0c120a): `CopyTo`, `Slice`, `IndexOf` im XML-Parser, LZW, `ByteWriter`; Import 41 → 32 s |
| Nativ sind Elementzugriffe auf Byte-Puffer und typisierte Arrays in Schleifen generisch: `aget_g`, die Zahl wird verpackt (`Int(...)`), `opEq`, `poolMark()`/`leave()` je Durchlauf. Gemessen (Release, gcc): Zählen der Nicht-Null-Bytes in 256 K: `byte[]`-Feld 2,6 ms, lokal 2,4 ms, `int[8]` 1,4 ms - 5 bis 10 ns je Element (C: unter 0,5 ns). Chunk füllen und kodieren kosten so je 6 ms. | keiner | verbessert (fbfa060): Voxelisierung einer Kachel 47 → 40 s |
| `base` ist ein Schlüsselwort (Variablenname „Expected an identifier“). | Umbenannt | Meldung könnte das Schlüsselwort nennen |
| **Nativ falsch:** Im Werkzeug (`Raser.Tool`, Release) liefert `float h0 = z0 + Raser.Shape.CornerMeters(shape, 0)` statt 0,2 den Wert 4596373779694328320 (die Bits von 0,2 als Ganzzahl). Im generierten C gibt `f322_c` (der C-Körper von `CornerMeters`, Rückgabe `defined float`) korrekt `Float(...)` zurück, die Aufrufstelle liest aber `(Real)(FireInt)s1.i` - sie hält das Ergebnis für eine Ganzzahl. `shape` ist dort ein lokales `int` aus einer Methode mit `defined int`. In kleinen Nachbauten (gleiche Datei, oder Bibliothek + Programm) tritt es nicht auf; die VM rechnet richtig. | war `Corner(...) * 0.05` | behoben (8a0292a), wieder `CornerMeters`. Folge: native Builds vorher setzten auch die unterste Chunk-Ebene falsch (`HeightRaster.Min`) - Generator 2 erzeugt neu |
| **Kein Fehler, mein Irrtum:** `(x) => self.Get("a")` fängt `self` ohne Wort ein, und das heißt: die Lambda bekommt eine **tiefe Kopie** (hier des ganzen Stores samt Dictionary und Items). Was sie zurückgibt, gehört zur Kopie und stirbt mit ihr - `store.items` selbst blieb heil. Im Viewer war die Kopie die des `WorldView` mit den Chunks; die Kopie eines Objekts, das eine Ressource über ihre Nummer hält, gibt beim Sterben die echte Ressource frei - daher „No resource with ID 1“ bzw. „The framebuffer has no usable size“. Richtig: das Objekt als Parameter der Lambda übergeben, eine globale Variable nehmen oder mit `on` binden. | Nachbarn als einzelne Parameter (`Raser.Mesher`) - bleibt so, ist ohnehin klarer | geklärt; fire warnt jetzt mit TC023 ausdrücklich vor der tiefen Kopie, die Doku zu Lambdas ist ergänzt |
| **Besitz falsch (nur nativ):** `store.Get("a")` als Anweisung (Ergebnis verworfen) zerstört das Objekt, das `Get` aus dem Dictionary zurückgibt (VM: nicht). | Ergebnis nicht verwerfen | an fire gemeldet |

Nachbau (`forge run own.fire` und nativ) - der erste Teil ist das dokumentierte Einfangen als tiefe Kopie (siehe oben), der zweite (das verworfene `store.Get("a")`, nur nativ) ist gemeldet:

```fire
class Item {
    string n
    construct(string n) { this.n = n }
    destruct() { print("destroy " + this.n) }
}
class Store {
    Dictionary<string, Item> items
    construct() { this.items = new Dictionary<string, Item>() }
    Item Get(string k) {
        if (this.items.ContainsKey(k)) { return this.items[k] }
        var it = new Item(k)
        this.items[k] = it
        it.TakeTo(this.items)
        return it
    }
}
class Holder {
    Item a
    construct(Item lambda<int> f) { this.a = f(1) }
    string Name() { return this.a.n }
}
class Run {
    static undefined Go(Store store) {
        var self = store
        print(new Holder((x) => self.Get("a")).Name())   // VM und nativ: danach "destroy a" - das Item der Kopie von store (richtig so)
        print("after holder")
        print(store.Get("a").n)
    }
}
var store = new Store()
store.Get("a")                                       // nativ: hier schon "destroy a"
Run.Go(store)
print("end")
```

Mit einer globalen Variable statt `self` (oder `store` als Parameter der Lambda): `a`, `after holder`, `a`, `end`, `destroy a`.
| `new Object(Model.FromArrays(...))` setzt die Mitte des Netzes auf die Position (Anker 0,5): die Koordinaten des Netzes gelten nur relativ. Für Welt-Koordinaten muss man das Minimum selbst rechnen und `SetAnchor(0, 0, 0)` + `SetPosition(min)` setzen. | war Minimum + `SetAnchor` | behoben (68e9a69): `obj.KeepMeshCoordinates = true` im Viewer, Bild pixelgleich |
