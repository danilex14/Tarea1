-- 99 · Resumen: tablas, filas, SRID e índices (lo que va en el README).
\pset footer off
\echo '== Fuentes'
SELECT feed_version AS gtfs_feed_version, feed_start_date, feed_end_date FROM gtfs_feed_info;
\echo '== Tablas'
SELECT t.tabla, t.filas, t.srid, pg_size_pretty(pg_total_relation_size(t.tabla::regclass)) AS tamano
FROM (VALUES
    ('osm_puntos',     (SELECT count(*) FROM osm_puntos),     (SELECT max(ST_SRID(geom)) FROM osm_puntos)),
    ('osm_lineas',     (SELECT count(*) FROM osm_lineas),     (SELECT max(ST_SRID(geom)) FROM osm_lineas)),
    ('osm_poligonos',  (SELECT count(*) FROM osm_poligonos),  (SELECT max(ST_SRID(geom)) FROM osm_poligonos)),
    ('calles',         (SELECT count(*) FROM calles),         (SELECT max(ST_SRID(geom)) FROM calles)),
    ('edificios',      (SELECT count(*) FROM edificios),      (SELECT max(ST_SRID(geom)) FROM edificios)),
    ('paraderos_osm',  (SELECT count(*) FROM paraderos_osm),  (SELECT max(ST_SRID(geom)) FROM paraderos_osm)),
    ('amenidades',     (SELECT count(*) FROM amenidades),     (SELECT max(ST_SRID(geom)) FROM amenidades)),
    ('paraderos_gtfs', (SELECT count(*) FROM paraderos_gtfs), (SELECT max(ST_SRID(geom)) FROM paraderos_gtfs)),
    ('recorridos',     (SELECT count(*) FROM recorridos),     (SELECT max(ST_SRID(geom)) FROM recorridos)),
    ('rutas',          (SELECT count(*) FROM rutas),          (SELECT max(ST_SRID(geom)) FROM rutas)),
    ('paradero_ruta',  (SELECT count(*) FROM paradero_ruta),  NULL),
    ('comunas_cl',     (SELECT count(*) FROM comunas_cl),     (SELECT max(ST_SRID(geom)) FROM comunas_cl)),
    ('comunas_zona',   (SELECT count(*) FROM comunas_zona),   (SELECT max(ST_SRID(geom)) FROM comunas_zona)),
    ('comunas_sub',    (SELECT count(*) FROM comunas_sub),    (SELECT max(ST_SRID(geom)) FROM comunas_sub)),
    ('gtfs_stop_times',(SELECT count(*) FROM gtfs_stop_times),NULL),
    ('gtfs_shapes',    (SELECT count(*) FROM gtfs_shapes),    NULL)
) AS t(tabla, filas, srid);
\echo '== Indices'
SELECT tablename AS tabla, indexname AS indice,
       CASE WHEN indexdef ILIKE '%USING gist%' THEN 'GiST' ELSE 'B-tree' END AS tipo,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS tamano
FROM pg_indexes
WHERE schemaname = 'public' AND tablename NOT IN ('spatial_ref_sys')
ORDER BY 1, 2;
\echo '== Bitacora del ETL'
SELECT paso, detalle, n FROM registro_etl ORDER BY cuando, paso, detalle;
