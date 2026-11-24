-- 21 · GTFS → geometría. Recorte a la caja EN LA BASE (no a mano).
DROP TABLE IF EXISTS paradero_ruta, paraderos_gtfs, recorridos, rutas CASCADE;

-- (a) Qué rutas sirven a cada paradero: stop_times → trips → routes. Se usa para el modo
--     (bus / metro / tren) y para "por cuántos recorridos distintos pasa".
--     Ojo: en el GTFS de DTPM los trips son plantillas con frequencies.txt, así que contar
--     filas de stop_times NO es contar buses reales; contamos rutas distintas.
CREATE TABLE paradero_ruta AS
SELECT DISTINCT st.stop_id, t.route_id
FROM gtfs_stop_times st
JOIN gtfs_trips t USING (trip_id);
CREATE INDEX ON paradero_ruta (stop_id);
CREATE INDEX ON paradero_ruta (route_id);

-- (b) Paraderos: ST_SetSRID(ST_MakePoint(lon, lat), 4326) → 5361. Solo puntos de abordaje
--     (location_type vacío o 0); estaciones (1), accesos (2), nodos (3) y zonas de abordaje
--     (4) no son "paraderos". Solo los de la caja.
--     route_type: 3 bus, 1 metro; los trenes EFE (MTN, MTR) vienen como 0 en este feed.
CREATE TABLE paraderos_gtfs AS
WITH s AS (
    SELECT stop_id, nullif(stop_code, '') AS stop_code, stop_name, nullif(parent_station, '') AS parent_station,
           ST_SetSRID(ST_MakePoint(stop_lon::float8, stop_lat::float8), 4326) AS g4326
    FROM gtfs_stops
    WHERE coalesce(nullif(location_type, ''), '0') = '0'
), servicio AS (
    SELECT pr.stop_id,
           count(DISTINCT pr.route_id) AS n_rutas,
           string_agg(DISTINCT CASE r.route_type WHEN '3' THEN 'bus' WHEN '1' THEN 'metro'
                                                 WHEN '2' THEN 'tren' WHEN '0' THEN 'tren' ELSE 'otro' END, '+') AS modo
    FROM paradero_ruta pr JOIN gtfs_routes r USING (route_id)
    GROUP BY pr.stop_id
)
SELECT s.stop_id, s.stop_code, s.stop_name, s.parent_station,
       coalesce(sv.modo, 'sin_servicio') AS modo,
       coalesce(sv.n_rutas, 0)          AS n_rutas,
       ST_Transform(s.g4326, 5361)::geometry(Point, 5361) AS geom
FROM s
LEFT JOIN servicio sv USING (stop_id)
JOIN zona z ON ST_Intersects(s.g4326, z.geom4326);

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'gtfs_derivadas', 'stops.txt puntos de abordaje (todo Santiago)', count(*)
FROM gtfs_stops WHERE coalesce(nullif(location_type, ''), '0') = '0'
UNION ALL SELECT 'gtfs_derivadas', 'paraderos_gtfs dentro de la caja', count(*) FROM paraderos_gtfs
UNION ALL SELECT 'gtfs_derivadas', 'paraderos_gtfs modo ' || modo, count(*) FROM paraderos_gtfs GROUP BY modo;

-- (c) Recorridos: UNA LineString por shape_id, con los vértices en el orden de
--     shape_pt_sequence (ST_MakeLine con ORDER BY dentro del agregado). Se construye en
--     4326 y se transforma una sola vez.
--     Decisión ida/vuelta/variantes: se conserva CADA shape como fila (un shape es un trazado
--     físico distinto: ida y vuelta van por calles distintas en Santiago). Para todo lo que
--     cuenta "recorridos distintos" se usa route_id (count DISTINCT), y la tabla `rutas`
--     junta los shapes de una ruta en una MultiLineString.
--     En este GTFS cada shape pertenece a una sola ruta (verificado en cargar.sh).
CREATE TABLE recorridos AS
WITH lineas AS (
    SELECT shape_id,
           count(*) AS n_puntos,
           count(DISTINCT shape_pt_sequence) AS n_secuencias,
           ST_MakeLine(ST_SetSRID(ST_MakePoint(shape_pt_lon, shape_pt_lat), 4326)
                       ORDER BY shape_pt_sequence) AS g4326
    FROM gtfs_shapes
    GROUP BY shape_id
), shape_ruta AS (
    SELECT DISTINCT ON (shape_id) shape_id, route_id, nullif(direction_id, '')::int AS direction_id
    FROM gtfs_trips
    WHERE nullif(shape_id, '') IS NOT NULL
    ORDER BY shape_id, route_id
)
SELECT l.shape_id, sr.route_id, r.route_short_name, r.route_long_name,
       r.route_type::int AS route_type, sr.direction_id,
       l.n_puntos, l.n_secuencias,
       ST_Transform(l.g4326, 5361)::geometry(LineString, 5361) AS geom
FROM lineas l
JOIN shape_ruta sr USING (shape_id)
JOIN gtfs_routes r USING (route_id)
JOIN zona z ON ST_Intersects(l.g4326, z.geom4326);
ALTER TABLE recorridos ADD COLUMN largo_m float8;
UPDATE recorridos SET largo_m = ST_Length(geom);

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'gtfs_derivadas', 'shapes en shapes.txt', count(DISTINCT shape_id) FROM gtfs_shapes
UNION ALL SELECT 'gtfs_derivadas', 'recorridos (shapes) que tocan la caja', count(*) FROM recorridos
UNION ALL SELECT 'gtfs_derivadas', 'rutas distintas que tocan la caja', count(DISTINCT route_id) FROM recorridos
UNION ALL SELECT 'gtfs_derivadas', 'shapes con shape_pt_sequence repetido', count(*) FROM recorridos WHERE n_puntos <> n_secuencias
UNION ALL SELECT 'gtfs_derivadas', 'shapes no simples (se cruzan a si mismos: normal en circuitos)', count(*) FROM recorridos WHERE NOT ST_IsSimple(geom)
UNION ALL SELECT 'gtfs_derivadas', 'shapes de menos de 2 puntos', count(*) FROM recorridos WHERE n_puntos < 2;

-- Una fila por ruta (todas sus variantes juntas), para mapas y conteos por ruta.
CREATE TABLE rutas AS
SELECT route_id, route_short_name, route_long_name, route_type,
       count(*) AS n_shapes,
       ST_Multi(ST_Collect(geom))::geometry(MultiLineString, 5361) AS geom
FROM recorridos
GROUP BY route_id, route_short_name, route_long_name, route_type;
