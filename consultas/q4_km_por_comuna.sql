-- P4 · Kilómetros de recorrido por comuna: cada trazado recortado en el límite comunal
-- con ST_Intersection (líneas contra polígonos, Lab 05 3.3).
-- Se usa la parte de cada comuna DENTRO de la caja (geom_caja): fuera de la caja hay
-- recorridos que no se cargaron (solo se cargaron los shapes que tocan la caja).
-- km_shapes suma TODOS los shapes (ida + vuelta + variantes: kilómetros de servicio);
-- km_ida suma solo direction_id = 0 (aprox. un sentido por ruta).
\timing on
SELECT c.comuna,
       round((sum(ST_Length(ST_Intersection(r.geom, c.geom_caja))) / 1000)::numeric, 1) AS km_shapes,
       round((sum(ST_Length(ST_Intersection(r.geom, c.geom_caja))) FILTER (WHERE r.direction_id = 0) / 1000)::numeric, 1) AS km_ida,
       count(DISTINCT r.route_id) AS rutas,
       round((sum(ST_Length(ST_Intersection(r.geom, c.geom_caja))) / 1000 / c.area_caja_km2)::numeric, 1) AS km_por_km2
FROM comunas_zona c
JOIN recorridos r ON ST_Intersects(r.geom, c.geom_caja)
GROUP BY c.comuna, c.area_caja_km2
ORDER BY km_shapes DESC;

-- Lo mismo con comunas_sub (ST_Subdivide, 128 vértices). Debe dar los MISMOS km.
SELECT s.comuna,
       round((sum(ST_Length(ST_Intersection(r.geom, s.geom))) / 1000)::numeric, 1) AS km_shapes
FROM comunas_sub s
JOIN recorridos r ON ST_Intersects(r.geom, s.geom)
GROUP BY s.comuna
ORDER BY km_shapes DESC;
\timing off

-- Planes: sin y con ST_Subdivide (el Execution Time es la comparación)
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT c.comuna, sum(ST_Length(ST_Intersection(r.geom, c.geom_caja)))
FROM comunas_zona c JOIN recorridos r ON ST_Intersects(r.geom, c.geom_caja)
GROUP BY c.comuna;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT s.comuna, sum(ST_Length(ST_Intersection(r.geom, s.geom)))
FROM comunas_sub s JOIN recorridos r ON ST_Intersects(r.geom, s.geom)
GROUP BY s.comuna;

-- Tercera variante: subdividir TAMBIÉN las líneas. En esta zona las comunas recortadas a
-- la caja tienen pocos vértices (≈190 en promedio): lo caro de ST_Intersection son los
-- recorridos (≈500 vértices, cajas de varios km). Partiendo ambos lados, cada par
-- (parte de comuna, trozo de recorrido) es barato y la caja del índice es ajustada.
DROP TABLE IF EXISTS recorridos_sub;
CREATE TABLE recorridos_sub AS
SELECT shape_id, route_id, ST_Subdivide(geom, 32)::geometry(LineString, 5361) AS geom FROM recorridos;
CREATE INDEX idx_recorridos_sub_geom ON recorridos_sub USING GIST (geom);
ANALYZE recorridos_sub;

SELECT 'comunas_zona x recorridos' AS variante, count(*) AS pares, round((sum(ST_Length(ST_Intersection(r.geom, c.geom_caja)))/1000)::numeric, 1) AS km
FROM comunas_zona c JOIN recorridos r ON ST_Intersects(r.geom, c.geom_caja)
UNION ALL
SELECT 'comunas_sub x recorridos', count(*), round((sum(ST_Length(ST_Intersection(r.geom, s.geom)))/1000)::numeric, 1)
FROM comunas_sub s JOIN recorridos r ON ST_Intersects(r.geom, s.geom)
UNION ALL
SELECT 'comunas_sub x recorridos_sub', count(*), round((sum(ST_Length(ST_Intersection(r.geom, s.geom)))/1000)::numeric, 1)
FROM comunas_sub s JOIN recorridos_sub r ON ST_Intersects(r.geom, s.geom);

-- Vértices: por qué Subdivide sobre las comunas casi no cambia nada aquí
SELECT 'comunas (en caja)' AS capa, round(avg(ST_NPoints(geom_caja))) AS vertices_prom, max(ST_NPoints(geom_caja)) AS vertices_max FROM comunas_zona
UNION ALL SELECT 'comunas_sub', round(avg(ST_NPoints(geom))), max(ST_NPoints(geom)) FROM comunas_sub
UNION ALL SELECT 'recorridos', round(avg(ST_NPoints(geom))), max(ST_NPoints(geom)) FROM recorridos
UNION ALL SELECT 'recorridos_sub', round(avg(ST_NPoints(geom))), max(ST_NPoints(geom)) FROM recorridos_sub;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT s.comuna, sum(ST_Length(ST_Intersection(r.geom, s.geom)))
FROM comunas_sub s JOIN recorridos_sub r ON ST_Intersects(r.geom, s.geom)
GROUP BY s.comuna;
