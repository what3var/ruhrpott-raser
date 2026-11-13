# Was Ruhrpott-Raser in fire findet

Das Projekt ist der Extremtest für fire. Hier steht, was dabei an fire auffällt: Fehler, Lücken und Umwege, mit dem Stand, auf dem es gefunden wurde.

| Fund | Umweg im Projekt | Stand |
|---|---|---|
| In einem `namespace` findet ein statischer Zugriff über den kurzen Klassennamen die Nachbarklasse nicht (`B.G()` in `namespace Raser` gibt E4022 „Unknown identifier 'B'“), obwohl die Doku sagt, dass der kurze Name innen reicht. `new B()` geht. Auch Enum-Werte (`Material.Air`) sind betroffen. | Statische Zugriffe voll qualifiziert (`Raser.Grid.FloorDiv`) | offen (fire `http-server`, bffea1b) |
| `List<T>` hat kein `Sort`. | `Raser.Sorting.Ints`/`Texts` | offen |
| Statische Felder werden in Deklarationsreihenfolge initialisiert; ein Initialisierer, der ein später deklariertes statisches Feld liest, bekommt `undefined`. | Reihenfolge der Klassen in `voxel.fire` beachten | Verhalten, nicht dokumentiert |
| Ein Bibliotheksprojekt `Raser.Core` hat ohne `"import"` den Importnamen `Raser_Core` (Punkte werden zu `_`); `#import "Raser.Core"` meldet dann nur „not a known extension“, ohne den echten Namen zu nennen. | `"import": "raser.core"` in jedem Projekt | Verhalten; die Meldung könnte den Importnamen der referenzierten Bibliothek nennen |
| `where` und `under` sind Schlüsselwörter; als Variablenname gibt es nur „Expected an identifier“. | Umbenannt | Meldung könnte das Schlüsselwort nennen |
| Ein Ausdruck kann nicht mit `&&` auf der nächsten Zeile weitergehen (Zeilenende beendet die Anweisung). | Eine Zeile | Verhalten |
| Ein Objekt, das einem Konstruktor übergeben und in einem Feld gespeichert wird, stirbt mit dem Aufrufer, wenn es ein Temporärwert war (`new Voxelizer(Sample.Make(), ...)`). | `try x.TakeTo(this)` in den Konstruktoren | Absicht (Besitzmodell); leicht zu vergessen, ein Hinweis des Typprüfers wäre hilfreich |
| `from` ist ein Schlüsselwort; als Parametername „Expected a parameter name“. | Umbenannt | Meldung könnte das Schlüsselwort nennen |
| Keine Bit-Umwandlung Float ↔ Int und keine typisierten Lese-/Schreibfunktionen auf Byte-Puffern (Int16/32/64, Float32/64, Byte-Reihenfolge). | IEEE-754 von Hand (`Raser.GeoTiff.Float32`, `Raser.TiffFile.Float64`), `ByteWriter`/`ByteReader` | an fire gemeldet |
| Kein schnelles Kopieren/Suchen in Byte-Puffern (`Copy`, `Slice`, `IndexOf`); XML-Parser, LZW und `ByteWriter` laufen Byte für Byte in der VM. | Schleifen | an fire gemeldet |
| Nativ sind Elementzugriffe auf Byte-Puffer und typisierte Arrays in Schleifen generisch: `aget_g`, die Zahl wird verpackt (`Int(...)`), `opEq`, `poolMark()`/`leave()` je Durchlauf. Gemessen (Release, gcc): Zählen der Nicht-Null-Bytes in 256 K: `byte[]`-Feld 2,6 ms, lokal 2,4 ms, `int[8]` 1,4 ms - 5 bis 10 ns je Element (C: unter 0,5 ns). Chunk füllen und kodieren kosten so je 6 ms. | keiner (die Voxelisierung einer Kachel dauert dadurch rund 35 s) | an fire gemeldet |
| `base` ist ein Schlüsselwort (Variablenname „Expected an identifier“). | Umbenannt | Meldung könnte das Schlüsselwort nennen |
| **Nativ falsch:** Im Werkzeug (`Raser.Tool`, Release) liefert `float h0 = z0 + Raser.Shape.CornerMeters(shape, 0)` statt 0,2 den Wert 4596373779694328320 (die Bits von 0,2 als Ganzzahl). Im generierten C gibt `f322_c` (der C-Körper von `CornerMeters`, Rückgabe `defined float`) korrekt `Float(...)` zurück, die Aufrufstelle liest aber `(Real)(FireInt)s1.i` - sie hält das Ergebnis für eine Ganzzahl. `shape` ist dort ein lokales `int` aus einer Methode mit `defined int`. In kleinen Nachbauten (gleiche Datei, oder Bibliothek + Programm) tritt es nicht auf; die VM rechnet richtig. | `Raser.Shape.Corner(shape, k) * 0.05` im Export | an fire gemeldet; Stand fire `http-server` bffea1b |
| **Besitz falsch (VM und nativ):** Ein Objekt, das einem anderen gehört (z. B. einem `Dictionary`), wird übergeben, wenn es eine Lambda zurückgibt und das Ergebnis in einem Feld landet: `construct(Item lambda<int> f) { this.a = f(1) }` mit `f = (x) => store.Get("a")` - mit dem Halter stirbt `a` ("destroy a"), obwohl `store.items` es besitzt. Im Viewer zerstörte das die Chunks und danach (über die frei gewordenen Nummern) den Framebuffer: „No resource with ID 1“ bzw. „The framebuffer has no usable size“. Nachbau: `own.fire` unten. | Nachbarn als einzelne Parameter (`Raser.Mesher`) | an fire gemeldet |
| **Besitz falsch (nur nativ):** `store.Get("a")` als Anweisung (Ergebnis verworfen) zerstört das Objekt, das `Get` aus dem Dictionary zurückgibt (VM: nicht). | Ergebnis nicht verwerfen | an fire gemeldet |

Nachbau zu den beiden Besitz-Fehlern (`forge run own.fire` und nativ):

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
        print(new Holder((x) => self.Get("a")).Name())   // VM und nativ: danach "destroy a"
        print("after holder")
        print(store.Get("a").n)
    }
}
var store = new Store()
store.Get("a")                                       // nativ: hier schon "destroy a"
Run.Go(store)
print("end")
```

Erwartet: `a`, `after holder`, `a`, `end`, `destroy a` (einmal, am Ende).
| `new Object(Model.FromArrays(...))` setzt die Mitte des Netzes auf die Position (Anker 0,5): die Koordinaten des Netzes gelten nur relativ. Für Welt-Koordinaten muss man das Minimum selbst rechnen und `SetAnchor(0, 0, 0)` + `SetPosition(min)` setzen. | so gemacht (`Raser.Viewer`) | Verhalten; ein Schalter „Koordinaten des Netzes behalten“ wäre praktisch |
