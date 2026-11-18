#!/usr/bin/env bash
# Probe des Servers von Hand (docs/SERVER.md, Protokoll v3): Server starten, über HTTP registrieren und anmelden, Bots verbinden, Chat, Befehle,
# autoritative Physik, Vorhersage, Inventar, Schummeln, gespeicherte Stände (auch über einen Neustart des Servers), Startpunkt vom Server, zu Fuß
# gegen zu Fuß und die Bandbreite prüfen. Jeder Spieler macht in der nächsten Runde dort weiter, wo er aufgehört hat.
# Aufruf: tools/server-smoke.sh <raser-server> <raser-game> [arbeitsverzeichnis] [welt]
#   welt: das Verzeichnis der Welt (Kacheln) - dann rechnet der Server mit Hindernissen, und Anna sagt mit denselben Kacheln voraus (nur ein Bot
#   lädt die Welt).
set -u
SERVER=${1:?raser-server}
GAME=${2:?raser-game}
WORK=${3:-$(mktemp -d)}
WORLD=${4:-}
mkdir -p "$WORK/release/bin"
rm -rf "$WORK/data"
echo "spiel" > "$WORK/release/bin/game"
printf '0.2.0\nProbe.\n' > "$WORK/release/version.txt"
# andere Ports: HTTP_PORT=17480 GAME_PORT=17481 tools/server-smoke.sh ...; weitere Optionen des Servers: SERVER_ARGS="--traffic 0 --people 0"
HP=${HTTP_PORT:-7480}
GP=${GAME_PORT:-7481}
API=http://127.0.0.1:$HP
WORLDARG=()
[ -n "$WORLD" ] && WORLDARG=(--world "$WORLD")

start_server() {
  "$SERVER" --data "$WORK/data" --release "$WORK/release" --time 14:00 --http "$HP" --game "$GP" "${WORLDARG[@]}" ${SERVER_ARGS:-} >> "$WORK/server.log" 2>&1 &
  PID=$!
  for i in $(seq 1 50); do curl -s "$API/api/status" > /dev/null && break; sleep 0.2; done
}
rm -f "$WORK/server.log"
start_server
trap 'kill $PID 2>/dev/null' EXIT

token() { sed -n 's/.*"token": "\([0-9a-f]*\)".*/\1/p'; }
A=$(curl -s -X POST -d '{"user": "Anna", "password": "geheim123"}' "$API/api/register" | token)
B=$(curl -s -X POST -d '{"user": "Bernd", "password": "geheim456"}' "$API/api/register" | token)
C=$(curl -s -X POST -d '{"user": "Carla", "password": "geheim789"}' "$API/api/register" | token)
D=$(curl -s -X POST -d '{"user": "Dora", "password": "geheim321"}' "$API/api/register" | token)
E=$(curl -s -X POST -d '{"user": "Erik", "password": "geheim654"}' "$API/api/register" | token)
echo "register: 409 erwartet -> $(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"user": "anna", "password": "geheim123"}' "$API/api/register")"
echo "login falsch: 401 erwartet -> $(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"user": "Anna", "password": "falsch!!"}' "$API/api/login")"
B=$(curl -s -X POST -d '{"user": "Bernd", "password": "geheim456"}' "$API/api/login" | token)
echo "version: $(curl -s "$API/api/version")"
[ -n "$A" ] && [ -n "$B" ] && [ -n "$C" ] || { echo "kein Token"; cat "$WORK/server.log"; exit 1; }

# Runde 1: Chat und Befehle; Bernd fährt im Kreis, Anna geradeaus (Eingaben je Takt, der Server rechnet). Bernd versucht Admin-Befehle (abgelehnt),
# Anna darf sie. Bernd wünscht sich einen Startpunkt 4 km weiter - der Server nimmt seinen eigenen.
"$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 12 --at 380000,5708000 --say "Hallo Anna!;/time 22:00;/help" > "$WORK/bernd.log" 2>&1 &
BP=$!
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 12 --plan gerade --at 376100,5705000 "${WORLDARG[@]}" --say "Moin Bernd!;/players;/weather nebel;/time 20:30;/tp Bernd;/say Glueck auf" > "$WORK/anna.log" 2>&1 &
AP=$!
"$GAME" --server 127.0.0.1:$GP --token "falsch" --user Anna --bot 2 > "$WORK/falsch.log" 2>&1
wait $BP $AP

