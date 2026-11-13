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
