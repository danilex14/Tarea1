#!/usr/bin/env bash
# Tarea 1 — carga completa: tres fuentes → PostGIS (SRID 5361), indexado y con ANALYZE.
#
#   docker compose up -d --wait   (opcional: el script lo hace igual)
#   ./cargar.sh                   # todo
#   ./cargar.sh gtfs comunas      # solo algunas etapas: osm | comunas | gtfs | indices
#
# Requisitos en la máquina: Docker con compose y bash (Linux, macOS, o Git Bash / WSL en
# Windows). Nada más: ogr2ogr, unzip y psql corren dentro de los contenedores.
# Los archivos fuente van en datos_fuente/ (ver README.md y datos_fuente/LEEME.md).
set -euo pipefail
export MSYS_NO_PATHCONV=1          # Git Bash en Windows: no convertir /sql/... en C:/Program Files/Git/sql/...
cd "$(dirname "$0")"

# ------------------------------------------------------------------ zona de trabajo
ZONA="${ZONA:-santiago-centro}"
BBOX="${BBOX:--70.75 -33.52 -70.52 -33.36}"     # xmin ymin xmax ymax (lon/lat). Enunciado, sección 2.
read -r XMIN YMIN XMAX YMAX <<<"$BBOX"
GPKG="/datos/osm_${ZONA}.gpkg"

ETAPAS="${*:-osm comunas gtfs indices}"
mkdir -p datos salidas
LOG="salidas/carga.log"
: > "$LOG"

t_total=$(date +%s)
paso()  { printf '\n\033[1m== %s\033[0m\n' "$*" | tee -a "$LOG"; t0=$(date +%s); }
hecho() { echo "   ✓ $(( $(date +%s) - t0 )) s" | tee -a "$LOG"; }
falla() { echo "⛔ $*" | tee -a "$LOG" >&2; exit 1; }
quiere(){ [[ " $ETAPAS " == *" $1 "* ]]; }

dc()    { docker compose "$@"; }
psqlf() { dc exec -T -e PGOPTIONS=--client-min-messages=warning db psql -X -q -v ON_ERROR_STOP=1 -U postgres -d tarea1 \
            -v zona="$ZONA" -v xmin="$XMIN" -v ymin="$YMIN" -v xmax="$XMAX" -v ymax="$YMAX" "$@"; }
gdal()  { dc exec -T gdal "$@"; }

