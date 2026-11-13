-- Ruhrpott-Raser: Schema des Zwischenlayers in PostGIS (Konzept, Abschnitt 2; Roadmap M1).
--
-- Stand: Entwurf. Solange fire keinen PostgreSQL-Treiber hat, liegt der Zwischenlayer in Dateien (Raser.FileTileStore, docs/PIPELINE.md)
-- mit genau dieser Aufteilung; ein PostGIS-Store setzt später Raser.ITileStore um.
-- Koordinaten: ETRS89 / UTM 32N (EPSG:25832), Höhen über NHN (DHHN2016). Gespeichert wird absolut; die Kachel-JSONs sind kachel-lokal.

CREATE EXTENSION IF NOT EXISTS postgis;

-- Eine Kachel: 256 x 256 m, Schlüssel floor(Ost / 256), floor(Nord / 256).
CREATE TABLE tile (
    x           integer NOT NULL,
    y           integer NOT NULL,
    format      integer NOT NULL DEFAULT 1,
    quarter     text    NOT NULL DEFAULT 'vorort',      -- Viertel-Typ (Konzept, Abschnitt 4)
    mood        text    NOT NULL DEFAULT '',
    sources     text[]  NOT NULL DEFAULT '{}',          -- woher die Daten kommen (Dateien, Stände)
    heights     bytea,                                  -- Höhenraster RRH1 (258 x 258, 1 m, Pixelmitten -0,5 .. 256,5)
    data_hash   bigint,                                 -- FNV-1a über Merkmale + Raster (wie Tile.DataHash)
    imported_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (x, y)
);

-- Gebäude: stabile ID aus der Quelle (Raser.Ids.Stable), Spieler-Deltas hängen daran.
CREATE TABLE building (
    id          bigint PRIMARY KEY,
    source      text   NOT NULL UNIQUE,                 -- 'lod2:<gml:id>' oder 'osm:way/<id>'
    footprint   geometry(PolygonZ, 25832) NOT NULL,
    ground      real   NOT NULL,
    eaves       real   NOT NULL,
    ridge       real   NOT NULL,
    roof_type   smallint NOT NULL DEFAULT 0,            -- Raser.RoofType
    roofs       geometry(MultiPolygonZ, 25832),         -- Dachflächen aus LoD2
    function    text,                                   -- 'amenity=fuel', 'alkis=31001_1000', ...
    name        text,
    levels      smallint NOT NULL DEFAULT 0,
    wall        smallint NOT NULL,                      -- Raser.Material
    wall_color  smallint NOT NULL,
    roof        smallint NOT NULL,
    roof_color  smallint NOT NULL
);
CREATE INDEX building_footprint ON building USING gist (footprint);

CREATE TABLE road (
    id          bigint PRIMARY KEY,
    source      text   NOT NULL UNIQUE,                 -- 'osm:way/<id>'
    kind        text   NOT NULL,                        -- 'highway=residential', 'railway=tram', ...
    line        geometry(LineString, 25832) NOT NULL,
    width       real   NOT NULL,
    surface     smallint NOT NULL,
    color       smallint NOT NULL,
    lanes       smallint NOT NULL DEFAULT 0,
    layer       smallint NOT NULL DEFAULT 0
);
CREATE INDEX road_line ON road USING gist (line);

CREATE TABLE area (
    id          bigint PRIMARY KEY,
    source      text   NOT NULL UNIQUE,                 -- 'osm:way/<id>', 'osm:relation/<id>#<n>'
    kind        text   NOT NULL,
    ring        geometry(Polygon, 25832) NOT NULL,
    surface     smallint NOT NULL,
    color       smallint NOT NULL,
    priority    smallint NOT NULL DEFAULT 0
);
CREATE INDEX area_ring ON area USING gist (ring);

CREATE TABLE poi (
    id          bigint PRIMARY KEY,
    source      text   NOT NULL UNIQUE,                 -- 'osm:node/<id>'
    kind        text   NOT NULL,
    name        text,
    position    geometry(Point, 25832) NOT NULL
);
CREATE INDEX poi_position ON poi USING gist (position);

-- Womit die Chunks einer Kachel erzeugt wurden (Konzept, Abschnitt 9): passt eines nicht mehr, ist die Kachel veraltet.
CREATE TABLE chunk_manifest (
    tile_x            integer NOT NULL,
    tile_y            integer NOT NULL,
    generator_version integer NOT NULL,
    overrides_hash    bigint  NOT NULL,
    seed              bigint  NOT NULL,
    data_hash         bigint  NOT NULL,
    chunks            integer NOT NULL,
    filled            bigint  NOT NULL,
    generated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tile_x, tile_y),
    FOREIGN KEY (tile_x, tile_y) REFERENCES tile (x, y) ON DELETE CASCADE
);

-- Die Chunks selbst (RRC1 mit Deflate) gehören in den Key-Value-Store (Konzept: RocksDB), Schlüssel (kachel, chunk);
-- die Deltas der Spieler ebenso, an stabile IDs gehängt.
