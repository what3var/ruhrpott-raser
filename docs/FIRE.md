# Was Ruhrpott-Raser in fire findet

Das Projekt ist der Extremtest für fire. Hier steht, was dabei an fire auffällt und noch offen ist: Fehler, Lücken und Umwege, mit dem Stand, auf
dem es gefunden wurde. Erledigtes fliegt raus (die Geschichte steht in git). Zuletzt geprüft mit fire master a9d8598d.

## Sprache und Meldungen

| Fund | Umweg im Projekt | Stand |
|---|---|---|
| Statische Felder werden in Deklarationsreihenfolge initialisiert; ein Initialisierer, der ein später deklariertes statisches Feld liest, bekommt `undefined`. | Reihenfolge der Klassen in `voxel.fire` beachten | **muss behoben werden:** der Compiler soll zur Compilezeit ermitteln, welcher Initialisierer von welchem statischen Feld abhängt, und in dieser Reihenfolge initialisieren (ein Zyklus ist ein Fehler) |
| Ein Ausdruck kann nicht mit `&&` auf der nächsten Zeile weitergehen (Zeilenende beendet die Anweisung). | Eine Zeile | Verhalten |
| Ein Objekt, das einem Konstruktor übergeben und in einem Feld gespeichert wird, stirbt mit dem Aufrufer, wenn es ein Temporärwert war (`new Voxelizer(Sample.Make(), ...)`). | `try x.TakeTo(this)` in den Konstruktoren | Absicht (Besitzmodell); leicht zu vergessen, ein Hinweis des Typprüfers wäre hilfreich |
| **Wunsch: ein Schlüsselwort `replace`** für das Überschreiben eines Felds: es löscht das bisherige Objekt (bzw. Array, Container), wenn es im Besitz des Objekts ist, und setzt dann den neuen Wert. Hintergrund: ein Feld neu zu belegen (`this.d = new Dictionary<...>()`, `this.one = take b`, `this.a = undefined`) gibt das Alte **absichtlich nicht** frei - sonst müsste fire jedes Mal sämtliche Referenzen auf das Objekt und alle seine Kinder prüfen. Das Löschen darf deshalb **niemals implizit** passieren, nur mit `replace`. | heute `delete this.f` vor dem Überschreiben (`MeshBatch.Pack`), bzw. `List` + `Clear` (`WorldView.making`) | Idee |

| Elemente mit `RemoveAt` aus einer Liste nehmen, die aus `Json.Deserialize` kam, und die Liste danach wieder schreiben: „A value to write to JSON is destroyed“ (gefunden in Raser.Greens mit fire master, nativ). | die Liste mit `TakeAt` umlegen und die behaltenen mit `take` zurück | offen |

## scene3d

| Was | Warum | Stand |
|---|---|---|
| Nebel auch auf der GPU (laut Doku nur Fast und Software). | Hardware-Renderer | offen |
| Kacheln (`Scene.LightCulling`) und Spiegelungen (`Object.Reflectivity`) auch auf der GPU. | Hardware-Renderer | offen |

## scene3d: gemischt oder nicht

- Eine Textur mit auch nur einem durchsichtigen Texel macht jedes Objekt mit ihr zu einem gemischten (`blended`, `s3d_engine.h`: `tex->hasAlpha`),
  auch bei `Opacity = 1`. Auf der GPU schreiben gemischte Objekte keine Tiefe - der Nebel (aus der Tiefe gerechnet) deckt sie dann ganz zu: im Spiel
  war mit `--gpu 1` die ganze Welt verschwunden (der Atlas hat Glas-Texel), nur die Fahrzeuge aus Quadern waren zu sehen. Software zeichnet sie
  richtig. Umweg in Raser: `AlphaCutoff = 0.5` für die undurchsichtigen Netze. Wunsch: Software und GPU gleich (gemischte Objekte im Nebel wie in
  Software), oder `hasAlpha` nur, wenn das Objekt durchsichtige Texel wirklich benutzt.

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

## Netz

- **Kein Rückfall auf IPv4 bei leerem Host:** `new Net.TcpListener("", port)` und `new Http.Server("", port)` lauschen auf IPv6 (mit IPv4 darin);
  hat der Rechner kein IPv6 (ein Container nach dem Neustart), werfen beide „socket: Address family not supported by protocol“, statt auf
  `0.0.0.0` zurückzufallen. Umweg in raser-server (`Server.ListenHost`): erst leer probieren, sonst `0.0.0.0`. Wunsch: der Rückfall in fire.

- **`Http.Download` kann keine Antworten mit `Transfer-Encoding: chunked`** („A chunked download is not supported.“). Die OSM-API
  (`api.openstreetmap.org/api/0.6/map`) antwortet so; DGM1/LoD2 von opengeodata.nrw.de gehen. Umweg in `raser fetch` (src/Raser.Tool/setup.fire):
  für OSM `Http.Client.Get` (ganz in den Speicher, dann über eine Teildatei schreiben). Wunsch: chunked in `Http.Download` (fortsetzen geht
  dann nicht, laden schon). Stand fire master 6db80cbb.

