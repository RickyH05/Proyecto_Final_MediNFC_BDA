-- =============================================================================
-- MEDI_NFC2 — SEED COMPLETO v2
-- -----------------------------------------------------------------------------
-- Incluye:
--   • Catálogos, médico, cuidadores, pacientes (mismos que v1)
--   • Recetas con fecha_inicio = CURRENT_DATE - 30
--   • Agendas generadas automáticamente por trigger
--   • ~60 eventos NFC históricos reales (30 días)
--   • Patrones de adherencia distintos por paciente:
--       Elena    → buena adherencia ~80% (MEJORA)
--       Héctor   → irregular ~55% (DECLIVE últimos 7 días)
--       Consuelo → empieza bien, cae últimos 10 días (DECLIVE)
--   • Usuarios con contraseña Password1!
--
-- PASOS:
--   1. Borrar datos existentes
--   2. Reinsertar catálogos + entidades
--   3. Insertar recetas (trigger genera agendas automáticamente)
--   4. Marcar agendas pasadas como omitidas
--   5. Insertar eventos NFC y marcar agendas correspondientes
--
-- Horas programadas (definidas en receta_medicamento):
--   RM1 Metformina  Elena    → 08:00 y 20:00  (c/12h)
--   RM2 Losartán    Elena    → 20:00          (c/24h)
--   RM3 Digoxina    Héctor   → 09:00          (c/24h)
--   RM4 Rivastigmina Consuelo→ 07:30 y 19:30  (c/12h)
--   RM5 Calcio      Consuelo → 13:00          (c/24h)
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 1: LIMPIAR TODO
-- ─────────────────────────────────────────────────────────────────────────────
TRUNCATE TABLE
    log_acceso, audit_cambios, bitacora_regla_negocio,
    evento_proximidad, evento_nfc,
    agenda_toma, etiqueta_nfc,
    receta_medicamento, receta,
    paciente_cuidador, cuidador_horario,
    paciente_diagnostico,
    ubicacion_gps, gps_imei, beacon,
    medico_especialidad,
    paciente, cuidador, medico, usuario,
    medicamento_via, medicamento_nombre_comercial, medicamento,
    unidad_dosis, via_administracion,
    especialidad, diagnostico
    RESTART IDENTITY CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 2: CATÁLOGOS
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO diagnostico (id_diagnostico, descripcion) OVERRIDING SYSTEM VALUE VALUES
  (1, 'Diabetes Mellitus Tipo 2'),
  (2, 'Hipertensión Arterial'),
  (3, 'Insuficiencia Cardíaca Congestiva'),
  (4, 'Enfermedad de Alzheimer'),
  (5, 'Osteoporosis'),
  (6, 'Fibrilación Auricular')
ON CONFLICT (descripcion) DO NOTHING;

INSERT INTO especialidad (id_especialidad, descripcion) OVERRIDING SYSTEM VALUE VALUES
  (1, 'Geriatría'),
  (2, 'Cardiología'),
  (3, 'Neurología')
ON CONFLICT (descripcion) DO NOTHING;

INSERT INTO via_administracion (id_via, descripcion) OVERRIDING SYSTEM VALUE VALUES
  (1, 'Oral'),
  (2, 'Subcutánea'),
  (3, 'Intravenosa'),
  (4, 'Transdérmica')
ON CONFLICT (descripcion) DO NOTHING;

INSERT INTO unidad_dosis (id_unidad, abreviatura, descripcion) OVERRIDING SYSTEM VALUE VALUES
  (1, 'mg',   'Miligramos'),
  (2, 'ml',   'Mililitros'),
  (3, 'mcg',  'Microgramos'),
  (4, 'UI',   'Unidades Internacionales'),
  (5, 'comp', 'Comprimidos')
ON CONFLICT (descripcion) DO NOTHING;

INSERT INTO medicamento (id_medicamento, nombre_generico, codigo_atc, dosis_max, activo, id_unidad)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'Metformina',    'A10BA02',  2000, TRUE, 1),
  (2, 'Losartán',      'C09CA01',   100, TRUE, 1),
  (3, 'Digoxina',      'C01AA05',   250, TRUE, 3),
  (4, 'Rivastigmina',  'N06DA03',    12, TRUE, 1),
  (5, 'Calcio + Vit D','A12AX',    1200, TRUE, 1)
