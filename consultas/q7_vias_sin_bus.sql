-- P7 (propia) · ¿Qué parte de las vías principales de la ciudad (OSM) no tiene ningún
-- recorrido de bus (GTFS) encima?
-- Cruza las dos fuentes línea contra línea: la red vial que existe (OSM: highway trunk,
-- primary, secondary, tertiary) vs. la red de buses que el operador declara (GTFS shapes,
-- route_type = 3). Un tramo de vía principal sin buses es capacidad vial no usada por el
-- transporte público (o un corredor que el GTFS no cubre).
-- Método: cada vía se corta en tramos de ≤ 50 m (ST_Segmentize + ST_DumpSegments); un tramo
-- está "servido" si algún trazado de bus pasa a ≤ 25 m de su punto medio (los shapes de
-- DTPM van por el eje de la calzada; 25 m absorbe calzadas dobles y error de digitalización).
-- Se usa recorridos_seg: los shapes partidos con ST_Subdivide, porque un shape entero tiene
-- una caja de varios km y el índice GiST casi no filtra (ver plan).
DROP TABLE IF EXISTS vias_tramos, recorridos_seg;

CREATE TABLE recorridos_seg AS
SELECT shape_id, route_id, ST_Subdivide(geom, 16)::geometry(LineString, 5361) AS geom
FROM recorridos WHERE route_type = 3;
CREATE INDEX idx_recorridos_seg_geom ON recorridos_seg USING GIST (geom);

CREATE TABLE vias_tramos AS
SELECT v.id AS calle_id, v.name, v.highway, ST_Length(d.geom) AS largo_m,
       d.geom::geometry(LineString, 5361) AS geom,
       ST_LineInterpolatePoint(d.geom, 0.5)::geometry(Point, 5361) AS medio
FROM calles v, zona z,
     LATERAL ST_DumpSegments(ST_Segmentize(v.geom, 50)) AS d
WHERE v.highway IN ('trunk', 'primary', 'secondary', 'tertiary')
  AND ST_Within(v.geom, z.geom);
CREATE INDEX idx_vias_tramos_medio ON vias_tramos USING GIST (medio);
ALTER TABLE vias_tramos ADD COLUMN con_bus boolean;
UPDATE vias_tramos t SET con_bus = EXISTS (
    SELECT 1 FROM recorridos_seg r WHERE ST_DWithin(r.geom, t.medio, 25));
ANALYZE recorridos_seg, vias_tramos;

-- Por tipo de vía
SELECT highway,
       round((sum(largo_m) / 1000)::numeric, 1) AS km,
       round((sum(largo_m) FILTER (WHERE NOT con_bus) / 1000)::numeric, 1) AS km_sin_bus,
       round((100 * sum(largo_m) FILTER (WHERE NOT con_bus) / sum(largo_m))::numeric, 1) AS pct_sin_bus
FROM vias_tramos GROUP BY highway
ORDER BY array_position(ARRAY['trunk','primary','secondary','tertiary'], highway);

-- Por comuna (tramo → comuna por su punto medio)
SELECT c.comuna,
       round((sum(t.largo_m) / 1000)::numeric, 1) AS km_vias_principales,
       round((coalesce(sum(t.largo_m) FILTER (WHERE NOT t.con_bus), 0) / 1000)::numeric, 1) AS km_sin_bus,
       round((100 * coalesce(sum(t.largo_m) FILTER (WHERE NOT t.con_bus), 0) / sum(t.largo_m))::numeric, 1) AS pct_sin_bus
FROM comunas_zona c JOIN vias_tramos t ON ST_Contains(c.geom, t.medio)
GROUP BY c.comuna
HAVING sum(t.largo_m) > 5000
ORDER BY pct_sin_bus DESC;

-- Las vías principales con más km sin buses (por nombre)
SELECT coalesce(name, '(sin nombre)') AS via, highway,
       round((sum(largo_m) FILTER (WHERE NOT con_bus) / 1000)::numeric, 2) AS km_sin_bus,
       round((sum(largo_m) / 1000)::numeric, 2) AS km_total
FROM vias_tramos GROUP BY name, highway
HAVING sum(largo_m) FILTER (WHERE NOT con_bus) > 0
ORDER BY km_sin_bus DESC LIMIT 15;

-- Plan: recorridos enteros vs. recorridos_seg (mismo resultado, distinto costo)
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM vias_tramos t
WHERE EXISTS (SELECT 1 FROM recorridos r WHERE r.route_type = 3 AND ST_DWithin(r.geom, t.medio, 25));

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM vias_tramos t
WHERE EXISTS (SELECT 1 FROM recorridos_seg r WHERE ST_DWithin(r.geom, t.medio, 25));
