#!/usr/bin/env bash
# Der Ablauf des Launchers mit Netz, gegen den Ersatz-Server (mock_server.py) - ohne Fenster (--check).
#
#   src/Raser.Launcher/testing/check_test.sh <launcher-programm> [arbeitsordner]
#
# Prüft: frische Installation lädt alles, zweiter Lauf lädt nichts, eine geänderte Datei wird neu geladen, ein kaputter Download (falsche Bytes)
# wird abgelehnt und nicht installiert, falsches Passwort zeigt den Fehler, Registrieren (auch doppelt), ein Pfad mit .. in der Liste wird abgelehnt
# und nichts landet außerhalb, veraltete eigene Dateien werden entfernt, fremde bleiben, --play startet das Spiel mit den Argumenten.
set -u
LAUNCHER=$(realpath "$1")
WORK=${2:-$(mktemp -d)}
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${PORT:-17480}
mkdir -p "$WORK"
cd "$WORK" || exit 1
rm -rf rel inst cfg outside ctl.json
mkdir -p rel/bin rel/world cfg
export RASER_LAUNCHER_CONFIG=$WORK/cfg
echo '{}' > ctl.json
head -c 300000 /dev/urandom > rel/bin/data.bin
echo "Bochum" > rel/world/info.txt
# ein "Spiel", das seine Argumente ausgibt
printf '#!/bin/sh\necho "args: $*"\nexit 3\n' > rel/bin/game

python3 -I "$HERE/mock_server.py" --port "$PORT" --release rel --control ctl.json > mock.log 2>&1 &
MOCK=$!
trap 'kill $MOCK 2>/dev/null' EXIT
sleep 1

FAILS=0
ok() { echo "ok      $1"; }
bad() { echo "FAILED  $1"; FAILS=$((FAILS + 1)); }
run() { "$LAUNCHER" --check --server "127.0.0.1:$PORT" --install inst "$@" > out.txt 2>&1; echo $?; }
has() { grep -qF -- "$1" out.txt; }

code=$(run --user anna --password geheim1)
if [ "$code" = 0 ] && has "Angemeldet als anna" && has "geladen bin/data.bin" && has "Version 0.1.3" && has "Launcher da" \
   && cmp -s rel/bin/data.bin inst/bin/data.bin && cmp -s rel/world/info.txt inst/world/info.txt; then ok "frische Installation lädt alles"; else bad "frische Installation"; cat out.txt; fi
if grep -q geheim1 cfg/launcher.json || ! grep -q '"user": "anna"' cfg/launcher.json; then bad "Einstellungen (Name ja, Passwort nein)"; else ok "Einstellungen merken den Namen, nicht das Passwort"; fi

code=$(run)
if [ "$code" = 0 ] && has "Installation ist aktuell (3 Dateien)" && ! has "geladen"; then ok "zweiter Lauf lädt nichts"; else bad "zweiter Lauf"; cat out.txt; fi

head -c 5000 /dev/urandom > rel/bin/data.bin
code=$(run)
if [ "$code" = 0 ] && has "1 Datei" && has "geladen bin/data.bin" && cmp -s rel/bin/data.bin inst/bin/data.bin; then ok "geänderte Datei wird neu geladen"; else bad "geänderte Datei"; cat out.txt; fi

cp inst/bin/data.bin before.bin
head -c 5000 /dev/urandom > rel/bin/data.bin
echo '{"corrupt": ["bin/data.bin"]}' > ctl.json
code=$(run)
if [ "$code" = 1 ] && has "Prüfsumme falsch" && cmp -s before.bin inst/bin/data.bin && [ ! -e inst/.raser-tmp ]; then ok "kaputter Download wird abgelehnt, die alte Datei bleibt"; else bad "kaputter Download"; cat out.txt; ls -la inst inst/bin; fi
echo '{}' > ctl.json
code=$(run)
if [ "$code" = 0 ] && cmp -s rel/bin/data.bin inst/bin/data.bin; then ok "danach lädt er die richtige"; else bad "nach kaputtem Download"; cat out.txt; fi

code=$(run --user anna --password falsch)
if [ "$code" = 2 ] && has "FEHLER Anmeldung: Name oder Passwort falsch (HTTP 401)"; then ok "falsches Passwort zeigt den Fehler"; else bad "falsches Passwort"; cat out.txt; fi
code=$(run --user bert --password geheim2 --register --no-update)
if [ "$code" = 0 ] && has "Registriert und angemeldet als bert"; then ok "registrieren"; else bad "registrieren"; cat out.txt; fi
code=$(run --user bert --password geheim2 --register --no-update)
if [ "$code" = 2 ] && has "gibt es schon" && has "HTTP 409"; then ok "doppelt registrieren zeigt den Fehler"; else bad "doppelt registrieren"; cat out.txt; fi

for evil in "../outside/evil.txt" "/tmp/raser-evil.txt" "bin/../../outside/evil.txt"; do
  echo "{\"extra\": [{\"path\": \"$evil\", \"size\": 4, \"sha256\": \"$(printf boes | sha256sum | cut -d' ' -f1)\"}]}" > ctl.json
  code=$(run)
  if [ "$code" = 1 ] && has "unsicherer Pfad" && [ ! -e outside ] && [ ! -e /tmp/raser-evil.txt ]; then ok "Pfad $evil wird abgelehnt"; else bad "Pfad $evil"; cat out.txt; fi
done
echo '{}' > ctl.json

echo "fremd" > inst/fremd.txt
rm rel/world/info.txt
code=$(run)
if [ "$code" = 0 ] && has "entfernt world/info.txt" && [ ! -e inst/world/info.txt ] && [ -e inst/fremd.txt ]; then ok "veraltete eigene Datei entfernt, fremde bleibt"; else bad "veraltete Dateien"; cat out.txt; fi

code=$(run --user anna --password geheim1 --play)
if [ "$code" = 4 ] && has "spiel: args: --server 127.0.0.1:7481 --token tok-" && has "--user anna" && has "Spiel beendet mit Code 3"; then ok "--play startet das Spiel mit Server, Token und Name"; else bad "--play"; cat out.txt; fi

kill $MOCK 2>/dev/null
code=$(run)
if [ "$code" = 3 ] && has "FEHLER Status"; then ok "Server weg: Fehler statt Absturz"; else bad "Server weg"; cat out.txt; fi

echo "$FAILS Fehler"
[ "$FAILS" = 0 ]
