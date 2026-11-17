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
| **Threads stehen, solange das Hauptprogramm in einem langen nativen Aufruf steckt (nativ):** Ein fire-Thread, der nur rechnet (Chunk dekodieren, Randschichten - Schleifen, Felder, Dictionary, keine Dateien), kommt nur voran, wenn das Hauptprogramm einen Haltepunkt erreicht. Rendert das Hauptprogramm in einer Schleife (`cam.Render()`, je rund 160 ms), bleibt der Thread ganz stehen; mit `Sleep(0ms)` nach jedem Bild schafft er je Bild ein Stück: `Chunk.Decode` 2,3 → 20 ms, `ChunkFace.Of` 1,0 → 20 ms. Gleich mit `scene.Threads = 1` (3 Kerne frei) und mit `--global-jobs sleep`/`sync`. Dateizugriffe, Deflate und `new byte[]` allein sind nicht betroffen. Im Viewer kommen die Ergebnisse der Worker deshalb kaum an (bei 15 m/s fehlten in 1.150 von 1.160 Bildern Säulen), und die gemessenen Zeiten in den Workern sind 10- bis 20-mal zu hoch. Der frühere Eintrag „1,75-mal langsamer“ war derselbe Effekt mit einem Hauptprogramm, das gerade wartete. Nachbau `threads.fire` unten. | keiner (der Viewer lud im Hauptprogramm) | behoben (fire master 8c6100e: lesende Methoden laufen im Thread, das Hauptprogramm gibt in Natives frei): der Nachbau ohne `Sleep` braucht beim Rendern dieselbe Zeit (Decode 2,2 ms, Face.Of 1,1 ms); der Viewer baut die nahen Blöcke wieder in Workern (ein Block im Worker 2,9 s, im Hauptprogramm 2,3 s) |
| `IO.File.ReadAllText("/proc/meminfo")` (und `ReadAllBytes`) liefert unter Linux einen leeren Text: Dateien in `/proc` melden die Größe 0, gelesen wird offenbar nur so viel. Mit `IO.File.OpenRead` und `Read` kommt der Inhalt. | war `MemoryWatch.ReadProc` | behoben (fire 04454fb: liest bis zum Ende) |
| Wunsch: eine Abfrage des Speichers (ganzer Speicher, frei/verfügbar, was das Programm belegt) für alle Plattformen - der Viewer füllt seinen Vorrat, solange genug frei ist. | war `/proc` unter Linux | umgesetzt (fire 04454fb: `Environment.TotalMemory` / `FreeMemory` / `ProcessMemory`) - der Viewer nutzt sie |

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
| **Nativ generisch: Werte aus `Word.Bits` und statischen Feldern.** `int wb = Word.Bits` (auch als `defined int`) ist im erzeugten C ein `Value`; alles, was davon abhängt, läuft über die allgemeinen Operationen (`mul`, `add`, `ov__x002B` samt `claimToListP`) - im Mesher war das die Hälfte der Zeit. Ebenso ein `static defined int` in einem Ausdruck: `word vz = vz0 + z + R.Offset` wird zu `add(s0, s1)`. Der Vergleich zweier `word` dagegen ist einfaches C (`s0_w > s1_w`). Nachbau unten (`R.StaticInExpr`, `FromWordBits`). | war `wb` nur aus Literalen | behoben (fire 04454fb: `static readonly` mit konstantem Wert ist im C eine Konstante, `Word.Bits` auch; 1052e96: Rechnen auf defined Zahlen ohne Value-Umweg) - wieder `defined int wb = Word.Bits` |
| **Nativ teuer: `List<float>.Add` und typisierte Arrays gegenüber Puffern.** Gemessen (eine Million Elemente): `List<float>.Add` 127 ns je Aufruf, Schreiben in ein `float`-Array über das Feld 117 ns, über einen lokalen Namen 73 ns, Kopieren Element für Element zwischen zwei lokalen `float`-Arrays 22 ns - ein `byte`- oder `word`-Puffer schafft rund 2 ns. Ein Netz von 35.000 Vierecken braucht so mehrere hundert ms nur für die Arrays. | `MeshPart` auf mitwachsenden typisierten Arrays | Arrays behoben (fire 9c5490c: typisierte Arrays nativ so direkt wie Puffer, `defined float a[]`; `Model.FromArrays` aus float32-Puffern) - jetzt `defined`-Arrays; `List<T>` mit Zahlen: fire 638bacc macht `List<int>`/`List<float>` schneller (noch nicht nachgemessen) |
| `int`-Arrays sind beim Anlegen `undefined` (`int a[4096]` im Mesher: `'<<' expects int, not Undefined`), `byte`/`word`-Puffer sind 0. Das ist dokumentiert; `defined int a[...]` gibt es nicht (E4000). | war: Puffer und ausdrücklich füllen | behoben (fire 9c5490c: `defined int a[]`, mit 0 vorbelegt) - `GroundCut`, Mesher und `MeshPart` nutzen sie |
| Wunsch scene3d: Texturfilter "nächster Texel" bzw. "sharp bilinear" je Textur (Konzept: Pixel-Art scharf, aber geglättet). Mit nur bilinear braucht der Atlas 2 x 2 Texel je Voxel, damit die Voxel nicht verschwimmen (4-mal so viel Textur). | war 2 x 2 Texel je Voxel | umgesetzt (fire 3592a99: `Texture.Filter` Bilinear / Nearest / Sharp) - Atlas mit 1 Texel je Voxel, `TextureFilter.Sharp` |
| **Nativ: Ganzzahl-Division im Konstruktor schreibt den Parameter ins Feld.** `construct(defined int sx) { this.ox = sx / 2 }` gibt nativ `ox == 7` für `sx = 7` (VM: 3). Im erzeugten C wird der Quotient in `s1` gerechnet, gespeichert wird aber `Value x = P0` (der Parameter). Nur die Division (und nur im Konstruktor, nur `int`): `sx + 1`, `v / 2` in einer Methode und `a / 2.0` sind richtig. Mit fire a32117b. | war eine lokale Variable in `Raser.VoxelModel` | behoben (fire 97d2dd4); der Umweg ist zurückgenommen, alle Tests grün (fire master 6bc4a7e) |


