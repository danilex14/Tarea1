-- P2 · Cobertura: % de edificios OSM de cada comuna a MÁS de 500 m de cualquier paradero.
-- Patrón: anti-join (NOT EXISTS + ST_DWithin), Lab 05 3.1. Edificio = su punto interior.
-- Se calcula dos veces: contra paraderos_gtfs (lo que el operador declara) y contra
-- paraderos_osm (lo que alguien dibujó).
-- Efecto borde: un edificio a <500 m del borde de la caja puede tener su paradero más
-- cercano FUERA de la caja (no cargado). Por eso se excluyen esos edificios
-- (ST_Buffer(zona, -500)); el conteo de excluidos se informa aparte.
WITH interior AS (SELECT ST_Buffer(geom, -500) AS geom FROM zona),
e AS (
    SELECT c.comuna, e.id, e.punto
    FROM comunas_zona c
    JOIN edificios e ON ST_Contains(c.geom, e.punto)
    JOIN interior i  ON ST_Contains(i.geom, e.punto)
)
SELECT comuna,
       count(*) AS edificios,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (
                 SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(p.geom, e.punto, 500))) / count(*), 1) AS pct_lejos_gtfs,
       round(100.0 * count(*) FILTER (WHERE NOT EXISTS (
                 SELECT 1 FROM paraderos_osm  p WHERE ST_DWithin(p.geom, e.punto, 500))) / count(*), 1) AS pct_lejos_osm
FROM e
GROUP BY comuna
HAVING count(*) >= 100
ORDER BY pct_lejos_gtfs DESC, pct_lejos_osm DESC;

-- Total de la zona y edificios excluidos por el borde
WITH interior AS (SELECT ST_Buffer(geom, -500) AS geom FROM zona)
SELECT count(*) AS edificios_total,
       count(*) FILTER (WHERE NOT ST_Contains(i.geom, e.punto)) AS excluidos_por_borde,
       round(100.0 * count(*) FILTER (WHERE ST_Contains(i.geom, e.punto) AND NOT EXISTS (
             SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(p.geom, e.punto, 500)))
             / count(*) FILTER (WHERE ST_Contains(i.geom, e.punto)), 2) AS pct_lejos_gtfs_zona,
       round(100.0 * count(*) FILTER (WHERE ST_Contains(i.geom, e.punto) AND NOT EXISTS (
             SELECT 1 FROM paraderos_osm p WHERE ST_DWithin(p.geom, e.punto, 500)))
             / count(*) FILTER (WHERE ST_Contains(i.geom, e.punto)), 2) AS pct_lejos_osm_zona
FROM edificios e, interior i;

-- Plan del anti-join (GTFS). El índice debe aparecer del lado de ADENTRO (paraderos_gtfs).
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*)
FROM edificios e
WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(p.geom, e.punto, 500));