ON CONFLICT DO NOTHING;

INSERT INTO medicamento_nombre_comercial (id_medicamento, nombre_comercial) VALUES
  (1, 'Glucophage'), (2, 'Cozaar'), (3, 'Lanoxin'), (4, 'Exelon'), (5, 'Caltrate')
ON CONFLICT DO NOTHING;

INSERT INTO medicamento_via (id_medicamento, id_via) VALUES
  (1,1),(2,1),(3,1),(4,1),(5,1)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 3: MÉDICO
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO medico (id_medico, nombre, apellido_p, apellido_m,
                    cedula_profesional, email, activo, foto_perfil)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'Roberto', 'Garza', 'Herrera', 'CED-12345678', 'dr.garza@medinfc.mx', TRUE, 'default_medico.png')
ON CONFLICT DO NOTHING;

INSERT INTO medico_especialidad (id_medico, id_especialidad) VALUES (1,1),(1,2)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 4: CUIDADORES
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO cuidador (id_cuidador, nombre, apellido_p, apellido_m,
                      tipo_cuidador, telefono, email, activo, foto_perfil)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'María',    'López',   'Sánchez', 'formal',   '8110001111', 'maria.lopez@medinfc.mx',     TRUE, 'default_cuidador.png'),
  (2, 'Carlos',   'Ramírez', 'Vega',    'informal', '8112223333', 'carlos.ramirez@medinfc.mx',  TRUE, 'default_cuidador.png'),
  (3, 'Patricia', 'Morales', 'Torres',  'informal', '8114445555', 'patricia.morales@medinfc.mx',TRUE, 'default_cuidador.png')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 5: PACIENTES
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO paciente (id_paciente, nombre, apellido_p, apellido_m,
                      fecha_nacimiento, curp, activo, foto_perfil)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'Elena',    'Martínez','Cruz',   '1950-03-12', 'MACE500312MNLRZL01', TRUE, 'default_paciente.png'),
  (2, 'Héctor',   'González','Pérez',  '1943-07-28', 'GOPH430728HNLLRC02', TRUE, 'default_paciente.png'),
  (3, 'Consuelo', 'Vázquez', 'Moreno', '1947-11-05', 'VAMC471105MNLZRN03', TRUE, 'default_paciente.png')
ON CONFLICT DO NOTHING;

INSERT INTO paciente_diagnostico (id_paciente, id_diagnostico, activo) VALUES
  (1,1,TRUE),(1,2,TRUE),(2,3,TRUE),(2,6,TRUE),(3,4,TRUE),(3,5,TRUE)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 6: GPS, BEACONS
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO gps_imei (id_gps, imei, modelo, id_cuidador, activo, fecha_asignacion)
OVERRIDING SYSTEM VALUE VALUES
  (1, '356938035643809', 'Queclink GV55',    1, TRUE, CURRENT_DATE - 90),
  (2, '490154203237518', 'Teltonika FMB920', 2, TRUE, CURRENT_DATE - 90),
  (3, '354458089483910', 'Queclink GV55',    3, TRUE, CURRENT_DATE - 90)
ON CONFLICT DO NOTHING;