Nachbau: ein Thread rechnet, das Hauptprogramm rendert (`threads.fire`; ein Projekt, das `Raser.Core` und `Raser.World` referenziert, nativ gebaut;
die Datei ist ein Chunk der Testregion). Ohne `Sleep(0ms)` in der Schleife kommt der Thread nie zum Ende:

```fire
#import "time"
#import "windows"
#import "scene3d"
#import "filesystem"
#import "compression"
#import "raser.core"
#import "raser.world"
class L {
    static string Run() {
        var raw = Compression.Deflate.Decompress(IO.File.ReadAllBytes("world/chunks/1469_22284/29386_445690_7.rrc"))
        int t1 = DateTime.Now.Ticks
        for (int i = 0; i < 5; i++) { var c = Raser.Chunk.Decode(raw) }
        int t2 = DateTime.Now.Ticks
        var chunk = Raser.Chunk.Decode(raw)
        int t3 = DateTime.Now.Ticks
        for (int i = 0; i < 5; i++) { var f = Raser.ChunkFace.Of(chunk, i) }
        int t4 = DateTime.Now.Ticks
        return "Decode " + (t2 - t1) / 50000.0 + " ms, Face.Of " + (t4 - t3) / 50000.0 + " ms"
    }
}
var fb = new Framebuffer(960, 600)
var scene = new Scene()
scene.Threads = 1
for (int i = 0; i < 300; i++) { scene.Add(new Object(Template.Sphere, (i % 20) * 1m, 0m, (i / 20) * -1m, 0.8m, 0.8m, 0.8m, 48)) }
scene.Add(Light.Directional(-0.5, -1.0, -0.4))
var cam = new Camera(fb)
cam.SetPosition(10m, 8m, 10m)
cam.LookAt(10m, 0m, -7m)
scene.Add(cam)
var results = new Channel<string>()
fire with results { results.Send(L.Run()) }
print("Hauptprogramm wartet:  " + results.Receive())    // Decode 2,4 ms, Face.Of 1,1 ms
fire with results { results.Send(L.Run()) }
while (results.Count == 0) {
    cam.Render()
    Sleep(0ms)                                          // ohne diese Zeile: der Thread steht
}
print("Hauptprogramm rendert: " + results.Receive())    // Decode 28,6 ms, Face.Of 28,1 ms
```

Nachbau zur Geschwindigkeit in Threads (ein Projekt, das `Raser.Core`, `Raser.World` und `Raser.Mesh` referenziert; `forge build ... --engine native -m RELEASE`):

```fire
#import "time"
#import "raser.core"
#import "raser.world"
#import "raser.mesh"
class B {
    static string Run(string label) {
        var store = new Raser.FileTileStore("world")
        int load = 0
        int mesh = 0
        for (int r = 0; r < 3; r++) {
            for (int z = 6; z <= 8; z++) {
                int t0 = DateTime.Now.Ticks
                var c = store.LoadChunk(new Raser.ChunkKey(29386, 445690, z))
                var w = store.LoadChunk(new Raser.ChunkKey(29385, 445690, z))
                int t1 = DateTime.Now.Ticks
                var m = new Raser.Mesher(c, w).Build()
                int t2 = DateTime.Now.Ticks
                load = load + (t1 - t0)
                mesh = mesh + (t2 - t1)
            }
        }
        return label + ": load " + load / 90000.0 + " ms, mesh " + mesh / 90000.0 + " ms per chunk"
    }
}
print(B.Run("main"))
var results = new Channel<string>()
fire with results { results.Send(B.Run("fire thread")) }
print(results.Receive())
fire dedicated with results { results.Send(B.Run("fire dedicated")) }
print(results.Receive())
```

