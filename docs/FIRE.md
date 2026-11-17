# Was Ruhrpott-Raser in fire findet

Das Projekt ist der Extremtest für fire. Hier steht, was dabei an fire auffällt und noch offen ist: Fehler, Lücken und Umwege, mit dem Stand, auf
dem es gefunden wurde. Erledigtes fliegt raus (die Geschichte steht in git). Zuletzt geprüft mit fire master a9d8598d.

## Sprache und Meldungen

| Fund | Umweg im Projekt | Stand |
|---|---|---|
| Statische Felder werden in Deklarationsreihenfolge initialisiert; ein Initialisierer, der ein später deklariertes statisches Feld liest, bekommt `undefined`. | Reihenfolge der Klassen in `voxel.fire` beachten | Verhalten, nicht dokumentiert |
| Ein Ausdruck kann nicht mit `&&` auf der nächsten Zeile weitergehen (Zeilenende beendet die Anweisung). | Eine Zeile | Verhalten |
| Ein Objekt, das einem Konstruktor übergeben und in einem Feld gespeichert wird, stirbt mit dem Aufrufer, wenn es ein Temporärwert war (`new Voxelizer(Sample.Make(), ...)`). | `try x.TakeTo(this)` in den Konstruktoren | Absicht (Besitzmodell); leicht zu vergessen, ein Hinweis des Typprüfers wäre hilfreich |

## scene3d

| Was | Warum | Stand |
|---|---|---|
| Nebel auch auf der GPU (laut Doku nur Fast und Software). | Hardware-Renderer | offen |
| Kacheln (`Scene.LightCulling`) und Spiegelungen (`Object.Reflectivity`) auch auf der GPU. | Hardware-Renderer | offen |

## Speicher

| Was | Umweg | Stand |
|---|---|---|
| **Ein neuer Container im selben Feld gibt den alten samt Inhalt nicht frei** (`this.d = new Dictionary<...>()`). Nachbau unten: 6 Runden mit je 20 Objekten à 16 MB - 2 → 1923 MB, nichts kommt zurück. | `Clear` statt eines neuen Containers | offen (a9d8598d) |
| **Ein Array-Feld auf `undefined` setzen gibt das Array nicht frei** - es hängt weiter am Objekt und geht mit ihm durch einen Kanal: ein Objekt mit einem Byte-Puffer, dessen `float`-Feld (2 Mio. Werte) vorher auf `undefined` gesetzt wurde, braucht beim `TryReceive` 47 ms (mit `delete` vorher 0,009 ms). Im Spiel waren das die Rest-Ruckler beim Nachladen (`MeshBatch.Pack`: 40 bis 210 ms je abgeholtem Block, mit `delete` höchstens 4 ms). | `delete this.f` vor `this.f = undefined` | offen (a9d8598d) |
| **Ein Objekt in einem Feld ersetzen gibt das alte nicht frei**: `this.one = take b` 60-mal mit je 16 MB, danach `this.one = undefined` - 1923 → 2883 MB. Im Spiel (`WorldView.making`, je Ergebnis eines Workers) wuchs der Speicher so in 48 s auf 12 GB (OOM). | das Objekt in einer `List` halten und mit `Clear` freigeben | offen (a9d8598d) |

```fire
class Big {
    defined float a[]
    construct() { this.a = new float[2000000] }
}
class Holder {
    Dictionary<int, Big> d
    Big one
    construct() { }
}
var h = new Holder()
float start = Environment.ProcessMemory / 1000000.0
for (int r = 0; r < 6; r++) {
    h.d = new Dictionary<int, Big>()
    for (int i = 0; i < 20; i++) {
        var b = new Big()
        h.d[i] = b
        b.TakeTo(h.d)
    }
}
print("neuer Container im Feld: " + Math.Round(start) + " -> " + Math.Round(Environment.ProcessMemory / 1000000.0) + " MB")   // 2 -> 1923 MB
start = Environment.ProcessMemory / 1000000.0
for (int r = 0; r < 60; r++) {
    var b = new Big()
    h.one = take b
}
h.one = undefined
print("Objekt im Feld ersetzt: " + Math.Round(start) + " -> " + Math.Round(Environment.ProcessMemory / 1000000.0) + " MB")    // 1923 -> 2883 MB
```

## Threads

- **Zahlen-Arrays kosten beim Abholen aus einem Kanal Zeit je Wert, Byte-Puffer nicht - auch mit `take`** (ein Worker schickt ein Objekt mit
  einem Array, das Hauptprogramm misst sein `TryReceive`). `Send(take x)` gibt laut Doku weiter wie `handover`; trotzdem kosten 2 Mio. Werte
  65 ms - ob als Array direkt (`Channel<float[]>`, `Send(take a)`), als Feld eines Objekts oder als frisches Ergebnis eines Aufrufs:

  | Inhalt | TryReceive |
  |---|---|
  | `float[]` mit 200 000 Werten | 2,4 ms |
  | `float[]` mit 2 000 000 Werten | 59 ms |
  | `int[]` mit 2 000 000 Werten | 51 ms |
  | `byte[]` mit 8 MB | 0,01 ms |

  Umweg in Raser: die Worker packen die Netze in float32-/uint32-Bytes (`MeshBatch.Pack`), `Model.FromArrays` nimmt sie direkt (das ist
  dort auch schneller: 16 statt 32 ms für das längste Netz).
- **`Sleep` im Hauptprogramm kommt nicht zurück, solange ein Pool-Worker in Natives rechnet** (gefunden beim Messen, nativ, 4 Kerne):

  ```fire
  #import "time"
  #import "compression"
  class Probe {
      static undefined Busy(Channel<int> stop) {
          byte raw[] = new byte[8000000]
          for (int i = 0; i < raw.length; i++) { raw[i] = (i * 31 % 251) }
          while (stop.TryReceive() == undefined) { byte packed[] = Compression.Deflate.Compress(raw) }
      }
      static defined int Main() {
          var stop = new Channel<int>(2)
          fire with stop { Probe.Busy(stop) }             // mit `fire dedicated` kommt Sleep nach 299 ms zurück
          int t0 = DateTime.Now.Ticks
          Sleep(300ms)
          print("zurück nach " + ((DateTime.Now.Ticks - t0) / 10000) + " ms")   // kommt nie (10 von 10 Läufen; unter strace schon)
          stop.Send(1)
          return 0
      }
  }
  Environment.Exit(Probe.Main())
  ```

  Laut gdb rechnet dabei der Haupt-Thread des Betriebssystems (in `Busy`), der zweite wartet in `pthread_cond_timedwait`: der Thread des
  Hauptprogramms übernimmt beim `Sleep` offenbar den Worker und kommt erst zurück, wenn der nachgibt - und `TryReceive` in der Schleife gibt
  nicht nach. Rechnet das Hauptprogramm vor dem `Sleep` 300 ms selbst (der Worker hat dann schon einen anderen Thread), kommt es zurück.
  Umweg in Raser: die Worker laufen mit `fire dedicated`.
- `Send(new float[n])` lehnt der Typprüfer mit TC029 ab („An object goes into a channel only with a word … - or fresh ('new', the result of a
  call)“) - für ein Array zählt `new` nicht als frisch, das Ergebnis eines Aufrufs schon.