INSERT INTO beacon (id_beacon, uuid_beacon, nombre, id_paciente,
                    latitud_ref, longitud_ref, radio_metros, activo)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'BEACON-P1-UUID-0001', 'Domicilio Elena',    1, 25.6512000, -100.4002000, 8.00, TRUE),
  (2, 'BEACON-P2-UUID-0002', 'Domicilio Héctor',   2, 25.6489000, -100.3978000, 8.00, TRUE),
  (3, 'BEACON-P3-UUID-0003', 'Domicilio Consuelo', 3, 25.6530000, -100.4050000, 8.00, TRUE)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 7: VÍNCULOS Y HORARIOS
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO paciente_cuidador (id_paciente_cuidador, id_paciente, id_cuidador, es_principal, activo)
OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, TRUE,  TRUE),
  (2, 2, 1, TRUE,  TRUE),
  (3, 3, 2, TRUE,  TRUE),
  (4, 1, 3, FALSE, TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO cuidador_horario (id_paciente_cuidador, dia_semana, hora_inicio, hora_fin) VALUES
  (1,'lunes','07:00','15:00'),(1,'martes','07:00','15:00'),(1,'miercoles','07:00','15:00'),
  (1,'jueves','07:00','15:00'),(1,'viernes','07:00','15:00'),(1,'sabado','08:00','13:00'),
  (2,'lunes','15:30','22:00'),(2,'martes','15:30','22:00'),(2,'miercoles','15:30','22:00'),
  (2,'jueves','15:30','22:00'),(2,'viernes','15:30','22:00'),
  (3,'lunes','08:00','20:00'),(3,'martes','08:00','20:00'),(3,'miercoles','08:00','20:00'),
  (3,'jueves','08:00','20:00'),(3,'viernes','08:00','20:00'),
  (3,'sabado','08:00','20:00'),(3,'domingo','08:00','20:00'),
  (4,'sabado','13:00','20:00'),(4,'domingo','08:00','20:00')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 8: USUARIOS (contraseña: Password1!)
-- Columnas reales: id_usuario, email, password_hash, rol_usuario (enum: medico|cuidador),
--                  id_medico, id_cuidador, activo
-- NOTA: No existe rol 'admin' en rol_usuario_enum. El admin se gestiona en .env de Flask.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO usuario (id_usuario, email, password_hash, rol_usuario, id_medico, id_cuidador, activo)
OVERRIDING SYSTEM VALUE VALUES
  (1, 'dr.garza@medinfc.mx',          '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMUHa3dBF5VHp5Y2vJ2lKhzROa', 'medico',   1,    NULL, TRUE),
  (2, 'maria.lopez@medinfc.mx',       '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMUHa3dBF5VHp5Y2vJ2lKhzROa', 'cuidador', NULL, 1,    TRUE),
  (3, 'carlos.ramirez@medinfc.mx',    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMUHa3dBF5VHp5Y2vJ2lKhzROa', 'cuidador', NULL, 2,    TRUE),
  (4, 'patricia.morales@medinfc.mx',  '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMUHa3dBF5VHp5Y2vJ2lKhzROa', 'cuidador', NULL, 3,    TRUE)
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 9: RECETAS — fecha_inicio = hace 30 días
--         El trigger trg_generar_agenda genera agenda_toma automáticamente
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO receta (id_receta, id_paciente, id_medico,
                    fecha_emision, fecha_inicio, fecha_fin, estado_receta)
OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1, CURRENT_DATE - 31, CURRENT_DATE - 30, CURRENT_DATE + 60, 'vigente'),
  (2, 2, 1, CURRENT_DATE - 31, CURRENT_DATE - 30, CURRENT_DATE + 60, 'vigente'),
  (3, 3, 1, CURRENT_DATE - 31, CURRENT_DATE - 30, CURRENT_DATE + 60, 'vigente')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 10: RECETA_MEDICAMENTO
--          Al insertar cada fila, el trigger genera toda la agenda_toma
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO receta_medicamento
    (id_receta_medicamento, id_receta, id_medicamento,
     dosis_prescrita, frecuencia_horas, tolerancia_min, hora_primera_toma, id_unidad)
OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 1,  500, 12, 30, '08:00:00', 1),   -- Metformina  Elena    08:00 y 20:00
  (2, 1, 2,   50, 24, 30, '20:00:00', 1),   -- Losartán    Elena    20:00
  (3, 2, 3,  125, 24, 20, '09:00:00', 3),   -- Digoxina    Héctor   09:00
  (4, 3, 4,    6, 12, 30, '07:30:00', 1),   -- Rivastigmina Consuelo 07:30 y 19:30
  (5, 3, 5, 1000, 24, 60, '13:00:00', 1)    -- Calcio      Consuelo 13:00
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 11: ETIQUETAS NFC
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO etiqueta_nfc (uid_nfc, nombre, tipo_etiqueta, id_receta_medicamento, estado_etiqueta) VALUES
  ('NFC-RM-001', 'Etiqueta Metformina Elena',     'NTAG215', 1, 'activo'),
  ('NFC-RM-002', 'Etiqueta Losartán Elena',        'NTAG215', 2, 'activo'),
  ('NFC-RM-003', 'Etiqueta Digoxina Héctor',       'NTAG215', 3, 'activo'),
  ('NFC-RM-004', 'Etiqueta Rivastigmina Consuelo', 'NTAG215', 4, 'activo'),
  ('NFC-RM-005', 'Etiqueta Calcio Consuelo',       'NTAG215', 5, 'activo')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 12: UBICACIONES GPS
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO ubicacion_gps (id_ubicacion, id_gps, latitud, longitud,
                            precision_metros, timestamp_ubicacion, en_domicilio_paciente)
