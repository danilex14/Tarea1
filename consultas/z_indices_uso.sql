-- Índices: cuántas veces los usó el planificador durante las consultas (consultas.sh
-- reinicia las estadísticas antes de correr P1–P7). Un índice con 0 lecturas es un
-- hallazgo: ocupa disco y frena las cargas sin acelerar ninguna pregunta.
SELECT relname AS tabla, indexrelname AS indice, idx_scan AS lecturas, idx_tup_read AS tuplas_leidas,
       pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND relname <> 'spatial_ref_sys'   -- la imagen postgis/postgis trae además el esquema tiger
ORDER BY idx_scan, pg_relation_size(indexrelid) DESC;
