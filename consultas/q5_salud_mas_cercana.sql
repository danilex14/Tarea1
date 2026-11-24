-- P5 · Vecino más cercano: para cada paradero del recorrido 506 (Maipú – Peñalolén), la
-- farmacia o centro de salud (amenity pharmacy/hospital/clinic/doctors) más cercano.
-- Patrón: CROSS JOIN LATERAL + <-> + LIMIT 1 (KNN con el índice GiST).
-- Elección del 506: cruza la zona de poniente a oriente (Av. 5 de Abril en Estación Central,
-- Av. Matta en Santiago, Av. Grecia en Ñuñoa y Peñalolén): centro denso y bordes residenciales.
-- Los paraderos se ordenan por stop_sequence de un viaje representativo de cada sentido.
\set ruta '506'
WITH viaje AS (                               -- un viaje por sentido
    SELECT DISTINCT ON (t.direction_id) t.trip_id, t.direction_id
    FROM gtfs_trips t JOIN gtfs_routes r USING (route_id)
    WHERE r.route_short_name = :'ruta'
    ORDER BY t.direction_id, t.trip_id
), p AS (
    SELECT v.direction_id, st.stop_sequence, pg.stop_id, pg.stop_name, pg.geom
    FROM viaje v
    JOIN gtfs_stop_times st USING (trip_id)
    JOIN paraderos_gtfs pg USING (stop_id)            -- solo los de la caja
)
SELECT p.direction_id AS sentido, p.stop_sequence AS orden, p.stop_id, p.stop_name AS paradero,
       s.amenity, coalesce(s.name, '(sin nombre en OSM)') AS establecimiento, round(s.dist) AS metros
FROM p
CROSS JOIN LATERAL (
    SELECT a.name, a.amenity, a.geom <-> p.geom AS dist
    FROM amenidades a
    WHERE a.amenity IN ('pharmacy', 'hospital', 'clinic', 'doctors')
    ORDER BY a.geom <-> p.geom
    LIMIT 1
) s
ORDER BY sentido, orden;

-- Resumen por sentido
WITH viaje AS (
    SELECT DISTINCT ON (t.direction_id) t.trip_id, t.direction_id
    FROM gtfs_trips t JOIN gtfs_routes r USING (route_id)
    WHERE r.route_short_name = :'ruta' ORDER BY t.direction_id, t.trip_id
), d AS (
    SELECT v.direction_id, (SELECT a.geom <-> pg.geom FROM amenidades a
                            WHERE a.amenity IN ('pharmacy','hospital','clinic','doctors')
                            ORDER BY a.geom <-> pg.geom LIMIT 1) AS dist
    FROM viaje v JOIN gtfs_stop_times st USING (trip_id) JOIN paraderos_gtfs pg USING (stop_id)
)
SELECT direction_id AS sentido, count(*) AS paraderos, round(avg(dist)) AS media_m,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY dist)) AS mediana_m, round(max(dist)) AS max_m,
       count(*) FILTER (WHERE dist > 500) AS a_mas_de_500m
FROM d GROUP BY direction_id ORDER BY 1;

-- Plan: el KNN debe usar un Index Scan con "Order By: (geom <-> ...)"
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
WITH viaje AS (
    SELECT DISTINCT ON (t.direction_id) t.trip_id, t.direction_id
    FROM gtfs_trips t JOIN gtfs_routes r USING (route_id)
    WHERE r.route_short_name = :'ruta' ORDER BY t.direction_id, t.trip_id
)
SELECT pg.stop_id, s.dist
FROM viaje v JOIN gtfs_stop_times st USING (trip_id) JOIN paraderos_gtfs pg USING (stop_id)
CROSS JOIN LATERAL (SELECT a.geom <-> pg.geom AS dist FROM amenidades a
                    WHERE a.amenity IN ('pharmacy','hospital','clinic','doctors')
                    ORDER BY a.geom <-> pg.geom LIMIT 1) s;