OVERRIDING SYSTEM VALUE VALUES
  (1, 1, 25.6512050, -100.4002100, 3.50, NOW() - INTERVAL '2 hours',    TRUE),
  (2, 2, 25.6530200, -100.4050300, 4.00, NOW() - INTERVAL '1 hour',     TRUE),
  (3, 3, 25.6601000, -100.4120000, 6.00, NOW() - INTERVAL '30 minutes', FALSE)
ON CONFLICT DO NOTHING;



-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 14: EVENTOS NFC HISTÓRICOS
--
-- Función auxiliar para marcar una agenda como cumplida/tardía:
--   UPDATE agenda_toma SET estado_agenda = 'X'
--   WHERE id_agenda = (SELECT id_agenda FROM agenda_toma
--                      WHERE id_receta_medicamento = N
--                        AND fecha_hora_programada = 'FECHA HORA EXACTA'
--                      LIMIT 1);
--
-- Horas exactas programadas:
--   RM1: 08:00 y 20:00   RM2: 20:00   RM3: 09:00   RM4: 07:30 y 19:30   RM5: 13:00
-- ─────────────────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════
-- ELENA (P1) — Metformina RM1 (c/12h) + Losartán RM2 (c/24h)
-- Patrón: ~80% adherencia, buenas rachas con omisiones fin de semana
-- ═══════════════════════════════════════════════════

-- DÍA -30
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-30)::TIMESTAMP+'08:05'::TIME, 1, 1,'nfc','Toma matutina',(CURRENT_DATE-30)::TIMESTAMP+'08:05'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-30)::TIMESTAMP+'20:04'::TIME, 1, 1,'nfc','Losartán noche',(CURRENT_DATE-30)::TIMESTAMP+'20:04'::TIME);

-- DÍA -29
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-29)::TIMESTAMP+'08:03'::TIME, 1, 1,'nfc','Toma correcta',(CURRENT_DATE-29)::TIMESTAMP+'08:03'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-29)::TIMESTAMP+'20:02'::TIME, 1, 1,'nfc','Toma nocturna',(CURRENT_DATE-29)::TIMESTAMP+'20:02'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-29)::TIMESTAMP+'20:06'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-29)::TIMESTAMP+'20:06'::TIME);

-- DÍA -28
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-28)::TIMESTAMP+'08:31'::TIME, 1, 1,'nfc','Tardía 31min',(CURRENT_DATE-28)::TIMESTAMP+'08:31'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-28)::TIMESTAMP+'20:08'::TIME, 1, 1,'nfc','Nocturna ok',(CURRENT_DATE-28)::TIMESTAMP+'20:08'::TIME);

-- DÍA -27: omitida mañana, cumplida noche
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-27)::TIMESTAMP+'20:03'::TIME, 1, 1,'nfc','Nocturna ok',(CURRENT_DATE-27)::TIMESTAMP+'20:03'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-27)::TIMESTAMP+'20:05'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-27)::TIMESTAMP+'20:05'::TIME);

-- DÍA -26: fin de semana Patricia cubre
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-26)::TIMESTAMP+'08:10'::TIME, 1, 3,'nfc','Patricia fds',(CURRENT_DATE-26)::TIMESTAMP+'08:10'::TIME);

-- DÍA -25: fin de semana — omitida (ya queda así del paso 13)

-- DÍA -24
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-24)::TIMESTAMP+'08:02'::TIME, 1, 1,'nfc','Lunes puntual',(CURRENT_DATE-24)::TIMESTAMP+'08:02'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-24)::TIMESTAMP+'20:05'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-24)::TIMESTAMP+'20:05'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-24)::TIMESTAMP+'20:07'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-24)::TIMESTAMP+'20:07'::TIME);

-- DÍA -23
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-23)::TIMESTAMP+'08:07'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-23)::TIMESTAMP+'08:07'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-23)::TIMESTAMP+'20:03'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-23)::TIMESTAMP+'20:03'::TIME);

