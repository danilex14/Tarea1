# Tarea 1 — PostGIS de punta a punta: Santiago centro

**Procesamiento Masivo de Datos · ELE051-B / EIN102B · USM 2026-2 · Paralelo 701**
Integrantes: **Danilo Paredes** · **Felipe Contreras**

Pregunta que ordena el trabajo: *¿cómo se relaciona la ciudad construida (OpenStreetMap) con la red de transporte público (GTFS de DTPM)?* Todo se calcula en la zona `santiago-centro` (lon −70,75…−70,52 · lat −33,52…−33,36) y en **SRID 5361** (SIRGAS-Chile / UTM 19S).

Repositorio: <https://github.com/danilex14/Tarea1>. El informe (máx. 6 páginas) está en [`informe/informe_tarea1.pdf`](informe/informe_tarea1.pdf).

---

## 1. Cómo reproducir desde cero

Requisitos: **Docker** (con `docker compose`) y **bash** (Linux, macOS, o Git Bash / WSL en Windows). Nada más: `ogr2ogr`, `unzip` y `psql` corren dentro de los contenedores. Para rehacer los mapas hace falta además Python 3 con `matplotlib` (opcional: los PNG ya están en el repo).

```bash
# 1. Dejar los tres archivos fuente en datos_fuente/ (tal cual se descargan, ver tabla abajo)
# 2. Levantar y cargar
docker compose up -d --wait
./cargar.sh                  # ~1 min: OSM + DPA + GTFS → tablas, índices, ANALYZE
# 3. Preguntas, uso de índices y exportaciones
./consultas.sh               # ~4 min: salidas/q*.txt, salidas/indices_uso.txt, salidas/*.gpkg
# 4. Mapas (opcional)
pip install matplotlib && python3 scripts/mapas.py    # salidas/mapas/*.png
# Limpieza
docker compose down -v
```

`cargar.sh` también hace `docker compose up -d --wait` por su cuenta, así que el paso 2 funciona igual si se omite el `up`. No hay rutas que editar: todo es relativo a la carpeta del repositorio. En Git Bash el script desactiva la conversión de rutas (`MSYS_NO_PATHCONV=1`) y `.gitattributes` fuerza fin de línea LF en `.sh`/`.sql`.

### Archivos fuente (no se versionan, ver `.gitignore`)

| Fuente | Archivo usado | Fecha / versión | Dónde va | De dónde |
|---|---|---|---|---|
| OpenStreetMap, extracto Chile (Geofabrik, ODbL) | `chile-261122.osm.pbf` (352,5 MB) | **datos al 22-11-2026** (extracto fechado; equivale a `chile-latest` de ese día) | `datos_fuente/` | <https://download.geofabrik.de/south-america/chile.html> |
| GTFS vigente de Santiago (DTPM) | `GTFS_20261114_v2.zip` (12,8 MB) | `feed_version` **V171.20261114**, vigencia 14-11-2026 → 31-12-2026; era el vigente al descargarlo el **23-11-2026** | `datos_fuente/` | <https://www.dtpm.cl/index.php/noticias/gtfs-vigente> |
| División Político Administrativa 2023 (IDE Chile) | ZIP del geoportal (311 MB), capa `COMUNAS/COMUNAS_v1.shp` | DPA 2023, comunas v1 (dbf del 25-04-2023) | `datos_fuente/` (cualquier nombre `.zip`) | <https://www.geoportal.cl/geoportal/catalog/download/912598ad-ac92-35f6-8045-098f214bd9c2> |

Alternativas aceptadas por el script, para quien ya hizo los labs: en vez del `.pbf`, el `osm_santiago-centro.gpkg` que deja `preparar_datos.py --zona santiago-centro` del Lab 05; en vez del ZIP de la DPA, el `comunas_cl.sql` del Lab 03. Ambos se dejan en `datos_fuente/`.

> **Nota de fuente.** El enunciado (08-09-2026) menciona `GTFS_20260829.zip`; al momento de esta entrega DTPM publica `GTFS_20261114_v2.zip`, y es el que se usó. Geofabrik publica a diario: se usó el extracto del 22-11-2026.

## 2. Estructura

```
docker-compose.yml        PostGIS 16-3.4 + caja de herramientas GDAL (imágenes públicas, nada que construir)
cargar.sh                 el único script de carga
consultas.sh              corre las 7 preguntas, el uso de índices y la exportación
sql/                      el ETL, en orden: 00 base · 10–11 OSM · 20–21 GTFS · 30 comunas · 90 índices · 99 conteos
consultas/q1..q7_*.sql    una pregunta por archivo (consulta + EXPLAIN ANALYZE donde corresponde)
scripts/exportar.sh       PostGIS → salidas/resultados_santiago-centro.gpkg (5361) y GeoJSON (4326)
scripts/mapas.py          GeoJSON → salidas/mapas/*.png
salidas/                  resultados versionados: q*.txt, conteos.txt, indices_uso.txt, carga.log, fuentes.json, mapas, GeoPackage
informe/                  informe PDF
datos_fuente/  datos/     entrada e intermedios (NO versionados)
```