Nachbau zu den generischen Werten (`forge build ... --engine native -m RELEASE --keep`, dann im erzeugten `fire_program.c` nach `add(` und `mul(` suchen):

```fire
class R {
    word buf[4096]
    static defined int Offset = 1048576
    construct() { }
    defined int StaticInExpr(defined int vz0) {
        word b[] = this.buf
        defined int n = 0
        for (int z = 0; z < 64; z++) {
            word vz = vz0 + z + R.Offset            // add(s0, s1): R.Offset ist ein Value
            if (vz > b[z]) { n++ }                  // einfaches C
        }
        return n
    }
    defined int FromWordBits() {
        int wb = Word.Bits
        defined int s = 0
        for (int k = 0; k < 4096; k++) { s = s + k * wb }    // mul(s1, P0)
        return s
    }
}
var r = new R()
print(r.StaticInExpr(5) + " " + r.FromWordBits())
```

## Wünsche aus Licht und Wetter (Raser.Weather, Viewer)

| Was | Warum | Stand |
|---|---|---|
| **Punktlichter mit Reichweite, die wirklich endet** (oder eine Auswahl je Dreieck/Band): heute rechnet jedes Pixel jedes Punktlicht (`1 / (1 + q²)`, nie 0) - der Viewer schaltet deshalb nur die 10 nächsten Laternen als Licht, der Rest der Straße bleibt dunkel. | Nachtszenen mit hunderten Laternen und Fenstern | offen |
| **Partikel als Striche in Flugrichtung** (gestreckt nach der Geschwindigkeit): Regen aus runden Scheiben sieht wie Schnee aus. | Regen | gelöst in `native-c` (Emitter.Stretch) |
| **Leuchtende Texturen** (eine Emissions-Textur oder ein Kanal, der unbeleuchtet bleibt): nachts tauscht der Viewer für Glas, Wasser und Laternen die Textur und schaltet `Lit` aus - für Fenster in den undurchsichtigen fernen Fassaden geht das nicht. | Fenster nachts in der Ferne | gelöst in `native-c` (Object.EmissiveTexture) |
| Nebel auch auf der GPU (laut Doku nur Fast und Software). | Hardware-Renderer | offen |

Stand fire master 1f74e29 (native-c ist gemergt): `Light.Cutoff` und `Scene.LightCulling` (300 Laternen: 790 → 14 ms je Bild), `Emitter.Stretch`, `Object.EmissiveTexture`/`EmissiveStrength`, `Object.Reflectivity` (nur Software, rund +45 ms bei viel nassem Boden). Der Viewer nutzt alle vier; offen bleiben Kacheln und Spiegelungen auf der GPU.

## Speicher: Werte in Sammlungen

| Was | Umweg | Stand |
|---|---|---|
| **`Dictionary.Clear`/`Remove` (und `List.Clear`) geben Werte nicht frei, die mit `TakeTo(dict)` übergeben wurden** - sie bleiben bis zum Ende des Containers belegt. Schlimmer: **ein neuer Container im selben Feld** (`this.d = new Dictionary<...>()`) gibt den alten samt Inhalt auch nicht frei. Nachbau (nativ, 200 Chunks + 200 × 200 KB je Runde, 6 Runden): nach `Clear` 142 → 846 MB, mit neuem Wörterbuch ebenso 846 MB, mit `delete pair.Value` vor `Clear` bleibt es bei 141 MB. Im Netzbau des Werkzeugs wuchs der Speicher so auf 14 GB (OOM nach 20 bzw. 39 von 49 Kacheln). | `delete` je Wert vor `Clear` (`ColumnBuilder.Forget`, `NearBuilder.Forget`) | `Clear`, `Remove` und das Überschreiben eines Schlüssels behoben (fire 5922d0a: nach 6 Runden 141 statt 846 MB); die `delete`-Schleifen in Raser sind wieder weg. **Offen:** ein neuer Container im selben Feld (`this.d = new Dictionary<...>()`) gibt den alten samt Inhalt weiter nicht frei (846 MB) |
| **Netzbau: der Speicher wuchs je Kachel um rund 350 MB, auch mit `Forget`.** Ursache war derselbe Befund wie oben, an einer zweiten Stelle: `ColumnBuilder.Parts` leerte den Zwischenspeicher ab 200 Chunks selbst mit `Clear` - die Chunks blieben belegt und waren danach für `Forget` nicht mehr zu finden. Gemessen (25 Blöcke einer Kachel, drei Durchgänge, Aufräumen je Kachel): vorher 1012 → 1835 → 2657 MB, jetzt 359 → 366 → 371 MB; das Werkzeug über drei Kacheln: Spitze 319 MB statt 1,9 GB. | `Forget` (mit `delete`) statt `Clear` | behoben in Raser; `tools/meshes-per-tile.sh` ist nicht mehr nötig. Mit fire 5922d0a reicht `Clear` (drei Kacheln: Spitze 353 MB) |
| **Ein Objekt in einem Feld ersetzen gibt das alte nicht frei** (derselbe offene Punkt, jetzt mit einem Objekt statt eines Containers): `this.making = take res` für jedes Ergebnis eines Workers (`NearResult` mit großen Arrays), danach `this.making = undefined` - der Speicher wuchs in 48 s auf 12 GB (OOM). | das Ergebnis in einer `List` halten und mit `Clear` freigeben (`WorldView.making`) | offen |

