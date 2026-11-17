#!/usr/bin/env bash
# Probe des Servers von Hand (docs/SERVER.md): Server starten, über HTTP registrieren und anmelden, zwei Bots verbinden (Anna ist Admin, Bernd
# nicht), Chat und Befehle prüfen. Aufruf: tools/server-smoke.sh <raser-server> <raser-game> [arbeitsverzeichnis]
set -u
SERVER=${1:?raser-server}
GAME=${2:?raser-game}
WORK=${3:-$(mktemp -d)}
mkdir -p "$WORK/release/bin"
rm -rf "$WORK/data"
echo "spiel" > "$WORK/release/bin/game"
printf '0.1.3\nProbe.\n' > "$WORK/release/version.txt"
API=http://127.0.0.1:7480

"$SERVER" --data "$WORK/data" --release "$WORK/release" --time 14:00 > "$WORK/server.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for i in $(seq 1 50); do curl -s "$API/api/status" > /dev/null && break; sleep 0.2; done

token() { sed -n 's/.*"token": "\([0-9a-f]*\)".*/\1/p'; }
A=$(curl -s -X POST -d '{"user": "Anna", "password": "geheim123"}' "$API/api/register" | token)
B=$(curl -s -X POST -d '{"user": "Bernd", "password": "geheim456"}' "$API/api/register" | token)
echo "register: 409 erwartet -> $(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"user": "anna", "password": "geheim123"}' "$API/api/register")"
echo "login falsch: 401 erwartet -> $(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"user": "Anna", "password": "falsch!!"}' "$API/api/login")"
B=$(curl -s -X POST -d '{"user": "Bernd", "password": "geheim456"}' "$API/api/login" | token)
echo "version: $(curl -s "$API/api/version")"
[ -n "$A" ] && [ -n "$B" ] || { echo "kein Token"; cat "$WORK/server.log"; exit 1; }

# Bernd versucht Admin-Befehle (abgelehnt), Anna darf sie
"$GAME" --server 127.0.0.1:7481 --token "$B" --user Bernd --bot 12 --at 376120,5705010 --say "Hallo Anna!;/time 22:00;/help" > "$WORK/bernd.log" 2>&1 &
BP=$!
"$GAME" --server 127.0.0.1:7481 --token "$A" --user Anna --bot 12 --at 376100,5705000 --say "Moin Bernd!;/players;/weather nebel;/time 20:30;/tp Bernd;/say Glueck auf" > "$WORK/anna.log" 2>&1 &
AP=$!
"$GAME" --server 127.0.0.1:7481 --token "falsch" --user Anna --bot 2 > "$WORK/falsch.log" 2>&1
wait $BP $AP
echo "status: $(curl -s "$API/api/status")"
echo "=== Anna"; cat "$WORK/anna.log"
echo "=== Bernd"; cat "$WORK/bernd.log"
echo "=== falsches Token"; cat "$WORK/falsch.log"
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
check "$WORK/anna.log" "Teleport nach" "Anna springt zu Bernd"
check "$WORK/falsch.log" "abgelehnt" "falsches Token abgelehnt"
[ $ok = 1 ] && echo "ALLES OK" || exit 1