-- DÍA -22: tardía mañana
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-22)::TIMESTAMP+'08:31'::TIME, 1, 1,'nfc','Tardía 31min',(CURRENT_DATE-22)::TIMESTAMP+'08:31'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-22)::TIMESTAMP+'20:04'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-22)::TIMESTAMP+'20:04'::TIME);

-- DÍA -21
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-21)::TIMESTAMP+'08:01'::TIME, 1, 1,'nfc','Puntual',(CURRENT_DATE-21)::TIMESTAMP+'08:01'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-21)::TIMESTAMP+'20:09'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-21)::TIMESTAMP+'20:09'::TIME);

-- DÍA -20
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-20)::TIMESTAMP+'08:04'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-20)::TIMESTAMP+'08:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-20)::TIMESTAMP+'20:06'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-20)::TIMESTAMP+'20:06'::TIME);

-- DÍA -19: fin de semana Patricia
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-19)::TIMESTAMP+'08:15'::TIME, 1, 3,'nfc','Patricia fds',(CURRENT_DATE-19)::TIMESTAMP+'08:15'::TIME);

-- DÍA -18: fin de semana omitida

-- DÍA -17
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-17)::TIMESTAMP+'08:02'::TIME, 1, 1,'nfc','Lunes ok',(CURRENT_DATE-17)::TIMESTAMP+'08:02'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-17)::TIMESTAMP+'20:04'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-17)::TIMESTAMP+'20:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-17)::TIMESTAMP+'20:08'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-17)::TIMESTAMP+'20:08'::TIME);

-- DÍA -16
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-16)::TIMESTAMP+'08:06'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-16)::TIMESTAMP+'08:06'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-16)::TIMESTAMP+'20:02'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-16)::TIMESTAMP+'20:02'::TIME);

-- DÍA -15: tardía
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-15)::TIMESTAMP+'08:31'::TIME, 1, 1,'nfc','Tardía 31min',(CURRENT_DATE-15)::TIMESTAMP+'08:31'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-15)::TIMESTAMP+'20:03'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-15)::TIMESTAMP+'20:03'::TIME);

-- DÍA -14
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-14)::TIMESTAMP+'08:01'::TIME, 1, 1,'nfc','Puntual',(CURRENT_DATE-14)::TIMESTAMP+'08:01'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-14)::TIMESTAMP+'20:05'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-14)::TIMESTAMP+'20:05'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-14)::TIMESTAMP+'20:07'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-14)::TIMESTAMP+'20:07'::TIME);

-- DÍA -13
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-13)::TIMESTAMP+'08:03'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-13)::TIMESTAMP+'08:03'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-13)::TIMESTAMP+'20:01'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-13)::TIMESTAMP+'20:01'::TIME);

-- DÍA -12: fin de semana omitida
-- DÍA -11: fin de semana Patricia
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-11)::TIMESTAMP+'08:20'::TIME, 1, 3,'nfc','Patricia domingo',(CURRENT_DATE-11)::TIMESTAMP+'08:20'::TIME);

-- DÍA -10
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-10)::TIMESTAMP+'08:04'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-10)::TIMESTAMP+'08:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-10)::TIMESTAMP+'20:06'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-10)::TIMESTAMP+'20:06'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-10)::TIMESTAMP+'20:09'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-10)::TIMESTAMP+'20:09'::TIME);

-- DÍA -9
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-9)::TIMESTAMP+'08:02'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-9)::TIMESTAMP+'08:02'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-9)::TIMESTAMP+'20:03'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-9)::TIMESTAMP+'20:03'::TIME);

-- DÍA -8: tardía
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-8)::TIMESTAMP+'08:31'::TIME, 1, 1,'nfc','Tardía 31min',(CURRENT_DATE-8)::TIMESTAMP+'08:31'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-8)::TIMESTAMP+'20:04'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-8)::TIMESTAMP+'20:04'::TIME);

-- DÍA -7
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-7)::TIMESTAMP+'08:03'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-7)::TIMESTAMP+'08:03'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-7)::TIMESTAMP+'20:05'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-7)::TIMESTAMP+'20:05'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-7)::TIMESTAMP+'20:07'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-7)::TIMESTAMP+'20:07'::TIME);

-- DÍA -6
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-6)::TIMESTAMP+'08:01'::TIME, 1, 1,'nfc','Puntual',(CURRENT_DATE-6)::TIMESTAMP+'08:01'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-6)::TIMESTAMP+'20:02'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-6)::TIMESTAMP+'20:02'::TIME);

