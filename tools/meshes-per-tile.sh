#!/bin/bash
# Baut den Netz-Cache Kachel für Kachel, je ein Prozess (der Speicher wächst im Netzbau je Kachel um rund 350 MB - docs/FIRE.md).
# TOOL: das gebaute Werkzeug (Raser.Tool).
cd "$(dirname "$0")/.."
for t in $(ls world/tiles/*.rrh | xargs -n1 basename | sed 's/.rrh//'); do ${TOOL:-./raser} meshes --world world --tile $t | tail -1; done
