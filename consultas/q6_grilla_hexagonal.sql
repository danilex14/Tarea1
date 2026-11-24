-- P6 · Grilla hexagonal de 500 m: edificios y recorridos distintos por celda.
-- ST_HexagonGrid(500, caja): el 500 es el LADO del hexágono (≈ 0,65 km² por celda), igual
-- que en el Lab 05 2.3. Se materializa (vista materializada) porque es el insumo del mapa
-- principal y de la exportación, y no cambia mientras no se recarguen los datos.
-- Edificio → celda por su punto interior (no se cuenta dos veces).
-- Recorridos distintos = count(DISTINCT route_id) de los shapes que cruzan la celda
-- (ida y vuelta de una misma ruta cuentan una vez).
DROP MATERIALIZED VIEW IF EXISTS mv_grilla;
CREATE MATERIALIZED VIEW mv_grilla AS
WITH h AS (
    SELECT g.i, g.j, g.geom
    FROM zona z, ST_HexagonGrid(500, z.geom) AS g
    WHERE ST_Intersects(g.geom, z.geom)
)
SELECT h.i, h.j,
       (SELECT count(*) FROM edificios e WHERE ST_Intersects(h.geom, e.punto))                AS edificios,
       (SELECT count(DISTINCT r.route_id) FROM recorridos r
         WHERE r.route_type = 3 AND ST_Intersects(h.geom, r.geom))                            AS recorridos_bus,
       (SELECT count(DISTINCT r.route_id) FROM recorridos r WHERE ST_Intersects(h.geom, r.geom)) AS recorridos,
       (SELECT count(*) FROM paraderos_gtfs p WHERE ST_Intersects(h.geom, p.geom))            AS paraderos_gtfs,
       ST_Within(h.geom, (SELECT geom FROM zona))                                              AS completa,
       h.geom::geometry(Polygon, 5361) AS geom
FROM h;
CREATE INDEX idx_mv_grilla_geom ON mv_grilla USING GIST (geom);
CREATE UNIQUE INDEX idx_mv_grilla_ij ON mv_grilla (i, j);
ANALYZE mv_grilla;

-- Resumen de la grilla
SELECT count(*) AS celdas, count(*) FILTER (WHERE completa) AS completas,
       sum(edificios) AS edificios, max(edificios) AS max_edificios,
       count(*) FILTER (WHERE recorridos = 0) AS celdas_sin_recorrido,
       count(*) FILTER (WHERE recorridos = 0 AND edificios > 0) AS con_edificios_sin_recorrido
FROM mv_grilla;

-- Las 10 celdas con MÁS edificios y MENOS recorridos.
-- Criterio: solo celdas completas (dentro de la caja) y con al menos 200 edificios
-- (para que "pocos recorridos" sea un problema de gente, no un cerro vacío); orden por
-- recorridos ascendente y, a igualdad, por edificios descendente.
SELECT m.i, m.j, m.edificios, m.recorridos, m.recorridos_bus, m.paraderos_gtfs,
       (SELECT string_agg(DISTINCT c.comuna, ', ') FROM comunas_zona c
         WHERE ST_Intersects(c.geom, ST_Centroid(m.geom))) AS comuna,
       round(ST_X(ST_Transform(ST_Centroid(m.geom), 4326))::numeric, 4) AS lon,
       round(ST_Y(ST_Transform(ST_Centroid(m.geom), 4326))::numeric, 4) AS lat
FROM mv_grilla m
WHERE m.completa AND m.edificios >= 200
ORDER BY m.recorridos ASC, m.edificios DESC
LIMIT 10;

-- Las 10 con más edificios (para contexto)
SELECT i, j, edificios, recorridos FROM mv_grilla ORDER BY edificios DESC LIMIT 10;
