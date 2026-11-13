#!/usr/bin/env bash
# Lädt die Rohdaten der Testregion Bochum-Innenstadt (2 x 2 km, UTM 32: Ost 375000-377000, Nord 5704000-5706000) nach data/raw/.
#   DGM1 (GeoTIFF) und LoD2 (CityGML) von Geobasis NRW (Datenlizenz Deutschland - Zero - Version 2.0),
#   OSM als XML über die OSM-API in 16 Ausschnitten (ODbL; die API erlaubt je Abfrage höchstens 50 000 Knoten).
# Die Dateien landen nicht im Repo (.gitignore).
set -euo pipefail
cd "$(dirname "$0")/.."
NRW=https://www.opengeodata.nrw.de/produkte/geobasis
mkdir -p data/raw/dgm1 data/raw/lod2 data/raw/osm

for t in 375_5704 375_5705 376_5704 376_5705; do
  # DGM1: der Dateiname trägt das Jahr der Befliegung - aus dem Verzeichnis holen.
  name=$(curl -sS "$NRW/hm/dgm1_tiff/dgm1_tiff/" | grep -o "dgm1_32_${t}_1_nw_[0-9]*\.tif" | sort -u | tail -1)
  [ -f "data/raw/dgm1/$name" ] || curl -sS -o "data/raw/dgm1/$name" "$NRW/hm/dgm1_tiff/dgm1_tiff/$name"
  [ -f "data/raw/lod2/LoD2_32_${t}_1_NW.gml" ] || curl -sS -o "data/raw/lod2/LoD2_32_${t}_1_NW.gml" "$NRW/3dg/lod2_gml/lod2_gml/LoD2_32_${t}_1_NW.gml"
done

# OSM: 4 x 4 Ausschnitte über 7.197979..7.230418 Ost, 51.472416..51.492670 Nord (die Region mit 100 m Rand).
lon0=7.197979; lon1=7.230418; lat0=51.472416; lat1=51.492670
for i in 0 1 2 3; do
  for j in 0 1 2 3; do
    f="data/raw/osm/map_${i}_${j}.osm"
    [ -f "$f" ] && continue
    box=$(awk -v a=$lon0 -v b=$lon1 -v c=$lat0 -v d=$lat1 -v i=$i -v j=$j 'BEGIN { printf "%.6f,%.6f,%.6f,%.6f", a+(b-a)*i/4, c+(d-c)*j/4, a+(b-a)*(i+1)/4, c+(d-c)*(j+1)/4 }')
    curl -sS -A "ruhrpott-raser/0.1" -o "$f" "https://api.openstreetmap.org/api/0.6/map?bbox=$box"
    sleep 2
  done
done
echo "Fertig: $(ls data/raw/dgm1 | wc -l) DGM1, $(ls data/raw/lod2 | wc -l) LoD2, $(ls data/raw/osm | wc -l) OSM"
