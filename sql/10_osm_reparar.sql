-- 10 · OSM: reparación de geometrías inválidas (como en el Lab 05, 1.5), contada.
-- ogr2ogr ya cargó osm_puntos / osm_lineas / osm_poligonos (SRID 5361, GiST, hstore).

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'osm_reparar', 'poligonos invalidos antes: ' || coalesce(reason, '?'), count(*)
FROM (SELECT split_part(ST_IsValidReason(geom), '[', 1) AS reason
      FROM osm_poligonos WHERE NOT ST_IsValid(geom)) r
GROUP BY reason;

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'osm_reparar', 'poligonos invalidos antes (total)', count(*) FROM osm_poligonos WHERE NOT ST_IsValid(geom);

-- ST_MakeValid puede devolver colecciones (polígono + líneas sueltas): nos quedamos solo
-- con la parte poligonal (CollectionExtract 3) y la dejamos Multi para que el tipo de la
-- columna se mantenga.
UPDATE osm_poligonos
SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
WHERE NOT ST_IsValid(geom);

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'osm_reparar', 'poligonos invalidos despues', count(*) FROM osm_poligonos WHERE NOT ST_IsValid(geom)
UNION ALL
SELECT 'osm_reparar', 'poligonos vacios tras reparar (se excluyen al derivar)', count(*) FROM osm_poligonos WHERE ST_IsEmpty(geom)
UNION ALL
SELECT 'osm_reparar', 'lineas invalidas (no se reparan: no se usan como area)', count(*) FROM osm_lineas WHERE NOT ST_IsValid(geom);