-- DÍA -5
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-5)::TIMESTAMP+'08:04'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-5)::TIMESTAMP+'08:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-5)::TIMESTAMP+'20:06'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-5)::TIMESTAMP+'20:06'::TIME);

-- DÍA -4
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-4)::TIMESTAMP+'08:03'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-4)::TIMESTAMP+'08:03'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-4)::TIMESTAMP+'20:04'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-4)::TIMESTAMP+'20:04'::TIME);

-- DÍA -3
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-3)::TIMESTAMP+'08:06'::TIME, 1, 1,'nfc','Toma ok',(CURRENT_DATE-3)::TIMESTAMP+'08:06'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-3)::TIMESTAMP+'20:05'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-3)::TIMESTAMP+'20:05'::TIME);

-- DÍA -2: tardía
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-2)::TIMESTAMP+'08:31'::TIME, 1, 1,'nfc','Tardía 31min',(CURRENT_DATE-2)::TIMESTAMP+'08:31'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-2)::TIMESTAMP+'20:03'::TIME, 1, 1,'nfc','Nocturna ok',(CURRENT_DATE-2)::TIMESTAMP+'20:03'::TIME);

-- DÍA -1
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-1)::TIMESTAMP+'08:02'::TIME, 1, 1,'nfc','Puntual',(CURRENT_DATE-1)::TIMESTAMP+'08:02'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(1,'NFC-RM-001', (CURRENT_DATE-1)::TIMESTAMP+'20:04'::TIME, 1, 1,'nfc','Nocturna',(CURRENT_DATE-1)::TIMESTAMP+'20:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(2,'NFC-RM-002', (CURRENT_DATE-1)::TIMESTAMP+'20:06'::TIME, 1, 1,'nfc','Losartán',(CURRENT_DATE-1)::TIMESTAMP+'20:06'::TIME);

-- ═══════════════════════════════════════════════════
-- HÉCTOR (P2) — Digoxina RM3 (c/24h → 09:00)
-- Patrón: irregular ~55%, declive últimos 7 días
-- ═══════════════════════════════════════════════════

-- Días -30 a -22: relativamente bueno (7 de 9)
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-30)::TIMESTAMP+'09:04'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-30)::TIMESTAMP+'09:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-29)::TIMESTAMP+'09:02'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-29)::TIMESTAMP+'09:02'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-28)::TIMESTAMP+'09:07'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-28)::TIMESTAMP+'09:07'::TIME);

-- DÍA -27: omitida (fin de semana sin María)
-- DÍA -26: omitida (fin de semana)

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-25)::TIMESTAMP+'09:21'::TIME, 1, 1,'nfc','Tardía 21min',(CURRENT_DATE-25)::TIMESTAMP+'09:21'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-24)::TIMESTAMP+'09:03'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-24)::TIMESTAMP+'09:03'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-23)::TIMESTAMP+'09:05'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-23)::TIMESTAMP+'09:05'::TIME);

-- DÍA -22: omitida
-- Días -21 a -15: 4 de 7
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-21)::TIMESTAMP+'09:06'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-21)::TIMESTAMP+'09:06'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-20)::TIMESTAMP+'09:04'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-20)::TIMESTAMP+'09:04'::TIME);

-- DÍA -19, -18, -17: omitidas

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-16)::TIMESTAMP+'09:08'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-16)::TIMESTAMP+'09:08'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-15)::TIMESTAMP+'09:03'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-15)::TIMESTAMP+'09:03'::TIME);

-- Días -14 a -8: solo 2 de 7 (empieza a declinar)
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-13)::TIMESTAMP+'09:05'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-13)::TIMESTAMP+'09:05'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-10)::TIMESTAMP+'09:21'::TIME, 1, 1,'nfc','Tardía 21min',(CURRENT_DATE-10)::TIMESTAMP+'09:21'::TIME);

-- Últimos 7 días Héctor: solo 1 toma (racha omisión CRÍTICA)
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(3,'NFC-RM-003', (CURRENT_DATE-5)::TIMESTAMP+'09:06'::TIME, 1, 1,'nfc','Digoxina ok',(CURRENT_DATE-5)::TIMESTAMP+'09:06'::TIME);

