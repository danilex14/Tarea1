-- 20 · GTFS crudo: los CSV tal cual, con COPY (del lado del servidor: los archivos están
-- montados en /datos/gtfs dentro del contenedor de la base). Nada de INSERT por fila.
-- Todas las columnas como text: el tipado se hace al derivar, donde se puede controlar.
DROP TABLE IF EXISTS gtfs_stops, gtfs_shapes, gtfs_trips, gtfs_routes, gtfs_stop_times, gtfs_feed_info CASCADE;

CREATE TABLE gtfs_feed_info (feed_publisher_name text, feed_publisher_url text, feed_lang text,
                             feed_start_date text, feed_end_date text, feed_version text);
CREATE TABLE gtfs_routes (route_id text, agency_id text, route_short_name text, route_long_name text,
                          route_desc text, route_type text, route_url text, route_color text, route_text_color text);
CREATE TABLE gtfs_trips  (route_id text, service_id text, trip_id text, trip_headsign text, direction_id text,
                          shape_id text, trip_short_name text, wheelchair_accessible text, bikes_allowed text);
CREATE TABLE gtfs_stops  (stop_id text, stop_code text, stop_name text, stop_lat text, stop_lon text,
                          stop_url text, wheelchair_boarding text, location_type text, parent_station text, level_id text);
-- shapes y stop_times: las grandes. UNLOGGED porque son intermedias y se reconstruyen
-- desde el ZIP; ahorra el WAL de cientos de miles / un millón de filas.
CREATE UNLOGGED TABLE gtfs_shapes (shape_id text, shape_pt_lat float8, shape_pt_lon float8, shape_pt_sequence int);
CREATE UNLOGGED TABLE gtfs_stop_times (trip_id text, arrival_time text, departure_time text, stop_id text,
                          stop_sequence int, pickup_type text, drop_off_type text, timepoint text);

-- El orden de columnas de los COPY se toma de la cabecera de cada archivo (ver cargar.sh,
-- que valida que coincida). Si DTPM cambia el esquema, el script lo dice y se detiene.
COPY gtfs_feed_info  FROM '/datos/gtfs/feed_info.txt'  WITH (FORMAT csv, HEADER true);
COPY gtfs_routes     FROM '/datos/gtfs/routes.txt'     WITH (FORMAT csv, HEADER true);
COPY gtfs_trips      FROM '/datos/gtfs/trips.txt'      WITH (FORMAT csv, HEADER true);
COPY gtfs_stops      FROM '/datos/gtfs/stops.txt'      WITH (FORMAT csv, HEADER true);
COPY gtfs_shapes     FROM '/datos/gtfs/shapes.txt'     WITH (FORMAT csv, HEADER true);
COPY gtfs_stop_times FROM '/datos/gtfs/stop_times.txt' WITH (FORMAT csv, HEADER true);

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'gtfs_crudo', 'filas ' || t, n FROM (
    SELECT 'routes.txt' t, count(*) n FROM gtfs_routes UNION ALL
    SELECT 'trips.txt', count(*) FROM gtfs_trips UNION ALL
    SELECT 'stops.txt', count(*) FROM gtfs_stops UNION ALL
    SELECT 'shapes.txt', count(*) FROM gtfs_shapes UNION ALL
    SELECT 'stop_times.txt', count(*) FROM gtfs_stop_times) x;

CREATE INDEX ON gtfs_stop_times (trip_id);
CREATE INDEX ON gtfs_trips (trip_id);
ANALYZE gtfs_routes, gtfs_trips, gtfs_stops, gtfs_shapes, gtfs_stop_times;
