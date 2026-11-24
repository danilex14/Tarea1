-- 00 · Base: extensiones, la caja de trabajo y la bitácora del ETL.
-- Variables psql (las pasa cargar.sh): :zona :xmin :ymin :xmax :ymax  (lon/lat WGS 84)
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS hstore;

-- La caja se guarda UNA vez y todo lo demás se recorta contra ella, en la base.
DROP TABLE IF EXISTS zona CASCADE;
CREATE TABLE zona AS
SELECT :'zona'::text AS nombre,
       ST_MakeEnvelope(:xmin, :ymin, :xmax, :ymax, 4326)                       AS geom4326,
       -- En 5361 la caja deja de ser un rectángulo alineado: se transforma con densificación
       -- para que los bordes (rectos en grados) queden bien representados en metros.
       ST_Transform(ST_Segmentize(ST_MakeEnvelope(:xmin, :ymin, :xmax, :ymax, 4326), 0.001), 5361)::geometry(Polygon, 5361) AS geom;

-- Bitácora: cada paso que cambia o descarta filas deja aquí cuántas y por qué.
CREATE TABLE IF NOT EXISTS registro_etl (
    paso     text,
    detalle  text,
    n        bigint,
    cuando   timestamptz DEFAULT now()
);
TRUNCATE registro_etl;
