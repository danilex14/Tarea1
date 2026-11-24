-- 90 · Índices de las tablas derivadas + ANALYZE. (Las crudas de OSM ya traen GiST de ogr2ogr.)
CREATE INDEX IF NOT EXISTS idx_calles_geom         ON calles         USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_edificios_geom      ON edificios      USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_edificios_punto     ON edificios      USING GIST (punto);
CREATE INDEX IF NOT EXISTS idx_paraderos_osm_geom  ON paraderos_osm  USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_amenidades_geom     ON amenidades     USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_amenidades_amenity  ON amenidades     (amenity);
-- Parcial: solo salud (P5). El KNN filtra por amenity; con este índice no tiene que
-- recorrer farmacias "de mentira" (bancos, bancas, estacionamientos...) en orden de distancia.
CREATE INDEX IF NOT EXISTS idx_amenidades_salud    ON amenidades     USING GIST (geom)
    WHERE amenity IN ('pharmacy', 'hospital', 'clinic', 'doctors');
CREATE INDEX IF NOT EXISTS idx_paraderos_gtfs_geom ON paraderos_gtfs USING GIST (geom);
CREATE UNIQUE INDEX IF NOT EXISTS idx_paraderos_gtfs_id ON paraderos_gtfs (stop_id);
CREATE INDEX IF NOT EXISTS idx_recorridos_geom     ON recorridos     USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_recorridos_route    ON recorridos     (route_id);
CREATE INDEX IF NOT EXISTS idx_rutas_geom          ON rutas          USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_comunas_cl_geom     ON comunas_cl     USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_comunas_zona_geom   ON comunas_zona   USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_comunas_sub_geom    ON comunas_sub    USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_gtfs_trips_shape    ON gtfs_trips     (shape_id);

ANALYZE;
