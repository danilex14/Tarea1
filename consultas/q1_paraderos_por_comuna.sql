-- P1 · Paraderos GTFS por comuna y densidad (paraderos / km² de comuna dentro de la caja).
-- Patrón: punto-en-polígono (ST_Contains) con GROUP BY. LEFT JOIN para que aparezcan las
-- comunas con 0 paraderos.
-- Densidad: se divide por el área de la comuna DENTRO de la caja (area_caja_km2), porque
-- solo se cargaron los paraderos de la caja. pct_en_caja dice cuánto de la comuna se ve.
SELECT c.comuna,
       count(p.stop_id)                                          AS paraderos,
       count(p.stop_id) FILTER (WHERE p.modo LIKE '%bus%')       AS de_bus,
       round(c.area_caja_km2::numeric, 1)                        AS km2_en_caja,
       round((count(p.stop_id) / c.area_caja_km2)::numeric, 1)   AS por_km2,
       c.pct_en_caja
FROM comunas_zona c
LEFT JOIN paraderos_gtfs p ON ST_Contains(c.geom, p.geom)
GROUP BY c.comuna, c.area_caja_km2, c.pct_en_caja
ORDER BY (c.pct_en_caja >= 50) DESC, por_km2 DESC;   -- primero las comunas que se ven al menos a la mitad

-- Plan
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT c.comuna, count(p.stop_id)
FROM comunas_zona c
LEFT JOIN paraderos_gtfs p ON ST_Contains(c.geom, p.geom)
GROUP BY c.comuna;

-- Contraste: el mismo join contra comunas_sub (partes de ≤128 vértices)
EXPLAIN (ANALYZE, COSTS OFF)
SELECT s.comuna, count(p.stop_id)
FROM comunas_sub s
JOIN paraderos_gtfs p ON ST_Contains(s.geom, p.geom)
GROUP BY s.comuna;
