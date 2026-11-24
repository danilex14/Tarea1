-- P3 · Dos fuentes, un objeto: anti-join en los dos sentidos a 50 m.
-- Se comparan paraderos de BUS de GTFS (modo con 'bus') con highway=bus_stop de OSM: un
-- andén de metro no es un bus_stop y no corresponde exigirle pareja en OSM.
-- Además se informa la sensibilidad al umbral (25 / 50 / 100 m).
WITH g AS (SELECT stop_id, geom FROM paraderos_gtfs WHERE modo LIKE '%bus%'),
     o AS (SELECT id, geom FROM paraderos_osm)
SELECT umbral_m,
       (SELECT count(*) FROM g) AS gtfs_bus,
       (SELECT count(*) FROM g WHERE NOT EXISTS (SELECT 1 FROM o WHERE ST_DWithin(o.geom, g.geom, umbral_m))) AS gtfs_sin_osm,
       (SELECT count(*) FROM o) AS osm_bus_stop,
       (SELECT count(*) FROM o WHERE NOT EXISTS (SELECT 1 FROM g WHERE ST_DWithin(g.geom, o.geom, umbral_m))) AS osm_sin_gtfs
FROM (VALUES (25), (50), (100)) AS u(umbral_m)
ORDER BY umbral_m;

-- Por comuna, a 50 m: ¿dónde está incompleto OSM?
SELECT c.comuna,
       count(*) AS gtfs_bus,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_osm o WHERE ST_DWithin(o.geom, g.geom, 50))) AS sin_osm,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_osm o WHERE ST_DWithin(o.geom, g.geom, 50))) / count(*), 1) AS pct_sin_osm
FROM comunas_zona c
JOIN paraderos_gtfs g ON ST_Contains(c.geom, g.geom) AND g.modo LIKE '%bus%'
GROUP BY c.comuna
HAVING count(*) >= 50
ORDER BY pct_sin_osm DESC;

-- Plan de un sentido (GTFS sin OSM a 50 m)
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*)
FROM paraderos_gtfs g
WHERE g.modo LIKE '%bus%'
  AND NOT EXISTS (SELECT 1 FROM paraderos_osm o WHERE ST_DWithin(o.geom, g.geom, 50));

-- Y el mismo sin índice espacial (se desactiva solo para esta sesión) para comparar
SET enable_indexscan = off; SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, COSTS OFF)
SELECT count(*)
FROM paraderos_gtfs g
WHERE g.modo LIKE '%bus%'
  AND NOT EXISTS (SELECT 1 FROM paraderos_osm o WHERE ST_DWithin(o.geom, g.geom, 50));
RESET enable_indexscan; RESET enable_bitmapscan;