## Threads: Natives verschiedener Pakete sperren einander

**Befund (fire master c9e8e84, nativ, Linux):** Solange ein Worker-Thread in `Compression.Deflate` steckt, wartet das Hauptprogramm - auch wenn es
selbst nur `DateTime.Now.Ticks` (Paket `time`) aufruft. Ruft der Worker `Deflate` in einer Schleife ohne Pause, kommt das Hauptprogramm gar nicht mehr
dran (die Sperre geht sofort wieder an den Worker). Im Spiel entpacken drei bis vier Worker Chunks und den Netz-Cache, das Hauptprogramm liest
für sein Zeitbudget oft die Uhr: einzelne Bilder dauern dadurch 0,3 bis 1,3 s, quer durch alle Abschnitte des Nachladens (einzeln gemessen kostet
dort nichts mehr als ein paar ms, z. B. `Model.FromArrays` mit 16000 Vierecken 2,5 ms).

Gemessen (ein Worker, das Hauptprogramm baut Zeichenketten und liest je Runde die Uhr, 4 s):

| Worker | Runden | längste Runde |
|---|---|---|
| keiner | 215170 | 1,5 ms |
| rechnet nur | 214836 | 3,7 ms |
| legt große Arrays an | 188806 | 5,3 ms |
| `byte[].ReadFloat32` in Schleife | 197526 | 18 ms |
| `IO.File.Exists` in Schleife | 43175 | 7,9 ms |
| `DateTime.Now.Ticks` in Schleife | 65131 | 2,7 ms |
| `Deflate.Compress` + `Decompress` (8 MB) in Schleife | 975 | **14655 ms** |
| dasselbe mit `Sleep(1ms)` nach jedem Aufruf | 17925 | 25 ms |
| dasselbe mit Rechnen zwischen den Aufrufen | 160037 | 24 ms |

Nachbau:

```fire
#import "time"
#import "compression"
class Probe {
    static undefined Work(Channel<int> stop) {
        byte raw[] = new byte[8000000]
        for (int i = 0; i < raw.length; i++) { raw[i] = (i * 31 % 251) }
        while (stop.TryReceive() == undefined) {
            byte packed[] = Compression.Deflate.Compress(raw)
            byte back[] = Compression.Deflate.Decompress(packed)
        }
    }
    static defined int Main() {
        var stop = new Channel<int>(4)
        fire with stop { Probe.Work(stop) }
        int worst = 0
        int began = DateTime.Now.Ticks
        int last = began
        int rounds = 0
        while (DateTime.Now.Ticks - began < 40000000) {
            int now = DateTime.Now.Ticks
            if (now - last > worst) { worst = now - last }
            last = now
            rounds++
        }
        stop.Send(1)
        print(rounds + " Runden, längste " + (worst / 10000.0) + " ms")     // 975 Runden, längste 14655 ms
        return 0
    }
}
Environment.Exit(Probe.Main())
```

Wunsch: Natives ohne gemeinsamen Zustand (Deflate, Hash, die Uhr, Dateien lesen) ohne Sperre (`"threadSafe": true`) oder je Paket eine eigene, und
eine faire Übergabe. Vermutung (nicht geprüft): `time` und `compression` teilen sich eine Sperre (`PkgLock` in `CppGenerator.cs`).
Im Spiel bleibt es bis dahin bei den Rucklern beim Nachladen; `raser --live 60` misst sie (längstes Bild, je Abschnitt).