## 3. Infraestructura

- **`db`**: `postgis/postgis:16-3.4` (PostgreSQL 16 + PostGIS 3.4, las versiones del curso). Volumen con nombre `t1-pgdata`, puerto `5435` (el Lab 05 usa 5434: conviven). Montajes: `./datos`, `./sql`, `./consultas` (solo lectura) y `./salidas`. Ajustes de memoria moderados (`shared_buffers=1GB`, `work_mem=64MB`) y `jit=off`.
- **`gdal`**: `osgeo/gdal:ubuntu-small-3.6.3`, queda dormido y el script le hace `exec` para `ogr2ogr`, `ogrinfo` y `unzip`. Se conecta a `db` por la red de compose.
- **Por qué dos imágenes públicas y no el `Dockerfile` del Lab 05**: así `docker compose up -d` no depende de un `apt-get` durante la construcción (el paso que más falla con red restringida) y la carga funciona en una máquina limpia sin construir nada.
- **Healthcheck** `pg_isready -h 127.0.0.1`: durante la inicialización de un volumen nuevo PostgreSQL escucha solo por socket; sin `-h` el healthcheck daba "listo" antes de terminar los scripts de initdb y el primer `CREATE EXTENSION` del ETL chocaba con el de la imagen (ver §7).

## 4. ETL: tablas, conteos e índices

Conteos de la carga del 24-11-2026 (64 s desde un volumen vacío) (copiados de `salidas/conteos.txt`, que el script regenera):

| Tabla | Filas | Origen / qué es | Índices |
|---|---:|---|---|
| `osm_puntos` | 258.830 | OSM crudo (`ogr2ogr`, `other_tags` como hstore) | GiST `geom`, PK |
| `osm_lineas` | 170.536 | OSM crudo | GiST `geom`, PK |
| `osm_poligonos` | 149.895 | OSM crudo, **375 reparados** con `ST_MakeValid` | GiST `geom`, PK |
| `calles` | 101.584 | `osm_lineas` con `highway` | GiST `geom` |
| `edificios` | 121.207 | `osm_poligonos` con `building`, polígono + **punto interior** | GiST `geom`, GiST `punto` |
| `paraderos_osm` | 6.574 | `osm_puntos` con `highway = 'bus_stop'` | GiST `geom` |
| `amenidades` | 21.149 | `amenity` de puntos (en `other_tags`) y de polígonos (punto interior) | GiST `geom`, B-tree `amenity`, GiST **parcial** salud |
| `paraderos_gtfs` | 6.819 | `stops.txt` → `ST_MakePoint(lon, lat)` 4326 → 5361, en la caja | GiST `geom`, único `stop_id` |
| `recorridos` | 699 | **una LineString por `shape_id`** (`ST_MakeLine … ORDER BY shape_pt_sequence`) que toca la caja | GiST `geom`, B-tree `route_id` |
| `rutas` | 344 | los shapes de cada ruta juntos (MultiLineString) | GiST `geom` |
| `paradero_ruta` | 40.313 | pares (paradero, ruta) desde `stop_times` → `trips` | B-tree ×2 |
| `comunas_cl` | 345 | DPA 2023, 5360 → 5361 | GiST `geom`, PK |
| `comunas_zona` | 30 | comunas que tocan la caja, con área total y área en la caja | GiST `geom` |
| `comunas_sub` | 67 | `ST_Subdivide(comuna ∩ caja, 128)` | GiST `geom` |
| `gtfs_stop_times` | 1.098.717 | `stop_times.txt` crudo, por **COPY** | B-tree `trip_id` |
| `gtfs_shapes` | 456.784 | `shapes.txt` crudo, por **COPY** | — |

Además, creadas por las consultas: `mv_grilla` (vista materializada, 636 hexágonos), `recorridos_sub` y `recorridos_seg` (recorridos partidos con `ST_Subdivide`), `vias_tramos` (97.030 tramos de ≤ 50 m de vías principales). Todas con GiST y `ANALYZE`.

La bitácora completa de lo que se descartó o reparó queda en la tabla `registro_etl` y en `salidas/conteos.txt`.

## 5. Decisiones

