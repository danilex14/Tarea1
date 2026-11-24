-- 11 · OSM: capas derivadas con esquema propio (la T del ETL). Patrón del Lab 05, 2.1.
DROP TABLE IF EXISTS calles, edificios, paraderos_osm, amenidades CASCADE;

-- Calles: toda línea con highway. Se guarda el largo para no recalcularlo.
CREATE TABLE calles AS
SELECT id, osm_id, name, highway,
       other_tags -> 'maxspeed' AS maxspeed,
       other_tags -> 'oneway'   AS oneway,
       ST_Length(geom) AS largo_m,
       geom::geometry(LineString, 5361) AS geom
FROM osm_lineas
WHERE highway IS NOT NULL;

-- Edificios: el polígono (para áreas) y su PUNTO INTERIOR (para asignar a una comuna o a
-- un hexágono sin contar dos veces el que cruza un límite). ST_PointOnSurface, no
-- ST_Centroid: el centroide de un edificio en "L" puede caer fuera de él.
CREATE TABLE edificios AS
SELECT id, coalesce(osm_id, osm_way_id) AS osm_id, name, building,
       other_tags -> 'building:levels' AS pisos,
       ST_Area(geom) AS area_m2,
       geom::geometry(MultiPolygon, 5361) AS geom,
       ST_PointOnSurface(geom)::geometry(Point, 5361) AS punto
FROM osm_poligonos
WHERE building IS NOT NULL AND NOT ST_IsEmpty(geom);

-- Paraderos de OSM: los que alguien dibujó como highway=bus_stop.
CREATE TABLE paraderos_osm AS
SELECT id, osm_id, name,
       other_tags -> 'ref' AS ref,
       geom::geometry(Point, 5361) AS geom
FROM osm_puntos
WHERE highway = 'bus_stop';

-- Amenidades: en la capa de puntos `amenity` vive en other_tags; en la de polígonos es
-- columna (osmconf.ini por defecto). Los polígonos se reducen a su punto interior.
CREATE TABLE amenidades AS
SELECT id, osm_id, name, other_tags -> 'amenity' AS amenity, 'punto'::text AS origen,
       geom::geometry(Point, 5361) AS geom
FROM osm_puntos
WHERE other_tags ? 'amenity'
UNION ALL
SELECT id, coalesce(osm_id, osm_way_id), name, amenity, 'poligono',
       ST_PointOnSurface(geom)::geometry(Point, 5361)
FROM osm_poligonos
WHERE amenity IS NOT NULL AND NOT ST_IsEmpty(geom);

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'osm_derivadas', 'edificios descartados por quedar vacios', count(*)
FROM osm_poligonos WHERE building IS NOT NULL AND ST_IsEmpty(geom);