-- ═══════════════════════════════════════════════════
-- CONSUELO (P3) — Rivastigmina RM4 (c/12h → 07:30 y 19:30) + Calcio RM5 (c/24h → 13:00)
-- Patrón: buena primeros 20 días, declive pronunciado últimos 10
-- ═══════════════════════════════════════════════════

-- Días -30 a -21: buena adherencia ~85%
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-30)::TIMESTAMP+'07:33'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-30)::TIMESTAMP+'07:33'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-30)::TIMESTAMP+'13:04'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-30)::TIMESTAMP+'13:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-30)::TIMESTAMP+'19:32'::TIME, 1, 2,'nfc','Rivastigmina noche',(CURRENT_DATE-30)::TIMESTAMP+'19:32'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-29)::TIMESTAMP+'07:31'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-29)::TIMESTAMP+'07:31'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-29)::TIMESTAMP+'13:02'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-29)::TIMESTAMP+'13:02'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-29)::TIMESTAMP+'19:34'::TIME, 1, 2,'nfc','Rivastigmina noche',(CURRENT_DATE-29)::TIMESTAMP+'19:34'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-28)::TIMESTAMP+'07:35'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-28)::TIMESTAMP+'07:35'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-28)::TIMESTAMP+'13:05'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-28)::TIMESTAMP+'13:05'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-27)::TIMESTAMP+'07:32'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-27)::TIMESTAMP+'07:32'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-27)::TIMESTAMP+'19:33'::TIME, 1, 2,'nfc','Rivastigmina noche',(CURRENT_DATE-27)::TIMESTAMP+'19:33'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-26)::TIMESTAMP+'07:36'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-26)::TIMESTAMP+'07:36'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-26)::TIMESTAMP+'13:03'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-26)::TIMESTAMP+'13:03'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-25)::TIMESTAMP+'07:34'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-25)::TIMESTAMP+'07:34'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-25)::TIMESTAMP+'19:35'::TIME, 1, 2,'nfc','Rivastigmina noche',(CURRENT_DATE-25)::TIMESTAMP+'19:35'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-24)::TIMESTAMP+'07:38'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-24)::TIMESTAMP+'07:38'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-24)::TIMESTAMP+'13:06'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-24)::TIMESTAMP+'13:06'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-23)::TIMESTAMP+'07:30'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-23)::TIMESTAMP+'07:30'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-23)::TIMESTAMP+'19:31'::TIME, 1, 2,'nfc','Rivastigmina noche',(CURRENT_DATE-23)::TIMESTAMP+'19:31'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-22)::TIMESTAMP+'07:37'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-22)::TIMESTAMP+'07:37'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-22)::TIMESTAMP+'13:04'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-22)::TIMESTAMP+'13:04'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-21)::TIMESTAMP+'07:33'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-21)::TIMESTAMP+'07:33'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-21)::TIMESTAMP+'19:36'::TIME, 1, 2,'nfc','Rivastigmina noche',(CURRENT_DATE-21)::TIMESTAMP+'19:36'::TIME);

-- Días -20 a -11: declive progresivo Consuelo (Carlos empieza a fallar)
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-20)::TIMESTAMP+'07:40'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-20)::TIMESTAMP+'07:40'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-20)::TIMESTAMP+'13:07'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-20)::TIMESTAMP+'13:07'::TIME);

-- DÍA -19: tardía (Carlos llega tarde)
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-19)::TIMESTAMP+'08:01'::TIME, 1, 2,'nfc','Tardía Carlos',(CURRENT_DATE-19)::TIMESTAMP+'08:01'::TIME);

-- DÍA -18: cumplida
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-18)::TIMESTAMP+'07:35'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-18)::TIMESTAMP+'07:35'::TIME);

-- Días -17 a -11: solo 2 de 7 (declive fuerte)
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-15)::TIMESTAMP+'07:38'::TIME, 1, 2,'nfc','Rivastigmina',(CURRENT_DATE-15)::TIMESTAMP+'07:38'::TIME);

INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(5,'NFC-RM-005', (CURRENT_DATE-13)::TIMESTAMP+'13:05'::TIME, 1, 2,'nfc','Calcio',(CURRENT_DATE-13)::TIMESTAMP+'13:05'::TIME);