# Runde 2: Anna fährt, hält, steigt aus und setzt ihren Rucksack ab; Bernd (zu Fuß) setzt seinen ab, geht zu Annas und hebt ihn auf.
"$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 40 --plan aufheben --vehicle fuss --at 376100,5705000 > "$WORK/bernd2.log" 2>&1 &
BP=$!
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 40 --plan ablegen --at 376100,5705000 "${WORLDARG[@]}" > "$WORK/anna2.log" 2>&1 &
AP=$!
wait $BP $AP

# Runde 3: Anna fährt Bernd (zu Fuß) um - Bernd verliert Bargeld und Gegenstände, Anna sammelt sie auf; dann meldet Anna sich neu an: ihr Bargeld
# kommt aus der Datenbank.
"$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 40 --plan stehen --vehicle fuss --at 376100,5705030 > "$WORK/bernd3.log" 2>&1 &
BP=$!
sleep 1
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 38 --plan umfahren --target Bernd --tp 1 --at 376100,5705000 "${WORLDARG[@]}" > "$WORK/anna3.log" 2>&1
wait $BP
sleep 1
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 3 --plan stehen --vehicle fuss --at 376100,5705000 > "$WORK/anna4.log" 2>&1
# Runde 4: Carla schummelt allein (doppelt so viele Eingaben, dann eine Lage wie in v1) - allein, damit ihr Wagen niemanden umfährt.
"$GAME" --server 127.0.0.1:$GP --token "$C" --user Carla --bot 8 --plan schummeln --at 376300,5705000 > "$WORK/carla.log" 2>&1
# Runde 5: Dora (neu) geht 3 s, meldet sich neu an (Stand wie zuletzt), dann startet der Server neu, Dora wieder (Stand wie zuletzt).
"$GAME" --server 127.0.0.1:$GP --token "$D" --user Dora --bot 6 --plan gehen --vehicle fuss --at 390000,5710000 > "$WORK/dora1.log" 2>&1
"$GAME" --server 127.0.0.1:$GP --token "$D" --user Dora --bot 5 --plan gehen > "$WORK/dora2.log" 2>&1
# (eine Sekunde, damit der Server das Gehen verarbeitet und speichert; ein harter Abbruch verliert höchstens die letzten 10 s)
sleep 1
kill $PID; wait $PID 2>/dev/null
start_server
D=$(curl -s -X POST -d '{"user": "Dora", "password": "geheim321"}' "$API/api/login" | token)
A=$(curl -s -X POST -d '{"user": "Anna", "password": "geheim123"}' "$API/api/login" | token)
B=$(curl -s -X POST -d '{"user": "Bernd", "password": "geheim456"}' "$API/api/login" | token)
E=$(curl -s -X POST -d '{"user": "Erik", "password": "geheim654"}' "$API/api/login" | token)
"$GAME" --server 127.0.0.1:$GP --token "$D" --user Dora --bot 4 --plan stehen > "$WORK/dora3.log" 2>&1
# Runde 6: Dora und Erik (zu Fuß) laufen aufeinander zu - sie überlappen nicht.
"$GAME" --server 127.0.0.1:$GP --token "$E" --user Erik --bot 12 --plan zueinander --target Dora --vehicle fuss > "$WORK/erik.log" 2>&1 &
EP=$!
"$GAME" --server 127.0.0.1:$GP --token "$D" --user Dora --bot 12 --plan zueinander --target Erik > "$WORK/dora4.log" 2>&1
wait $EP
# Runde 7 (nur mit Welt): der Verkehr rechnet der Server - Anna und Bernd stehen am selben Ort und sehen dieselben NPCs an derselben Stelle;
# gemessen wird die Bandbreite.
if [ -n "$WORLD" ]; then
  "$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 14 --plan stehen --at 376117,5705005 > "$WORK/bernd5.log" 2>&1 &
  BP=$!
  "$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 14 --plan stehen --at 376117,5705005 > "$WORK/anna5.log" 2>&1 &
  AP=$!
  wait $BP $AP
fi

