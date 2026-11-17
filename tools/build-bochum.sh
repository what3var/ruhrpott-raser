#!/usr/bin/env bash
# Baut das Werkzeug nativ und rechnet die Testregion: Import -> Voxelisierung -> Draufsicht (world.png).
set -euo pipefail
cd "$(dirname "$0")/.."
FORGE=${FORGE:-forge}
"$FORGE" build RuhrpottRaser.firesln --engine native -m RELEASE
TOOL=src/Raser.Tool/bin/linux-rel/Raser.Tool
$TOOL import --dgm data/raw/dgm1 --lod2 data/raw/lod2 --osm data/raw/osm --world world
$TOOL voxelize --world world --overrides overrides
$TOOL export png --world world --step 4 --out world.png
