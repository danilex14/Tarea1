#!/usr/bin/env bash
# Exporta los resultados con ogr2ogr (PG: como ORIGEN, como en el Lab 05 4.2):
#   salidas/resultados_santiago-centro.gpkg  (5361, para QGIS; se versiona)
#   salidas/geojson/*.geojson                (4326, insumo de scripts/mapas.py)
set -euo pipefail
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
G=/salidas/resultados_santiago-centro.gpkg
mkdir -p salidas/geojson
rm -f salidas/resultados_santiago-centro.gpkg salidas/geojson/*.geojson

declare -A CAPAS
CAPAS[q1_comunas]="SELECT c.cut_com, c.comuna, c.area_caja_km2, c.pct_en_caja, count(p.stop_id) AS paraderos,
    count(p.stop_id) / c.area_caja_km2 AS por_km2, c.geom_caja AS geom
  FROM comunas_zona c LEFT JOIN paraderos_gtfs p ON ST_Contains(c.geom, p.geom)
  GROUP BY c.cut_com, c.comuna, c.area_caja_km2, c.pct_en_caja, c.geom_caja"
CAPAS[q2_cobertura]="WITH interior AS (SELECT ST_Buffer(geom, -500) AS geom FROM zona),
  e AS (SELECT c.cut_com, e.punto FROM comunas_zona c JOIN edificios e ON ST_Contains(c.geom, e.punto)
        JOIN interior i ON ST_Contains(i.geom, e.punto)),
  r AS (SELECT cut_com, count(*) AS edificios,
          100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs p WHERE ST_DWithin(p.geom, e.punto, 500))) / count(*) AS pct_lejos_gtfs,
          100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM paraderos_osm p WHERE ST_DWithin(p.geom, e.punto, 500))) / count(*) AS pct_lejos_osm
        FROM e GROUP BY cut_com HAVING count(*) >= 100)   -- igual que en q2: comunas con muy pocos edificios en la caja no se pintan
  SELECT c.comuna, r.edificios, r.pct_lejos_gtfs, r.pct_lejos_osm, c.geom_caja AS geom
  FROM comunas_zona c JOIN r USING (cut_com)"
CAPAS[q3_gtfs_sin_osm]="SELECT g.stop_id, g.stop_name, g.geom FROM paraderos_gtfs g
  WHERE g.modo LIKE '%bus%' AND NOT EXISTS (SELECT 1 FROM paraderos_osm o WHERE ST_DWithin(o.geom, g.geom, 50))"
CAPAS[q3_osm_sin_gtfs]="SELECT o.id, o.name, o.geom FROM paraderos_osm o
  WHERE NOT EXISTS (SELECT 1 FROM paraderos_gtfs g WHERE g.modo LIKE '%bus%' AND ST_DWithin(g.geom, o.geom, 50))"
CAPAS[q6_grilla]="SELECT i, j, edificios, recorridos, recorridos_bus, paraderos_gtfs, completa, geom FROM mv_grilla"
CAPAS[q6_top10]="SELECT i, j, edificios, recorridos, geom FROM mv_grilla WHERE completa AND edificios >= 200
  ORDER BY recorridos ASC, edificios DESC LIMIT 10"
CAPAS[q7_vias]="SELECT calle_id, name, highway, con_bus, sum(largo_m) AS largo_m, ST_Multi(ST_LineMerge(ST_Collect(geom))) AS geom
  FROM vias_tramos GROUP BY calle_id, name, highway, con_bus"
CAPAS[rutas]="SELECT route_id, route_short_name, route_type, n_shapes, geom FROM rutas"
CAPAS[comunas]="SELECT comuna, geom_caja AS geom FROM comunas_zona"
CAPAS[zona]="SELECT nombre, geom FROM zona"

primera=1
for capa in q1_comunas q2_cobertura q3_gtfs_sin_osm q3_osm_sin_gtfs q6_grilla q6_top10 q7_vias rutas comunas zona; do
  upd=""; [[ $primera -eq 0 ]] && upd="-update"; primera=0
  docker compose exec -T gdal sh -c "ogr2ogr -f GPKG $G \"\$PG_CONN\" $upd -a_srs EPSG:5361 -nln $capa -sql \"${CAPAS[$capa]}\"" \
    || { echo "⛔ exportación $capa falló"; exit 1; }
  docker compose exec -T gdal sh -c "ogr2ogr -f GeoJSON /salidas/geojson/$capa.geojson $G $capa -t_srs EPSG:4326 -lco COORDINATE_PRECISION=6"
done
echo "✓ exportado → salidas/resultados_santiago-centro.gpkg y salidas/geojson/ ($(ls salidas/geojson | wc -l) capas)"
