-- =============================================================================
-- MEDI_NFC — SEED DE PROXIMIDAD GPS + BEACONS
-- -----------------------------------------------------------------------------
-- Uso:
--   psql -U proyectofinal_user -d medi_nfc2 -f seed_proximidad.sql
--
-- Qué hace:
--   Para cada evento NFC de los últimos 5 días, genera:
--     1) Una fila en ubicacion_gps con coordenadas cerca del beacon del paciente
--        (jitter pequeño = dentro del radio, jitter grande = fuera del radio)
--     2) Una fila en evento_proximidad con distancia Haversine calculada,
--        gps_verificado=TRUE y beacon_detectado según el radio
--
-- Distribución:
--     85% de eventos quedan DENTRO del radio del beacon (proximidad válida)
--     15% de eventos quedan FUERA del radio (alerta operativa de proximidad)
--
-- Idempotente: limpia evento_proximidad y borra ubicacion_gps de los últimos
-- 5 días antes de volver a poblar.
--
-- IDs y coordenadas se leen de las tablas beacon y gps_imei (no se hardcodean).
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 1: Limpiar lo previo para que el script sea re-ejecutable
-- ─────────────────────────────────────────────────────────────────────────────

-- Borrar evento_proximidad completo (FK con CASCADE no aplica aquí)
TRUNCATE TABLE evento_proximidad RESTART IDENTITY;

-- Borrar ubicaciones GPS recientes (las viejas se conservan)
DELETE FROM ubicacion_gps
WHERE timestamp_ubicacion >= CURRENT_DATE - INTERVAL '5 days';

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 2: Generar proximidades para eventos NFC recientes
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    r              RECORD;
    v_id_paciente  INTEGER;
    v_id_gps       BIGINT;
    v_id_beacon    BIGINT;
    v_lat_ref      NUMERIC(10, 7);
    v_lon_ref      NUMERIC(10, 7);
    v_radio        NUMERIC(6, 2);
    v_jitter_lat   NUMERIC(10, 7);
    v_jitter_lon   NUMERIC(10, 7);
    v_lat          NUMERIC(10, 7);
    v_lon          NUMERIC(10, 7);
    v_precision    NUMERIC(6, 2);
    v_distancia    NUMERIC(8, 2);
    v_dentro       BOOLEAN;
    v_id_ubicacion INTEGER;
    v_total        INTEGER := 0;
    v_dentro_cnt   INTEGER := 0;
    v_fuera_cnt    INTEGER := 0;
BEGIN
    FOR r IN
        SELECT en.id_evento,
               en.id_receta_medicamento,
               en.id_cuidador_lector,
               en.timestamp_lectura
        FROM   evento_nfc en
        WHERE  en.timestamp_lectura >= CURRENT_DATE - INTERVAL '5 days'
          AND  en.id_cuidador_lector IS NOT NULL
        ORDER  BY en.id_evento
    LOOP
        -- Resolver el paciente vía receta_medicamento → receta
        SELECT r2.id_paciente INTO v_id_paciente
        FROM   receta_medicamento rm
        JOIN   receta r2 ON r2.id_receta = rm.id_receta
        WHERE  rm.id_receta_medicamento = r.id_receta_medicamento;

        IF v_id_paciente IS NULL THEN
            CONTINUE;
        END IF;

        -- Obtener el beacon del paciente
        SELECT b.id_beacon, b.latitud_ref, b.longitud_ref, b.radio_metros
        INTO   v_id_beacon, v_lat_ref, v_lon_ref, v_radio
        FROM   beacon b
        WHERE  b.id_paciente = v_id_paciente
          AND  b.activo = TRUE
        LIMIT  1;

        IF v_id_beacon IS NULL THEN
            CONTINUE;
        END IF;

        -- Obtener el GPS asignado al cuidador que escaneó
        SELECT g.id_gps INTO v_id_gps
        FROM   gps_imei g
        WHERE  g.id_cuidador = r.id_cuidador_lector
          AND  g.activo = TRUE
        LIMIT  1;

        IF v_id_gps IS NULL THEN
            CONTINUE;
        END IF;

        -- Decidir si la lectura cae dentro o fuera del radio (85/15)
        v_dentro := random() < 0.85;

        IF v_dentro THEN
            -- Jitter pequeño: ±0.00004 grados ≈ ±4.4 metros (dentro de radio 8 m)
            v_jitter_lat := (random() - 0.5) * 0.00008;
            v_jitter_lon := (random() - 0.5) * 0.00008;
        ELSE
            -- Jitter grande: ±0.0005 grados ≈ ±55 metros (claramente fuera)
            v_jitter_lat := (random() - 0.5) * 0.001;
            v_jitter_lon := (random() - 0.5) * 0.001;
        END IF;

        v_lat := ROUND((v_lat_ref + v_jitter_lat)::NUMERIC, 7);
        v_lon := ROUND((v_lon_ref + v_jitter_lon)::NUMERIC, 7);

        -- Precisión GPS aleatoria realista: 2.5 a 8.0 m
        v_precision := ROUND((2.5 + random() * 5.5)::NUMERIC, 2);

        -- Distancia Haversine aproximada en metros
        -- Δlat * 111320  +  Δlon * 111320 * cos(lat)
        v_distancia := ROUND(SQRT(
              POWER((v_lat - v_lat_ref) * 111320.0, 2) +
              POWER((v_lon - v_lon_ref) * 111320.0 * COS(RADIANS(v_lat_ref)), 2)
        )::NUMERIC, 2);

        -- Insertar ubicación GPS
        INSERT INTO ubicacion_gps (
            id_gps, latitud, longitud, precision_metros,
            timestamp_ubicacion, en_domicilio_paciente
        ) VALUES (
            v_id_gps, v_lat, v_lon, v_precision,
            r.timestamp_lectura, v_dentro
        )
        RETURNING id_ubicacion INTO v_id_ubicacion;

        -- Insertar evento de proximidad
        INSERT INTO evento_proximidad (
            id_evento, id_ubicacion, id_beacon,
            distancia_metros, gps_verificado, beacon_detectado
        ) VALUES (
            r.id_evento, v_id_ubicacion, v_id_beacon,
            v_distancia,
            TRUE,                                       -- GPS sí se verificó
            (v_distancia <= v_radio)                    -- dentro del radio?
        );

        v_total := v_total + 1;
        IF v_distancia <= v_radio THEN
            v_dentro_cnt := v_dentro_cnt + 1;
        ELSE
            v_fuera_cnt := v_fuera_cnt + 1;
        END IF;
    END LOOP;

    RAISE NOTICE '──────── RESULTADO ────────';
    RAISE NOTICE 'Eventos procesados:          %', v_total;
    RAISE NOTICE 'Dentro del radio (válida):   % (%%%)',
                 v_dentro_cnt,
                 CASE WHEN v_total > 0
                      THEN ROUND(100.0 * v_dentro_cnt / v_total, 1)
                      ELSE 0 END;
    RAISE NOTICE 'Fuera del radio (alerta):    % (%%%)',
                 v_fuera_cnt,
                 CASE WHEN v_total > 0
                      THEN ROUND(100.0 * v_fuera_cnt / v_total, 1)
                      ELSE 0 END;
    RAISE NOTICE '───────────────────────────';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 2.5: Pings de tracking para cuidadores activos sin actividad NFC