echo "status: $(curl -s "$API/api/status")"
for f in anna bernd falsch anna2 bernd2 carla anna3 bernd3 anna4 dora1 dora2 dora3 dora4 erik anna5 bernd5; do echo "=== $f"; [ -f "$WORK/$f.log" ] && grep -v "sieht:\|\] npc " "$WORK/$f.log"; done
echo "=== Server"; cat "$WORK/server.log"

ok=1
check() { if grep -q "$2" "$1"; then echo "ok: $3"; else echo "FEHLT: $3"; ok=0; fi; }
check "$WORK/anna.log" "sieht:.*Bernd" "Anna sieht Bernd"
check "$WORK/bernd.log" "sieht:.*Anna" "Bernd sieht Anna"
check "$WORK/anna.log" "<Bernd> Hallo Anna!" "Anna liest Bernds Chat"
check "$WORK/bernd.log" "<Anna> Moin Bernd!" "Bernd liest Annas Chat"
check "$WORK/bernd.log" "/time dürfen nur Admins" "Admin-Befehl von Bernd abgelehnt"
check "$WORK/bernd.log" "Anna stellt das Wetter auf nebel" "Admin-Befehl von Anna wirkt"
check "$WORK/bernd.log" "Wetter nebel" "Bernd hat das Wetter des Servers"
check "$WORK/anna.log" "Teleport nach" "Anna springt zu Bernd (der Server setzt die Lage)"
check "$WORK/falsch.log" "abgelehnt" "falsches Token abgelehnt"
# die Lage folgt den Eingaben: der Server hat den Wagen bewegt (im Kreis: 5 bis 40 m vom Startpunkt, den der Server gewählt hat)
check "$WORK/bernd.log" "am weitesten \([5-9]\|[1-9][0-9]\) m" "Bernds Wagen fährt auf dem Server"
check "$WORK/anna2.log" "Rucksack abgesetzt" "Anna setzt den Rucksack ab"
check "$WORK/bernd2.log" "Inhalt:.*Flasche Wasser x2" "Bernd hebt Annas Rucksack auf und sieht den Inhalt"
check "$WORK/carla.log" "hinausgeworfen: Protokoll v1" "eine Lage vom Client wirft hinaus"
# doppelt so viele Eingaben: der Server rechnet trotzdem nur 30 je s (Vollgas aus dem Stand in 4 s: höchstens ~45 m)
if grep -q "Server-Strecke \([0-9]\|[1-3][0-9]\|4[0-5]\)\(\.[0-9]\)\? m" "$WORK/carla.log"; then echo "ok: Schummeln bringt nichts"; else echo "FEHLT: Schummeln bringt nichts"; ok=0; fi
check "$WORK/bernd3.log" "umgehauen von Anna: Bargeld" "Bernd wird umgefahren und verliert"
check "$WORK/anna3.log" "aufgesammelt: [1-9]" "Anna sammelt Bernds Sachen auf"
check "$WORK/anna3.log" "sieht die Taschenlampe von Bernd" "Bernd schaltet die Lampe ein (Use), Anna sieht sie im Snapshot"
CASH=$(sed -n 's/.*Bargeld jetzt \([0-9]*\) Cent.*/\1/p' "$WORK/anna3.log")
if [ -n "$CASH" ] && grep -q "Bargeld $CASH Cent" "$WORK/anna4.log"; then echo "ok: Annas Bargeld ($CASH Cent) bleibt in der Datenbank"; else echo "FEHLT: Annas Bargeld bleibt in der Datenbank"; ok=0; fi
# der Startpunkt kommt vom Server: Bernd und Dora wünschten sich weit weg, beide fangen am Spawn-Punkt an (bis 300 m davon)
near_spawn() { sed -n 's/.*Stand am Anfang: Lage \([0-9]*\),\([0-9]*\).*/\1 \2/p' "$1" | head -1 | awk '{d=sqrt(($1/100-376117)^2+($2/100-5705005)^2); exit !(d < 300)}'; }
if near_spawn "$WORK/bernd.log" && near_spawn "$WORK/dora1.log"; then echo "ok: der Startpunkt vom Client zählt nicht"; else echo "FEHLT: der Startpunkt vom Client zählt nicht"; ok=0; fi
# der Stand nach dem Neuanmelden und nach dem Neustart des Servers: genau wie am Ende davor
same_stand() { E1=$(sed -n 's/.*Stand am Ende: //p' "$1"); S2=$(sed -n 's/.*Stand am Anfang: //p' "$2"); [ -n "$E1" ] && [ "$E1" = "$S2" ]; }
if same_stand "$WORK/dora1.log" "$WORK/dora2.log"; then echo "ok: Inventar und Lage nach dem Neuanmelden gleich"; else echo "FEHLT: Inventar und Lage nach dem Neuanmelden gleich"; ok=0; fi
if same_stand "$WORK/dora2.log" "$WORK/dora3.log"; then echo "ok: Inventar und Lage nach dem Neustart des Servers gleich"; else echo "FEHLT: Inventar und Lage nach dem Neustart des Servers gleich"; ok=0; fi
# (Bernd: nur Bargeld und Inventar - seine Lage darf der Server um 1 m verschieben, wenn dort schon jemand steht)
same_inv() { E1=$(sed -n 's/.*Stand am Ende: .*\(Bargeld.*\)/\1/p' "$1"); S2=$(sed -n 's/.*Stand am Anfang: .*\(Bargeld.*\)/\1/p' "$2"); [ -n "$E1" ] && [ "$E1" = "$S2" ]; }
if same_inv "$WORK/bernd3.log" "$WORK/bernd5.log" || [ -z "$WORLD" ]; then echo "ok: Bernds Inventar (nach dem Umhauen) über den Neustart"; else echo "FEHLT: Bernds Inventar über den Neustart"; ok=0; fi
# zu Fuß gegen zu Fuß: nie näher als 0,7 m (bis auf die cm der Snapshots)
least() { sed -n 's/.*kleinster Abstand zu [A-Za-z]*: \([0-9.]*\) m.*/\1/p' "$1"; }
LD=$(least "$WORK/dora4.log"); LE=$(least "$WORK/erik.log")
if [ -n "$LD" ] && awk -v a="$LD" -v b="$LE" 'BEGIN{exit !(a >= 0.68 && b >= 0.68 && a < 2.0)}'; then echo "ok: zwei Spieler zu Fuß überlappen nicht ($LD m / $LE m)"; else echo "FEHLT: zwei Spieler zu Fuß überlappen nicht ($LD / $LE)"; ok=0; fi
if [ -n "$WORLD" ]; then
  BW=$(sed -n 's/.*Bandbreite: empfangen \([0-9]*\) B\/s.*/\1/p' "$WORK/anna5.log")
  if [ -n "$BW" ] && [ "$BW" -lt 8000 ]; then echo "ok: Bandbreite mit Verkehr $BW B/s (unter 8000)"; else echo "FEHLT: Bandbreite mit Verkehr unter 8000 B/s ($BW)"; ok=0; fi
  npcs() { awk '/\] npc /{print $3" "$4" "$5" "$6}' "$1"; }
  npcs "$WORK/anna5.log" > "$WORK/npc_anna"
  npcs "$WORK/bernd5.log" > "$WORK/npc_bernd"
  read SAME BAD <<< "$(awk 'NR==FNR{a[$1" "$2]=$3" "$4;next} ($1" "$2) in a {n++; if (a[$1" "$2]!=$3" "$4) bad++} END{print n+0, bad+0}' "$WORK/npc_anna" "$WORK/npc_bernd")"
  echo "Verkehr: $SAME NPC-Lagen in beiden Logs zum selben Takt, $BAD verschieden"; grep -h "Verkehr in Sicht" "$WORK"/anna5.log "$WORK"/bernd5.log
  if [ "$SAME" -ge 10 ] && [ "$BAD" = 0 ]; then echo "ok: beide sehen dieselben NPCs an derselben Stelle"; else echo "FEHLT: beide sehen dieselben NPCs an derselben Stelle"; ok=0; fi
fi
echo "Vorhersage:"; grep -h "Vorhersage:" "$WORK"/anna*.log "$WORK"/bernd*.log "$WORK"/dora*.log "$WORK"/erik.log
echo "Bandbreite:"; grep -h "Bandbreite:\|Verkehr in Sicht" "$WORK"/anna*.log "$WORK"/bernd*.log "$WORK"/dora*.log "$WORK"/erik.log
[ $ok = 1 ] && echo "ALLES OK" || exit 1