-- Últimos 10 días Consuelo: racha crítica, solo 1 toma
INSERT INTO evento_nfc (id_receta_medicamento, uid_nfc, timestamp_lectura, id_resultado, id_cuidador_lector, origen, observaciones, fecha_registro) VALUES
(4,'NFC-RM-004', (CURRENT_DATE-8)::TIMESTAMP+'08:01'::TIME, 1, 2,'nfc','Tardía Carlos llegó tarde',(CURRENT_DATE-8)::TIMESTAMP+'08:01'::TIME);

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 13: MARCAR AGENDAS PASADAS SIN EVENTO COMO OMITIDAS
--          Se ejecuta DESPUÉS de los eventos para no interferir con el trigger
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE agenda_toma
SET    estado_agenda = 'omitida'
WHERE  estado_agenda = 'pendiente'
  AND  fecha_hora_programada < CURRENT_DATE;

-- ─────────────────────────────────────────────────────────────────────────────
-- PASO 15: SINCRONIZAR SEQUENCES
-- ─────────────────────────────────────────────────────────────────────────────
SELECT setval(pg_get_serial_sequence('diagnostico',        'id_diagnostico'),        (SELECT MAX(id_diagnostico)        FROM diagnostico),        TRUE);
SELECT setval(pg_get_serial_sequence('especialidad',       'id_especialidad'),       (SELECT MAX(id_especialidad)       FROM especialidad),       TRUE);
SELECT setval(pg_get_serial_sequence('via_administracion', 'id_via'),                (SELECT MAX(id_via)                FROM via_administracion), TRUE);
SELECT setval(pg_get_serial_sequence('unidad_dosis',       'id_unidad'),             (SELECT MAX(id_unidad)             FROM unidad_dosis),       TRUE);
SELECT setval(pg_get_serial_sequence('medicamento',        'id_medicamento'),        (SELECT MAX(id_medicamento)        FROM medicamento),        TRUE);
SELECT setval(pg_get_serial_sequence('medico',             'id_medico'),             (SELECT MAX(id_medico)             FROM medico),             TRUE);
SELECT setval(pg_get_serial_sequence('cuidador',           'id_cuidador'),           (SELECT MAX(id_cuidador)           FROM cuidador),           TRUE);
SELECT setval(pg_get_serial_sequence('paciente',           'id_paciente'),           (SELECT MAX(id_paciente)           FROM paciente),           TRUE);
SELECT setval(pg_get_serial_sequence('gps_imei',           'id_gps'),                (SELECT MAX(id_gps)                FROM gps_imei),           TRUE);
SELECT setval(pg_get_serial_sequence('beacon',             'id_beacon'),             (SELECT MAX(id_beacon)             FROM beacon),             TRUE);
SELECT setval(pg_get_serial_sequence('paciente_cuidador',  'id_paciente_cuidador'),  (SELECT MAX(id_paciente_cuidador)  FROM paciente_cuidador),  TRUE);
SELECT setval(pg_get_serial_sequence('receta',             'id_receta'),             (SELECT MAX(id_receta)             FROM receta),             TRUE);
SELECT setval(pg_get_serial_sequence('receta_medicamento', 'id_receta_medicamento'), (SELECT MAX(id_receta_medicamento) FROM receta_medicamento), TRUE);
SELECT setval(pg_get_serial_sequence('ubicacion_gps',      'id_ubicacion'),          (SELECT MAX(id_ubicacion)          FROM ubicacion_gps),      TRUE);
SELECT setval(pg_get_serial_sequence('usuario',            'id_usuario'),            (SELECT MAX(id_usuario)            FROM usuario),            TRUE);
SELECT setval(pg_get_serial_sequence('evento_nfc',         'id_evento'),             (SELECT MAX(id_evento)             FROM evento_nfc),         TRUE);

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFICACIÓN
-- ─────────────────────────────────────────────────────────────────────────────
/*
SELECT estado_agenda, COUNT(*) FROM agenda_toma
WHERE fecha_hora_programada::DATE < CURRENT_DATE
GROUP BY estado_agenda ORDER BY estado_agenda;

-- Esperado aprox:
--   cumplida  ~65
--   tardia    ~10
--   omitida   ~resto (~85)

SELECT id_paciente, fecha, total, correctas, fuera_horario, no_tomadas
FROM v_grafica_tomas
WHERE fecha BETWEEN CURRENT_DATE-30 AND CURRENT_DATE
ORDER BY id_paciente, fecha LIMIT 20;
*/