- **SRID 5361** para todo cálculo (metros reales en Santiago). OSM se reproyecta al recortar (`-t_srs EPSG:5361`), la DPA se declara 5360 y se reproyecta (como el `-s 5360:5361` del Lab 03), el GTFS se construye en 4326 y se transforma una vez. Los GeoJSON para mapas se exportan en 4326 porque el estándar lo exige.
- **Recorte de la caja en la base.** La caja se guarda una vez en la tabla `zona` (en 4326 y, densificada, en 5361). Paraderos GTFS: los que caen dentro; recorridos: los shapes que la **tocan** (se conservan enteros y se recortan por comuna en P4).
- **Punto interior vs. polígono.** Edificios y amenidades poligonales se asignan a comuna/hexágono por `ST_PointOnSurface` (no `ST_Centroid`, que puede caer fuera de un edificio en "L"): así un edificio que cruza un límite se cuenta una sola vez. El polígono se conserva para áreas.
- **Reparaciones (OSM).** 375 polígonos inválidos antes de reparar: 236 con anillos de 3 puntos, 79 con anillos de 2 puntos y 60 auto-intersecciones. `ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))` deja **0 inválidos**; 315 quedan vacíos (eran anillos degenerados) y se excluyen al derivar, de ellos **203 eran edificios**. 1 línea inválida no se repara (no se usa como área). Las 345 comunas de la DPA son válidas.
- **Paraderos GTFS**: solo puntos de abordaje (`location_type` vacío o 0). Se agrega `modo` (bus 6.576 · metro 234 · tren EFE 8 · sin servicio 1) y `n_rutas` desde `stop_times`. En P3 se compara solo el modo bus con `bus_stop` de OSM.
- **Shapes múltiples por ruta (ida, vuelta, variantes).** Se conserva **cada shape como una fila**: ida y vuelta son trazados físicos distintos. Verificado que ningún shape es compartido por dos rutas. Todo lo que cuenta "recorridos distintos" usa `count(DISTINCT route_id)`; los km de P4 se informan sumando todos los shapes (km de servicio) y solo `direction_id = 0` (≈ un sentido). Sin secuencias repetidas ni shapes de menos de 2 puntos; 254 shapes no son simples (circuitos que se cruzan a sí mismos), lo que es normal y no se corrige.
- **stop_times.txt** (1.098.717 filas) se carga con `COPY` del lado del servidor, en tablas `UNLOGGED` (son intermedias, se reconstruyen desde el ZIP), con columnas `text` y tipado al derivar. El script valida las cabeceras de cada CSV antes del COPY. Ojo: en este GTFS los viajes son plantillas con `frequencies.txt`, así que **contar filas de stop_times no es contar buses**; por eso se cuentan rutas distintas.
- **Densidades por área dentro de la caja**: solo se cargaron paraderos y edificios de la caja, así que dividir por el área total subestimaría las comunas cortadas (Las Condes se ve en un 31 %, La Florida en un 13 %).

## 6. Índices: cuáles se usaron (`salidas/indices_uso.txt`)

`consultas.sh` reinicia las estadísticas y corre P1–P7. Resultado:

- **Muy usados:** `idx_paraderos_gtfs_geom` (344 mil lecturas), `idx_paraderos_osm_geom` (242 mil), `idx_recorridos_seg_geom` (194 mil), `idx_recorridos_geom` (99 mil), `idx_amenidades_salud` (el parcial: 702), `idx_edificios_punto` (666).
- **Sin uso (0 lecturas):** `idx_edificios_geom` (4,9 MB: todo se hizo por el punto interior), `idx_amenidades_geom` (el planificador prefiere el parcial de salud), los GiST de las tablas crudas `osm_*` (24 MB entre los tres: después de derivar nadie las consulta), `idx_comunas_sub_geom` y `idx_comunas_cl_geom` (las comunas siempre van del lado de afuera del nested loop), `idx_rutas_geom`, `idx_recorridos_route`, `idx_gtfs_trips_shape`, los B-tree de `paradero_ruta`. Son un hallazgo: en un pipeline de producción se borrarían o no se crearían.

## 7. Qué no funcionó (y cómo se resolvió)

- **Carrera del healthcheck.** Con el volumen recién creado, `pg_isready` sin `-h` respondía "listo" mientras corrían los scripts de inicialización de la imagen; el `CREATE EXTENSION postgis` del ETL chocó con el de la imagen y el contenedor terminó con error. Se arregló chequeando por TCP (`-h 127.0.0.1`).
- **Exportación sin SRID.** `ogr2ogr` con `-sql` y un `WITH` no detectó el SRID de la geometría: el GeoJSON de P2 salió en metros en vez de grados. Se fuerza `-a_srs EPSG:5361` en todas las exportaciones.
- **`ST_Subdivide` no aceleró P4** (ver informe): las comunas recortadas a la caja tienen en promedio 191 vértices y lo caro de `ST_Intersection` son los recorridos (≈ 500 vértices). Subdividir comunas, o comunas y recorridos, da tiempos dentro del ruido (0,7–1,0 s entre corridas). Se dejó documentado como hallazgo.
- **El índice sobre los recorridos enteros casi no filtra.** Un shape tiene una caja de varios km; en P7 el anti-join contra `recorridos` tardó 14,0 s y contra `recorridos_seg` (partidos con `ST_Subdivide(geom, 16)`) 0,60 s, con el mismo resultado.
- **Sin probar en Windows nativo.** El pipeline se probó de punta a punta en Linux (Docker 29, máquina limpia: volumen borrado y `datos/` vacío). En Windows debería funcionar con Git Bash + Docker Desktop; si `cargar.sh` falla por fin de línea, `git config core.autocrlf false` y volver a clonar.
