// Esquema MongoDB exportado: medinfc_mongo
// Generado: 2026-05-11T23:38:00.239Z


// ─── Colección: alertas_rt ───
db.createCollection("alertas_rt");
db.alertas_rt.createIndex({"pg_id_alerta":1}, {"unique":true,"name":"pg_id_alerta_1"});
db.alertas_rt.createIndex({"pg_id_paciente":1,"estado":1}, { name: "pg_id_paciente_1_estado_1" });

// ─── Colección: eventos_nfc_rt ───
db.createCollection("eventos_nfc_rt");
db.eventos_nfc_rt.createIndex({"pg_id_evento":1}, {"unique":true,"name":"pg_id_evento_1"});
db.eventos_nfc_rt.createIndex({"pg_id_cuidador":1,"ts":-1}, { name: "pg_id_cuidador_1_ts_-1" });

// ─── Colección: historial_gps ───
db.createCollection("historial_gps");
db.historial_gps.createIndex({"imei":1,"ts":-1}, { name: "imei_1_ts_-1" });

// ─── Colección: historico_adherencia ───
db.createCollection("historico_adherencia");
db.historico_adherencia.createIndex({"pg_id_paciente":1,"fecha":-1}, { name: "pg_id_paciente_1_fecha_-1" });

// ─── Colección: logs_acceso ───
db.createCollection("logs_acceso");
db.logs_acceso.createIndex({"ts":1}, {"expireAfterSeconds":7776000,"name":"ts_1"});

// ─── Colección: logs_nfc_fallidos ───
db.createCollection("logs_nfc_fallidos");
db.logs_nfc_fallidos.createIndex({"ts":1}, { name: "ts_1" });

// ─── Colección: logs_sistema ───
db.createCollection("logs_sistema");
db.logs_sistema.createIndex({"ts":1}, {"expireAfterSeconds":2592000,"name":"ts_1"});

// ─── Colección: perfil_clinico_paciente ───
db.createCollection("perfil_clinico_paciente");
db.perfil_clinico_paciente.createIndex({"pg_id_paciente":1}, {"unique":true,"name":"pg_id_paciente_1"});
db.perfil_clinico_paciente.createIndex({"pg_id_medico":1}, { name: "pg_id_medico_1" });
db.perfil_clinico_paciente.createIndex({"actualizado_en":-1}, { name: "actualizado_en_-1" });

// ─── Colección: ubicaciones_gps_hist ───
db.createCollection("ubicaciones_gps_hist");
db.ubicaciones_gps_hist.createIndex({"pg_id_cuidador":1,"ts":-1}, { name: "pg_id_cuidador_1_ts_-1" });
db.ubicaciones_gps_hist.createIndex({"pg_id_paciente":1,"ts":-1}, { name: "pg_id_paciente_1_ts_-1" });