# ------------------------------------------------------------------ 0. fuentes
paso "0. Fuentes en datos_fuente/"
PBF=$(ls datos_fuente/*.osm.pbf 2>/dev/null | head -1 || true)
GPKG_LISTO=$(ls "datos_fuente/osm_${ZONA}.gpkg" 2>/dev/null || true)  # el de preparar_datos.py del Lab 05, si ya lo tienen
GTFS_ZIP=$(ls datos_fuente/GTFS*.zip datos_fuente/gtfs*.zip 2>/dev/null | head -1 || true)
DPA_SQL=$(ls datos_fuente/comunas_cl.sql 2>/dev/null || true)          # el de preparar_datos.py del Lab 03, si ya lo tienen
DPA_ZIP=""
for z in datos_fuente/*.zip; do
  [[ -e "$z" && "$z" != "$GTFS_ZIP" ]] && DPA_ZIP="$z" && break
done
if quiere osm; then
  [[ -n "$PBF" || -n "$GPKG_LISTO" || -f "datos/osm_${ZONA}.gpkg" ]] || falla "Falta chile-latest.osm.pbf en datos_fuente/ (https://download.geofabrik.de/south-america/chile-latest.osm.pbf)"
  echo "   OSM:  ${PBF:-${GPKG_LISTO:-datos/osm_${ZONA}.gpkg}}" | tee -a "$LOG"
fi
if quiere gtfs; then
  [[ -n "$GTFS_ZIP" ]] || falla "Falta el ZIP del GTFS (GTFS_*.zip) en datos_fuente/ (https://www.dtpm.cl/index.php/noticias/gtfs-vigente)"
  echo "   GTFS: $GTFS_ZIP" | tee -a "$LOG"
fi
if quiere comunas; then
  [[ -n "$DPA_SQL" || -n "$DPA_ZIP" ]] || falla "Falta el ZIP de la DPA 2023 (o comunas_cl.sql del Lab 03) en datos_fuente/"
  echo "   DPA:  ${DPA_SQL:-$DPA_ZIP}" | tee -a "$LOG"
fi
echo "   Zona: $ZONA · caja lon [$XMIN, $XMAX] · lat [$YMIN, $YMAX]" | tee -a "$LOG"

paso "1. Contenedores (docker compose up -d --wait)"
dc up -d --wait >>"$LOG" 2>&1 || falla "docker compose up falló (ver $LOG)"
psqlf -f /sql/00_base.sql
hecho

# ------------------------------------------------------------------ 2. OSM
if quiere osm; then
  paso "2a. OSM: recorte de la caja y reproyección a 5361 → datos/osm_${ZONA}.gpkg"
  if [[ -f "datos/osm_${ZONA}.gpkg" ]]; then
    echo "   ya existe, se reutiliza (bórrenlo para rehacerlo)"
  elif [[ -n "$GPKG_LISTO" ]]; then
    cp "$GPKG_LISTO" "datos/osm_${ZONA}.gpkg"; echo "   copiado desde $GPKG_LISTO"
  else
    # Lo mismo que hace preparar_datos.py --zona santiago-centro del Lab 05.
    gdal ogr2ogr -f GPKG "$GPKG" "/fuente/$(basename "$PBF")" points lines multipolygons \
         -spat "$XMIN" "$YMIN" "$XMAX" "$YMAX" -t_srs EPSG:5361 \
         --config OSM_MAX_TMPFILE_SIZE 4000 >>"$LOG" 2>&1 || falla "ogr2ogr (recorte) falló (ver $LOG)"
  fi
  hecho

  paso "2b. OSM: GeoPackage → PostGIS (ogr2ogr, hstore, GiST)"
  for par in points:osm_puntos lines:osm_lineas multipolygons:osm_poligonos; do
    capa=${par%%:*}; tabla=${par##*:}; t1=$(date +%s)
    gdal sh -c "ogr2ogr -f PostgreSQL \"\$PG_CONN\" $GPKG $capa -nln $tabla -overwrite \
         -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=GIST -lco COLUMN_TYPES=other_tags=hstore -lco FID=id \
         --config PG_USE_COPY YES" >>"$LOG" 2>&1 || falla "ogr2ogr ($capa) falló (ver $LOG)"
    echo "   $capa → $tabla  $(( $(date +%s) - t1 )) s" | tee -a "$LOG"
  done
  hecho

  paso "2c. OSM: reparar geometrías (ST_MakeValid) y derivar capas"
  psqlf -f /sql/10_osm_reparar.sql
  psqlf -f /sql/11_osm_derivadas.sql
  hecho
fi

# ------------------------------------------------------------------ 3. DPA
if quiere comunas; then
  paso "3. DPA 2023: comunas_cl en 5361"
  if [[ -n "$DPA_SQL" ]]; then
    # Camino Lab 03: el .sql de shp2pgsql (-s 5360:5361) ya trae la tabla comunas_cl.
    dc cp "$DPA_SQL" db:/tmp/comunas_cl.sql
    psqlf -c "DROP TABLE IF EXISTS comunas_cl CASCADE" -f /tmp/comunas_cl.sql >>"$LOG"
  else
    gdal sh -c "rm -rf /datos/dpa && mkdir -p /datos/dpa && unzip -q -o '/fuente/$(basename "$DPA_ZIP")' 'COMUNAS/*' -d /datos/dpa" \
      || falla "No se pudo extraer COMUNAS/ de $DPA_ZIP"
    SHP=$(gdal sh -c "ls /datos/dpa/COMUNAS/*.shp | head -1" | tr -d '\r')
    # La DPA 2023 viene en SIRGAS-Chile geográfico (EPSG:5360): se declara y se reproyecta,
    # igual que el -s 5360:5361 de shp2pgsql en el Lab 03.
    gdal sh -c "ogr2ogr -f PostgreSQL \"\$PG_CONN\" '$SHP' -nln comunas_cl -overwrite \
         -s_srs EPSG:5360 -t_srs EPSG:5361 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=gid \
         -lco SPATIAL_INDEX=NONE --config PG_USE_COPY YES" >>"$LOG" 2>&1 || falla "ogr2ogr (comunas) falló (ver $LOG)"
  fi
  psqlf -c "UPDATE comunas_cl SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3)) WHERE NOT ST_IsValid(geom)" >>"$LOG"
  psqlf -f /sql/30_comunas.sql
  hecho
fi

# ------------------------------------------------------------------ 4. GTFS
if quiere gtfs; then
  paso "4a. GTFS: descomprimir $(basename "$GTFS_ZIP")"
  gdal sh -c "rm -rf /datos/gtfs && mkdir -p /datos/gtfs && unzip -q -o '/fuente/$(basename "$GTFS_ZIP")' -d /datos/gtfs"
  # Validar cabeceras: el COPY carga por posición, así que si DTPM cambia columnas hay que saberlo.
  declare -A ESPERADA=(
    [feed_info]="feed_publisher_name,feed_publisher_url,feed_lang,feed_start_date,feed_end_date,feed_version"
    [routes]="route_id,agency_id,route_short_name,route_long_name,route_desc,route_type,route_url,route_color,route_text_color"
    [trips]="route_id,service_id,trip_id,trip_headsign,direction_id,shape_id,trip_short_name,wheelchair_accessible,bikes_allowed"
    [stops]="stop_id,stop_code,stop_name,stop_lat,stop_lon,stop_url,wheelchair_boarding,location_type,parent_station,level_id"
    [shapes]="shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence"
    [stop_times]="trip_id,arrival_time,departure_time,stop_id,stop_sequence,pickup_type,drop_off_type,timepoint"
  )
  for f in "${!ESPERADA[@]}"; do
    cab=$(head -1 "datos/gtfs/$f.txt" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
    [[ "$cab" == "${ESPERADA[$f]}" ]] || falla "$f.txt cambió de columnas:\n   esperado: ${ESPERADA[$f]}\n   viene:    $cab"
  done
  echo "   cabeceras OK · stop_times.txt: $(( $(wc -l < datos/gtfs/stop_times.txt) - 1 )) filas" | tee -a "$LOG"
  hecho

  paso "4b. GTFS: COPY de los CSV crudos"
  psqlf -f /sql/20_gtfs_crudo.sql
  hecho

  paso "4c. GTFS: paraderos (ST_MakePoint) y recorridos (ST_MakeLine ORDER BY secuencia)"
  N=$(psqlf -At -c "SELECT count(*) FROM (SELECT shape_id FROM gtfs_trips WHERE shape_id <> '' GROUP BY shape_id HAVING count(DISTINCT route_id) > 1) x")
  echo "   shapes compartidos por más de una ruta: $N" | tee -a "$LOG"
  psqlf -f /sql/21_gtfs_derivadas.sql
  hecho
fi

# ------------------------------------------------------------------ 5. índices y resumen
if quiere indices; then
  paso "5. Índices espaciales y ANALYZE"
  psqlf -f /sql/90_indices.sql
  hecho
  paso "6. Resumen → salidas/conteos.txt y salidas/fuentes.json"
  FEED=$(psqlf -At -c "SELECT feed_version || ' (vigencia ' || feed_start_date || '–' || feed_end_date || ')' FROM gtfs_feed_info" | tr -d '\r')
  OSM_F=$(basename "${PBF:-${GPKG_LISTO:-datos/osm_${ZONA}.gpkg}}")
  if [[ "$OSM_F" =~ chile-([0-9]{2})([0-9]{2})([0-9]{2})\.osm\.pbf ]]; then   # extracto fechado de Geofabrik
    OSM_D="datos al 20${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
  else
    OSM_D="descargado el $(date -r "${PBF:-${GPKG_LISTO:-datos/osm_${ZONA}.gpkg}}" +%F 2>/dev/null || echo '?')"
  fi
  printf '{\n  "zona": "%s",\n  "bbox": "%s",\n  "osm": "%s (%s)",\n  "gtfs": "%s · %s",\n  "dpa": "DPA 2023 (IDE Chile, comunas v1)"\n}\n' \
    "$ZONA" "$BBOX" "$OSM_F" "$OSM_D" "$(basename "$GTFS_ZIP")" "$FEED" > salidas/fuentes.json
  cat salidas/fuentes.json | tee -a "$LOG"
  psqlf -f /sql/99_conteos.sql > salidas/conteos.txt
  cat salidas/conteos.txt | tee -a "$LOG"
  hecho
fi

echo -e "\n✅ Carga completa en $(( $(date +%s) - t_total )) s. Siguiente: ./consultas.sh" | tee -a "$LOG"
