-- 30 · DPA 2023: comunas oficiales (Lab 03), ya en 5361 (cargadas por cargar.sh).
DROP TABLE IF EXISTS comunas_zona, comunas_sub CASCADE;

-- Las comunas que tocan la caja, con su área total y el área DENTRO de la caja.
-- Las densidades se calculan con el área dentro de la caja: los paraderos y edificios
-- fuera de ella no se cargaron, así que dividir por el área total subestimaría la
-- densidad de las comunas cortadas (La Florida, Las Condes, Peñalolén, ...).
CREATE TABLE comunas_zona AS
SELECT c.cut_com, c.comuna, c.provincia, c.region,
       ST_Area(c.geom) / 1e6 AS area_km2,
       ST_Area(ST_Intersection(c.geom, z.geom)) / 1e6 AS area_caja_km2,
       ST_Multi(ST_Intersection(c.geom, z.geom))::geometry(MultiPolygon, 5361) AS geom_caja,
       c.geom::geometry(MultiPolygon, 5361) AS geom
FROM comunas_cl c, zona z
WHERE ST_Intersects(c.geom, z.geom);
ALTER TABLE comunas_zona ADD COLUMN pct_en_caja numeric;
UPDATE comunas_zona SET pct_en_caja = round((100 * area_caja_km2 / area_km2)::numeric, 1);

-- ST_Subdivide: partes de ≤128 vértices. Cajas chicas → menos falsos positivos en la
-- fase 1 del índice y ST_Intersects/ST_Intersection mucho más baratos en la fase 2.
-- Se subdivide la parte DENTRO de la caja (geom_caja): es la que tiene datos.
-- Sirve para joins; NO para nada que trate a la comuna como un objeto (área, conteos).
CREATE TABLE comunas_sub AS
SELECT cut_com, comuna, ST_Subdivide(geom_caja, 128)::geometry(Polygon, 5361) AS geom
FROM comunas_zona;

INSERT INTO registro_etl (paso, detalle, n)
SELECT 'comunas', 'comunas_cl (pais)', count(*) FROM comunas_cl
UNION ALL SELECT 'comunas', 'comunas que tocan la caja', count(*) FROM comunas_zona
UNION ALL SELECT 'comunas', 'partes de comunas_sub (128 vertices)', count(*) FROM comunas_sub
UNION ALL SELECT 'comunas', 'comunas_cl invalidas', count(*) FROM comunas_cl WHERE NOT ST_IsValid(geom);
