-- Ruhrpott-Raser: Schema des Zwischenlayers in PostGIS (Konzept, Abschnitt 2; Roadmap M1). Raser.PostgresTileStore legt es an (EnsureSchema).
--
-- Die Merkmale liegen global, mit absoluten Koordinaten: ETRS89 / UTM 32N (EPSG:25832), Höhen über NHN (DHHN2016). Eine Kachel ist eine räumliche
-- Abfrage über ihr Rechteck (+ 1 m Rand); die Zeile in `tile` hält nur, was zur Kachel selbst gehört (Höhenraster, Viertel, Quellen).
-- Stabile IDs (Raser.Ids.Stable) und Quellen (`source`) sind die Schlüssel, an denen Spieler-Deltas hängen.

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS tile (
    x           integer NOT NULL,
    y           integer NOT NULL,
    format      integer NOT NULL DEFAULT 1,
    quarter     text    NOT NULL DEFAULT 'vorort',      -- Viertel-Typ (Konzept, Abschnitt 4)
    mood        text    NOT NULL DEFAULT '',
    sources     text    NOT NULL DEFAULT '',            -- woher die Daten kommen (Zeilen)
    heights     bytea,                                  -- Höhenraster RRH1 (258 x 258, 1 m, Pixelmitten -0,5 .. 256,5)
    imported_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (x, y)
);

CREATE TABLE IF NOT EXISTS building (
    id          bigint  PRIMARY KEY,
    source      text    NOT NULL UNIQUE,                -- 'lod2:<gml:id>' oder 'osm:way/<id>'
    footprint   geometry(Polygon, 25832) NOT NULL,
    ground      double precision NOT NULL,
    eaves       double precision NOT NULL,
    ridge       double precision NOT NULL,
    roof_type   smallint NOT NULL DEFAULT 0,            -- Raser.RoofType
    roofs       geometry(MultiPolygonZ, 25832),         -- Dachflächen aus LoD2
    function    text,                                   -- 'amenity=fuel', 'alkis=31001_1000', ...
    name        text,
    levels      smallint NOT NULL DEFAULT 0,
    cellars     smallint NOT NULL DEFAULT 0,
    wall        smallint NOT NULL,                      -- Raser.Material
    wall_color  smallint NOT NULL,
    roof        smallint NOT NULL,
    roof_color  smallint NOT NULL
);
ALTER TABLE building ADD COLUMN IF NOT EXISTS cellars smallint NOT NULL DEFAULT 0;   -- für Datenbanken von vor den Kellern
CREATE INDEX IF NOT EXISTS building_footprint ON building USING gist (footprint);

CREATE TABLE IF NOT EXISTS road (
    id          bigint  PRIMARY KEY,
    source      text    NOT NULL UNIQUE,                -- 'osm:way/<id>'
    kind        text    NOT NULL,                       -- 'highway=residential', 'railway=tram', ...
    line        geometry(LineString, 25832) NOT NULL,
    width       double precision NOT NULL,
    surface     smallint NOT NULL,
    color       smallint NOT NULL,
    lanes       smallint NOT NULL DEFAULT 0,
    layer       smallint NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS road_line ON road USING gist (line);

CREATE TABLE IF NOT EXISTS area (
    id          bigint  PRIMARY KEY,
    source      text    NOT NULL UNIQUE,                -- 'osm:way/<id>', 'osm:relation/<id>#<n>'
    kind        text    NOT NULL,
    ring        geometry(Polygon, 25832) NOT NULL,
    surface     smallint NOT NULL,
    color       smallint NOT NULL,
    priority    smallint NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS area_ring ON area USING gist (ring);

CREATE TABLE IF NOT EXISTS poi (
    id          bigint  PRIMARY KEY,
    source      text    NOT NULL UNIQUE,                -- 'osm:node/<id>'
    kind        text    NOT NULL,
    name        text,
    position    geometry(Point, 25832) NOT NULL
);
CREATE INDEX IF NOT EXISTS poi_position ON poi USING gist (position);

-- Die Chunks (RRC1 mit Deflate) und ihre Manifeste bleiben vorerst Dateien (world/chunks); sie gehören in den Key-Value-Store (Konzept: RocksDB),
-- Schlüssel (kachel, chunk), die Deltas der Spieler ebenso.