-- ─────────────────────────────────────────────────────────────────────────────
-- Simula que Traccar Client sigue publicando posición en el teléfono del
-- cuidador aunque no esté escaneando medicamentos. Cada cuidador activo
-- (principal o secundario) recibe un ping reciente cerca del domicilio de
-- alguno de sus pacientes asignados.
--
-- Si un cuidador atiende varios pacientes (caso de un secundario que cubre
-- a varios), se le asigna el ping cerca del primer paciente que encuentra
-- el JOIN (no es ideal pero refleja la realidad de un GPS único por persona).
INSERT INTO ubicacion_gps (id_gps, latitud, longitud, precision_metros,
                            timestamp_ubicacion, en_domicilio_paciente)
SELECT g.id_gps,
       ROUND((b.latitud_ref  + (random() - 0.5) * 0.00006)::NUMERIC, 7),
       ROUND((b.longitud_ref + (random() - 0.5) * 0.00006)::NUMERIC, 7),
       ROUND((2.5 + random() * 5.5)::NUMERIC, 2),
       NOW() - (random() * INTERVAL '2 hours'),
       TRUE
FROM gps_imei g
JOIN paciente_cuidador pc ON pc.id_cuidador = g.id_cuidador
                          AND pc.activo     = TRUE
JOIN beacon b ON b.id_paciente = pc.id_paciente
              AND b.activo     = TRUE
WHERE g.activo = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM ubicacion_gps u
      WHERE u.id_gps = g.id_gps
        AND u.timestamp_ubicacion >= NOW() - INTERVAL '4 hours'
  );

DO $$
DECLARE v_inserts INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_inserts
    FROM ubicacion_gps
    WHERE timestamp_ubicacion >= NOW() - INTERVAL '2 hours';

    RAISE NOTICE '──────── TRACKING ─────────';
    RAISE NOTICE 'Pings de tracking añadidos: %', v_inserts;
    RAISE NOTICE '───────────────────────────';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 3: Sincronizar sequence de ubicacion_gps
-- ─────────────────────────────────────────────────────────────────────────────
SELECT setval(
    pg_get_serial_sequence('ubicacion_gps', 'id_ubicacion'),
    COALESCE((SELECT MAX(id_ubicacion) FROM ubicacion_gps), 1),
    TRUE
);

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFICACIÓN MANUAL (descomenta si quieres ver el resultado)
-- ─────────────────────────────────────────────────────────────────────────────
/*
SELECT
    pa.nombre || ' ' || pa.apellido_p AS paciente,
    med.nombre_generico               AS medicamento,
    ep.distancia_metros               AS distancia_m,
    ep.gps_verificado,
    ep.beacon_detectado,
    ep.proximidad_valida,
    en.timestamp_lectura
FROM   evento_proximidad ep
JOIN   evento_nfc en          ON en.id_evento = ep.id_evento
JOIN   receta_medicamento rm  ON rm.id_receta_medicamento = en.id_receta_medicamento
JOIN   receta r               ON r.id_receta = rm.id_receta
JOIN   paciente pa            ON pa.id_paciente = r.id_paciente
JOIN   medicamento med        ON med.id_medicamento = rm.id_medicamento
ORDER  BY en.timestamp_lectura DESC
LIMIT  20;
*/