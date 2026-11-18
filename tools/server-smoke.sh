#!/usr/bin/env bash
# Probe des Servers von Hand (docs/SERVER.md, Protokoll v2): Server starten, über HTTP registrieren und anmelden, Bots verbinden, Chat, Befehle,
# autoritative Physik, Vorhersage, Inventar und Schummeln prüfen.
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

"$SERVER" --data "$WORK/data" --release "$WORK/release" --time 14:00 --http "$HP" --game "$GP" "${WORLDARG[@]}" ${SERVER_ARGS:-} > "$WORK/server.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for i in $(seq 1 50); do curl -s "$API/api/status" > /dev/null && break; sleep 0.2; done

token() { sed -n 's/.*"token": "\([0-9a-f]*\)".*/\1/p'; }
A=$(curl -s -X POST -d '{"user": "Anna", "password": "geheim123"}' "$API/api/register" | token)
B=$(curl -s -X POST -d '{"user": "Bernd", "password": "geheim456"}' "$API/api/register" | token)
C=$(curl -s -X POST -d '{"user": "Carla", "password": "geheim789"}' "$API/api/register" | token)
echo "register: 409 erwartet -> $(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"user": "anna", "password": "geheim123"}' "$API/api/register")"
echo "login falsch: 401 erwartet -> $(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"user": "Anna", "password": "falsch!!"}' "$API/api/login")"
B=$(curl -s -X POST -d '{"user": "Bernd", "password": "geheim456"}' "$API/api/login" | token)
echo "version: $(curl -s "$API/api/version")"
[ -n "$A" ] && [ -n "$B" ] && [ -n "$C" ] || { echo "kein Token"; cat "$WORK/server.log"; exit 1; }

# Runde 1: Chat und Befehle; beide fahren im Kreis (Eingaben je Takt, der Server rechnet). Bernd versucht Admin-Befehle (abgelehnt), Anna darf sie.
"$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 12 --at 376300,5705000 --say "Hallo Anna!;/time 22:00;/help" > "$WORK/bernd.log" 2>&1 &
BP=$!
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 12 --at 376100,5705000 "${WORLDARG[@]}" --say "Moin Bernd!;/players;/weather nebel;/time 20:30;/tp Bernd;/say Glueck auf" > "$WORK/anna.log" 2>&1 &
AP=$!
"$GAME" --server 127.0.0.1:$GP --token "falsch" --user Anna --bot 2 > "$WORK/falsch.log" 2>&1
wait $BP $AP

# Runde 2: Anna fährt, hält, steigt aus und setzt ihren Rucksack ab; Bernd (zu Fuß) setzt seinen ab, geht zu Annas und hebt ihn auf; Carla schummelt
# (doppelt so viele Eingaben, dann eine Lage wie in v1).
"$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 25 --plan aufheben --vehicle fuss --at 376100,5705000 > "$WORK/bernd2.log" 2>&1 &
BP=$!
"$GAME" --server 127.0.0.1:$GP --token "$C" --user Carla --bot 8 --plan schummeln --at 376300,5705000 > "$WORK/carla.log" 2>&1 &
CP=$!
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 25 --plan ablegen --at 376100,5705000 "${WORLDARG[@]}" > "$WORK/anna2.log" 2>&1 &
AP=$!
wait $BP $CP $AP

# Runde 3: Anna fährt Bernd (zu Fuß) um - Bernd verliert Bargeld und Gegenstände, Anna sammelt sie auf; dann meldet Anna sich neu an: ihr Bargeld
# kommt aus der Datenbank.
"$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 25 --plan stehen --vehicle fuss --at 376100,5705030 > "$WORK/bernd3.log" 2>&1 &
BP=$!
sleep 1
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 24 --plan umfahren --target Bernd --at 376100,5705000 "${WORLDARG[@]}" > "$WORK/anna3.log" 2>&1
wait $BP
sleep 1
"$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 3 --plan stehen --vehicle fuss --at 376100,5705000 > "$WORK/anna4.log" 2>&1
# Runde 4 (nur mit Welt): der Verkehr rechnet der Server - Anna und Bernd stehen am selben Ort und sehen dieselben NPCs an derselben Stelle.
if [ -n "$WORLD" ]; then
  "$GAME" --server 127.0.0.1:$GP --token "$B" --user Bernd --bot 14 --plan stehen --at 376117,5705005 > "$WORK/bernd5.log" 2>&1 &
  BP=$!
  "$GAME" --server 127.0.0.1:$GP --token "$A" --user Anna --bot 14 --plan stehen --at 376117,5705005 > "$WORK/anna5.log" 2>&1 &
  AP=$!
  wait $BP $AP
fi

echo "status: $(curl -s "$API/api/status")"
for f in anna bernd falsch anna2 bernd2 carla anna3 bernd3 anna4 anna5 bernd5; do echo "=== $f"; [ -f "$WORK/$f.log" ] && grep -v "sieht:\|\] npc " "$WORK/$f.log"; done
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
check "$WORK/bernd.log" "Server-Lage .*, \([5-9]\|[1-3][0-9]\) m vom Start" "Bernds Wagen fährt auf dem Server"
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
if [ -n "$WORLD" ]; then
  npcs() { awk '/\] npc /{print $3" "$4" "$5" "$6}' "$1"; }
  npcs "$WORK/anna5.log" > "$WORK/npc_anna"
  npcs "$WORK/bernd5.log" > "$WORK/npc_bernd"
  read SAME BAD <<< "$(awk 'NR==FNR{a[$1" "$2]=$3" "$4;next} ($1" "$2) in a {n++; if (a[$1" "$2]!=$3" "$4) bad++} END{print n+0, bad+0}' "$WORK/npc_anna" "$WORK/npc_bernd")"
  echo "Verkehr: $SAME NPC-Lagen in beiden Logs zum selben Takt, $BAD verschieden"; grep -h "Verkehr in Sicht" "$WORK"/anna5.log "$WORK"/bernd5.log
  if [ "$SAME" -ge 10 ] && [ "$BAD" = 0 ]; then echo "ok: beide sehen dieselben NPCs an derselben Stelle"; else echo "FEHLT: beide sehen dieselben NPCs an derselben Stelle"; ok=0; fi
fi
echo "Vorhersage:"; grep -h "Vorhersage:" "$WORK"/anna*.log "$WORK"/bernd*.log
echo "Bandbreite:"; grep -h "Bandbreite:" "$WORK"/anna*.log "$WORK"/bernd*.log
[ $ok = 1 ] && echo "ALLES OK" || exit 1
