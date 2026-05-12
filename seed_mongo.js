// =============================================================================
// MEDI_NFC — SEED MONGODB v1
// -----------------------------------------------------------------------------
// Uso:
//   mongosh medinfc_mongo seed_mongo.js
//
// Alineado con seed_test_data.sql:
//   • Pacientes:  1=Elena, 2=Héctor, 3=Consuelo
//   • Médico:     1=Dr. Garza
//   • Cuidadores: 1=María, 2=Carlos, 3=Patricia
//   • Recetas-Med: 1=Metformina/Elena, 2=Losartán/Elena,
//                  3=Digoxina/Héctor, 4=Rivastigmina/Consuelo, 5=Calcio/Consuelo
//
// Patrón de adherencia:
//   Elena    → ~80%, tendencia MEJORA en últimos 7 días
//   Héctor   → ~55%, DECLIVE marcado en últimos 7 días
//   Consuelo → comienza bien y cae a partir del día -10
//
// Colecciones que se poblan:
//   • historico_adherencia, eventos_nfc_rt, alertas_rt
//   • ubicaciones_gps_hist, historial_gps
//   • logs_acceso, logs_sistema, logs_nfc_fallidos
// =============================================================================

print("🔄 Conectado a base: " + db.getName());

// ─────────────────────────────────────────────────────────────────────────────
// 0. LIMPIAR COLECCIONES
// ─────────────────────────────────────────────────────────────────────────────
const COLLECTIONS = [
  "historico_adherencia",
  "eventos_nfc_rt",
  "alertas_rt",
  "ubicaciones_gps_hist",
  "historial_gps",
  "logs_acceso",
  "logs_sistema",
  "logs_nfc_fallidos"
];
COLLECTIONS.forEach(c => {
  db[c].drop();
  print("  🗑️  drop " + c);
});

// ─────────────────────────────────────────────────────────────────────────────
// 1. ÍNDICES TTL Y BÚSQUEDA
// ─────────────────────────────────────────────────────────────────────────────
db.logs_acceso.createIndex({ ts: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 90 }); // 90 días
db.logs_sistema.createIndex({ ts: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 30 }); // 30 días
db.logs_nfc_fallidos.createIndex({ ts: 1 });
db.historico_adherencia.createIndex({ pg_id_paciente: 1, fecha: -1 });
db.eventos_nfc_rt.createIndex({ pg_id_evento: 1 }, { unique: true });
db.eventos_nfc_rt.createIndex({ pg_id_cuidador: 1, ts: -1 });
db.alertas_rt.createIndex({ pg_id_alerta: 1 }, { unique: true });
db.alertas_rt.createIndex({ pg_id_paciente: 1, estado: 1 });
db.ubicaciones_gps_hist.createIndex({ pg_id_cuidador: 1, ts: -1 });
db.ubicaciones_gps_hist.createIndex({ pg_id_paciente: 1, ts: -1 });
db.historial_gps.createIndex({ imei: 1, ts: -1 });
print("✅ Índices creados (TTL en logs_acceso=90d, logs_sistema=30d)");

// ─────────────────────────────────────────────────────────────────────────────
// 2. HELPERS
// ─────────────────────────────────────────────────────────────────────────────
function daysAgo(n, h = 0, m = 0) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  d.setHours(h, m, 0, 0);
  return d;
}
function rand(min, max) {
  return Math.random() * (max - min) + min;
}
function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Coordenadas base de cada domicilio (idénticas a beacon en SQL)
const HOMES = {
  1: { lat: 25.6512, lon: -100.4002, paciente: "Elena Martínez" },   // Elena
  2: { lat: 25.6489, lon: -100.3978, paciente: "Héctor González" },  // Héctor
  3: { lat: 25.6530, lon: -100.4050, paciente: "Consuelo Vázquez" }  // Consuelo
};

const CUIDADORES = {
  1: { nombre: "María López",   imei: "356938035643809" },
  2: { nombre: "Carlos Ramírez", imei: "490154203237518" },
  3: { nombre: "Patricia Morales", imei: "354458089483910" }
};

// Asignación cuidador principal → paciente (de paciente_cuidador SQL)
const CUIDADOR_DE = { 1: 1, 2: 1, 3: 2 };  // Elena→María, Héctor→María, Consuelo→Carlos

// Cerca del domicilio: pequeñas variaciones aleatorias (±20 m aprox.)
function nearHome(idPac, jitter = 0.0002) {
  const h = HOMES[idPac];
  return {
    lat: +(h.lat + rand(-jitter, jitter)).toFixed(7),
    lon: +(h.lon + rand(-jitter, jitter)).toFixed(7)
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. HISTORICO_ADHERENCIA — 30 días × 3 pacientes = 90 documentos
//    Patrón:
//      Elena    → base ~80%, MEJORA últimos 7d (+5..10%)
//      Héctor   → base ~55%, DECLIVE últimos 7d (-15%)
//      Consuelo → 90% día -30, baja a 30% día 0
// ─────────────────────────────────────────────────────────────────────────────
print("📊 Poblando historico_adherencia...");

const adherenciaDocs = [];
const med_de = {
  1: [{ rm: 1, med: "Metformina", dosis: "500 mg" }, { rm: 2, med: "Losartán", dosis: "50 mg" }],
  2: [{ rm: 3, med: "Digoxina", dosis: "125 mcg" }],
  3: [{ rm: 4, med: "Rivastigmina", dosis: "6 mg" }, { rm: 5, med: "Calcio + Vit D", dosis: "1000 mg" }]
};

for (let dia = 30; dia >= 0; dia--) {
  const fecha = daysAgo(dia);
  fecha.setHours(0, 0, 0, 0);

  for (const idPac of [1, 2, 3]) {
    let base, programadas, cumplidas, tardias, omitidas;

    if (idPac === 1) {
      // Elena: 3 tomas/día (Metformina x2 + Losartán x1)
      programadas = 3;
      const adhBase = 0.80;
      const bonus = dia <= 7 ? (8 - dia) * 0.015 : 0;  // MEJORA reciente
      base = Math.min(0.95, adhBase + bonus);
    } else if (idPac === 2) {
      // Héctor: 1 toma/día (Digoxina)
      programadas = 1;
      const adhBase = 0.65;
      const penal = dia <= 7 ? (8 - dia) * 0.05 : 0;  // DECLIVE reciente
      base = Math.max(0.10, adhBase - penal);
    } else {
      // Consuelo: 3 tomas/día (Rivastigmina x2 + Calcio x1)
      programadas = 3;
      if (dia >= 11) {
        base = 0.85 - rand(0, 0.05);  // bien antes del día -10
      } else {
        base = Math.max(0.20, 0.85 - (11 - dia) * 0.06);  // caída sostenida
      }
    }

    const ratio = Math.max(0, Math.min(1, base + rand(-0.05, 0.05)));
    cumplidas = Math.round(programadas * ratio);
    if (cumplidas > programadas) cumplidas = programadas;
    const restantes = programadas - cumplidas;
    tardias = restantes > 0 && Math.random() < 0.35 ? 1 : 0;
    if (tardias > restantes) tardias = restantes;
    omitidas = restantes - tardias;

    const pct = programadas === 0
      ? 0
      : +(((cumplidas + tardias * 0.5) / programadas) * 100).toFixed(2);

    adherenciaDocs.push({
      pg_id_paciente: idPac,
      pg_id_medico: 1,
      paciente: HOMES[idPac].paciente,
      fecha: fecha,
      metricas: {
        programadas: programadas,
        cumplidas: cumplidas,
        tardias: tardias,
        omitidas: omitidas,
        pct_adherencia: pct
      },
      detalle_medicamentos: med_de[idPac].map(m => ({
        id_receta_medicamento: m.rm,
        medicamento: m.med,
        dosis: m.dosis
      })),
      generado_en: new Date()
    });
  }
}
db.historico_adherencia.insertMany(adherenciaDocs);
print("  ✅ " + adherenciaDocs.length + " documentos en historico_adherencia");

// ─────────────────────────────────────────────────────────────────────────────
// 4. EVENTOS_NFC_RT — espejo desnormalizado de eventos NFC
//    Generamos un patrón que coincide en tomas totales con el seed SQL
// ─────────────────────────────────────────────────────────────────────────────
print("📡 Poblando eventos_nfc_rt...");

const eventosNfcDocs = [];
const UID_DE_RM = { 1: "NFC-RM-001", 2: "NFC-RM-002", 3: "NFC-RM-003", 4: "NFC-RM-004", 5: "NFC-RM-005" };
const MEDICAMENTO_DE_RM = {
  1: "Metformina",
  2: "Losartán",
  3: "Digoxina",
  4: "Rivastigmina",
  5: "Calcio + Vit D"
};
const PACIENTE_DE_RM = { 1: 1, 2: 1, 3: 2, 4: 3, 5: 3 };
const HORAS_DE_RM = {
  1: [8, 20],
  2: [20],
  3: [9],
  4: [7.5, 19.5],
  5: [13]
};

let evCounter = 1;

function genEventos(idPac, rmList, dia, adhBase) {
  for (const rm of rmList) {
    const horas = HORAS_DE_RM[rm];
    for (const h of horas) {
      const hh = Math.floor(h);
      const mm = Math.round((h - hh) * 60);
      const programada = daysAgo(dia, hh, mm);
      const dado = Math.random() < adhBase;
      if (!dado) continue;  // omitido

      // Determinar si es tardío
      const tardio = Math.random() < 0.18;
      const offsetMin = tardio ? randInt(31, 75) : randInt(-5, 15);
      const ts = new Date(programada.getTime() + offsetMin * 60 * 1000);

      const idCuid = CUIDADOR_DE[idPac];
      const proxValida = Math.random() < 0.85;

      eventosNfcDocs.push({
        pg_id_evento: evCounter++,
        pg_id_paciente: idPac,
        pg_id_medico: 1,
        pg_id_cuidador: idCuid,
        pg_id_receta_medicamento: rm,
        paciente: HOMES[idPac].paciente,
        cuidador: CUIDADORES[idCuid].nombre,
        medicamento: MEDICAMENTO_DE_RM[rm],
        uid_nfc: UID_DE_RM[rm],
        ts: ts,
        ts_programado: programada,
        desfase_min: offsetMin,
        resultado: tardio ? "Tardío" : "Exitoso",
        origen: "nfc",
        proximidad_valida: proxValida,
        distancia_metros: proxValida ? +rand(0.5, 7.5).toFixed(2) : +rand(50, 200).toFixed(2)
      });
    }
  }
}

for (let dia = 30; dia >= 0; dia--) {
  // Elena
  let adh = 0.80;
  if (dia <= 7) adh = Math.min(0.95, 0.80 + (8 - dia) * 0.015);
  genEventos(1, [1, 2], dia, adh);

  // Héctor
  adh = 0.65;
  if (dia <= 7) adh = Math.max(0.10, 0.65 - (8 - dia) * 0.05);
  genEventos(2, [3], dia, adh);

  // Consuelo
  adh = dia >= 11 ? 0.85 : Math.max(0.20, 0.85 - (11 - dia) * 0.06);
  genEventos(3, [4, 5], dia, adh);
}

if (eventosNfcDocs.length > 0) {
  db.eventos_nfc_rt.insertMany(eventosNfcDocs);
}
print("  ✅ " + eventosNfcDocs.length + " documentos en eventos_nfc_rt");

// ─────────────────────────────────────────────────────────────────────────────
// 5. ALERTAS_RT — alertas activas para el badge del menú
//    Tipos: 1=Toma Tardía, 2=Dosis Duplicada, 3=Omisión Medicamento, 4=Proximidad Inválida
// ─────────────────────────────────────────────────────────────────────────────
print("🚨 Poblando alertas_rt...");

const alertasDocs = [];
let alertaCounter = 1;

// Alertas para Elena (pocas, mayoría atendidas, una pendiente reciente)
alertasDocs.push({
  pg_id_alerta: alertaCounter++,
  pg_id_paciente: 1,
  pg_id_medico: 1,
  pg_id_cuidador: 1,
  pg_id_receta_medicamento: 1,
  paciente: "Elena Martínez",
  medicamento: "Metformina",
  tipo_alerta: "Toma Tardía",
  id_tipo_alerta: 1,
  prioridad: "Media",
  estado: "Pendiente",
  ts: daysAgo(1, 8, 31),
  detalle: "Toma con desfase de 31 minutos"
});

// Alertas para Héctor (varias pendientes, escalada de declive)
for (let i = 0; i < 5; i++) {
  alertasDocs.push({
    pg_id_alerta: alertaCounter++,
    pg_id_paciente: 2,
    pg_id_medico: 1,
    pg_id_cuidador: 1,
    pg_id_receta_medicamento: 3,
    paciente: "Héctor González",
    medicamento: "Digoxina",
    tipo_alerta: "Omisión de Medicamento",
    id_tipo_alerta: 3,
    prioridad: "Alta",
    estado: "Pendiente",
    ts: daysAgo(i + 1, 9, 30),
    detalle: "Omisión de dosis programada de digoxina — riesgo cardiovascular"
  });
}
alertasDocs.push({
  pg_id_alerta: alertaCounter++,
  pg_id_paciente: 2,
  pg_id_medico: 1,
  pg_id_cuidador: 1,
  pg_id_receta_medicamento: 3,
  paciente: "Héctor González",
  medicamento: "Digoxina",
  tipo_alerta: "Proximidad Inválida",
  id_tipo_alerta: 4,
  prioridad: "Media",
  estado: "Pendiente",
  ts: daysAgo(2, 9, 15),
  detalle: "GPS del cuidador fuera del radio del beacon (137 m)"
});

// Alertas para Consuelo (muchas pendientes en últimos 10 días)
for (let dia = 0; dia < 10; dia++) {
  if (Math.random() < 0.55) {
    alertasDocs.push({
      pg_id_alerta: alertaCounter++,
      pg_id_paciente: 3,
      pg_id_medico: 1,
      pg_id_cuidador: 2,
      pg_id_receta_medicamento: 4,
      paciente: "Consuelo Vázquez",
      medicamento: "Rivastigmina",
      tipo_alerta: "Omisión de Medicamento",
      id_tipo_alerta: 3,
      prioridad: "Alta",
      estado: dia === 0 ? "Pendiente" : (Math.random() < 0.4 ? "Atendida" : "Pendiente"),
      ts: daysAgo(dia, randInt(7, 19), randInt(0, 59)),
      detalle: "Omisión de rivastigmina — paciente con Alzheimer requiere supervisión"
    });
  }
}

// Alertas antiguas atendidas para llenar historial
for (let dia = 11; dia < 25; dia++) {
  if (Math.random() < 0.25) {
    alertasDocs.push({
      pg_id_alerta: alertaCounter++,
      pg_id_paciente: randInt(1, 3),
      pg_id_medico: 1,
      pg_id_cuidador: randInt(1, 2),
      pg_id_receta_medicamento: randInt(1, 5),
      paciente: ["Elena Martínez", "Héctor González", "Consuelo Vázquez"][randInt(0, 2)],
      medicamento: ["Metformina", "Losartán", "Digoxina", "Rivastigmina", "Calcio + Vit D"][randInt(0, 4)],
      tipo_alerta: "Toma Tardía",
      id_tipo_alerta: 1,
      prioridad: "Baja",
      estado: "Atendida",
      ts: daysAgo(dia, randInt(8, 20), randInt(0, 59)),
      detalle: "Toma fuera de tolerancia, atendida por cuidador"
    });
  }
}

db.alertas_rt.insertMany(alertasDocs);
const pendientes = db.alertas_rt.countDocuments({ estado: "Pendiente" });
print("  ✅ " + alertasDocs.length + " alertas (pendientes: " + pendientes + ")");

// ─────────────────────────────────────────────────────────────────────────────
// 6. HISTORIAL_GPS — pings vía Traccar (protocolo OsmAnd)
//    Para cada cuidador: pings cada 15 min durante 4 días recientes
// ─────────────────────────────────────────────────────────────────────────────
print("📍 Poblando historial_gps (Traccar)...");

const trackerDocs = [];

for (const idCuid of [1, 2, 3]) {
  const cuid = CUIDADORES[idCuid];
  // Pacientes que atiende este cuidador
  const pacientesAtendidos = Object.keys(CUIDADOR_DE)
    .filter(p => CUIDADOR_DE[p] === idCuid)
    .map(p => parseInt(p));
  if (pacientesAtendidos.length === 0) continue;

  for (let dia = 4; dia >= 0; dia--) {
    for (let hora = 7; hora <= 21; hora += 1) {
      for (let min = 0; min < 60; min += 15) {
        const ts = daysAgo(dia, hora, min);
        const idPac = pacientesAtendidos[hora % pacientesAtendidos.length];
        const enDomicilio = Math.random() < 0.65;
        const coords = enDomicilio
          ? nearHome(idPac, 0.0001)
          : nearHome(idPac, 0.005);

        trackerDocs.push({
          imei: cuid.imei,
          pg_id_cuidador: idCuid,
          lat: coords.lat,
          lon: coords.lon,
          precision: +rand(2.5, 8.0).toFixed(2),
          ts: ts,
          en_domicilio: enDomicilio,
          fuente: "traccar"
        });
      }
    }
  }
}

if (trackerDocs.length > 0) {
  db.historial_gps.insertMany(trackerDocs);
}
print("  ✅ " + trackerDocs.length + " pings GPS en historial_gps");

// ─────────────────────────────────────────────────────────────────────────────
// 7. UBICACIONES_GPS_HIST — capturas del navegador (al escanear NFC)
//    Una entrada por cada evento_nfc reciente (últimos 7 días) con coords
// ─────────────────────────────────────────────────────────────────────────────
print("🌐 Poblando ubicaciones_gps_hist (navegador)...");

const ubicNavegadorDocs = [];

eventosNfcDocs.slice(-80).forEach(ev => {
  const idPac = ev.pg_id_paciente;
  const proximo = ev.proximidad_valida;
  const coords = proximo ? nearHome(idPac, 0.0001) : nearHome(idPac, 0.003);
  ubicNavegadorDocs.push({
    pg_id_paciente: idPac,
    pg_id_cuidador: ev.pg_id_cuidador,
    nombre_cuidador: ev.cuidador,
    latitud: coords.lat,
    longitud: coords.lon,
    precision_metros: +rand(3.0, 9.0).toFixed(2),
    en_domicilio: proximo,
    ts: ev.ts,
    fuente: "navegador"
  });
});

if (ubicNavegadorDocs.length > 0) {
  db.ubicaciones_gps_hist.insertMany(ubicNavegadorDocs);
}
print("  ✅ " + ubicNavegadorDocs.length + " ubicaciones del navegador");

// ─────────────────────────────────────────────────────────────────────────────
// 7.5 UBICACIONES_GPS_HIST — pings densos últimas 48h para visualización
//     Estos NO son del navegador sino simulación de tracking continuo.
//     Cada cuidador recibe ~30 pings cada 90min en las últimas 48h,
//     concentrados alrededor del domicilio de su paciente principal.
//     Esto hace que el mapa /doctor/proximidad/historial se vea rico
//     incluso si la ventana es de 6h, 12h, 24h o 48h.
// ─────────────────────────────────────────────────────────────────────────────
print("🛰️  Poblando pings densos (últimas 48h)...");

const ahora48h = new Date();
const pingsDensos = [];

for (const idCuid of [1, 2, 3]) {
  const cuid = CUIDADORES[idCuid];
  const pacientesAtendidos = Object.keys(CUIDADOR_DE)
    .filter(p => CUIDADOR_DE[p] === idCuid)
    .map(p => parseInt(p));
  if (pacientesAtendidos.length === 0) continue;

  // 30 pings cada uno repartidos en últimas 48h
  for (let i = 0; i < 30; i++) {
    // Rota entre pacientes atendidos para que un cuidador con 2 pacientes
    // alterne sus pings entre ambos domicilios
    const idPac = pacientesAtendidos[i % pacientesAtendidos.length];
    const minutosAtras = i * 90 + randInt(0, 30);
    const ts = new Date(ahora48h.getTime() - minutosAtras * 60 * 1000);

    const enDomicilio = Math.random() < 0.75;
    const coords = enDomicilio
      ? nearHome(idPac, 0.0003)
      : nearHome(idPac, 0.0025);

    pingsDensos.push({
      pg_id_paciente: idPac,
      pg_id_cuidador: idCuid,
      nombre_cuidador: cuid.nombre,
      latitud: coords.lat,
      longitud: coords.lon,
      precision_metros: +rand(2.5, 7.5).toFixed(2),
      en_domicilio: enDomicilio,
      ts: ts,
      fuente: "navegador"
    });
  }
}

if (pingsDensos.length > 0) {
  db.ubicaciones_gps_hist.insertMany(pingsDensos);
}
print("  ✅ " + pingsDensos.length + " pings densos en últimas 48h");

// ─────────────────────────────────────────────────────────────────────────────
// 8. LOGS_ACCESO — historial de logins (TTL 90 días)
// ─────────────────────────────────────────────────────────────────────────────
print("🔐 Poblando logs_acceso...");

const usuariosLogin = [
  { id: 1, email: "dr.garza@medinfc.mx",         rol: "medico" },
  { id: 2, email: "maria.lopez@medinfc.mx",       rol: "cuidador" },
  { id: 3, email: "carlos.ramirez@medinfc.mx",    rol: "cuidador" },
  { id: 4, email: "patricia.morales@medinfc.mx",  rol: "cuidador" }
];

const logsAccesoDocs = [];

for (let dia = 30; dia >= 0; dia--) {
  for (const u of usuariosLogin) {
    if (Math.random() < 0.75) {
      logsAccesoDocs.push({
        pg_id_usuario: u.id,
        email: u.email,
        rol: u.rol,
        ip: "192.168.1." + randInt(10, 250),
        exitoso: true,
        user_agent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0",
        motivo_fallo: null,
        ts: daysAgo(dia, randInt(7, 21), randInt(0, 59))
      });
    }
  }
  if (Math.random() < 0.15) {
    const u = usuariosLogin[randInt(0, 3)];
    logsAccesoDocs.push({
      pg_id_usuario: null,
      email: u.email,
      rol: null,
      ip: "192.168.1." + randInt(10, 250),
      exitoso: false,
      user_agent: "Mozilla/5.0",
      motivo_fallo: "credenciales_invalidas",
      ts: daysAgo(dia, randInt(7, 21), randInt(0, 59))
    });
  }
}

db.logs_acceso.insertMany(logsAccesoDocs);
print("  ✅ " + logsAccesoDocs.length + " logs de acceso (TTL 90d)");

// ─────────────────────────────────────────────────────────────────────────────
// 9. LOGS_SISTEMA (TTL 30 días)
// ─────────────────────────────────────────────────────────────────────────────
print("📝 Poblando logs_sistema...");

const logsSistemaDocs = [
  {
    nivel: "INFO",
    modulo: "app",
    mensaje: "Aplicación MediNFC iniciada correctamente",
    detalle: "Flask 3.1.3 corriendo en puerto 5000",
    traceback: null,
    ts: daysAgo(25, 8, 0)
  },
  {
    nivel: "INFO",
    modulo: "scheduler",
    mensaje: "APScheduler activado",
    detalle: "Job sp_detectar_omisiones programado cada 5 minutos",
    traceback: null,
    ts: daysAgo(25, 8, 0)
  },
  {
    nivel: "WARNING",
    modulo: "mongo_client",
    mensaje: "Latencia elevada en escritura a eventos_nfc_rt",
    detalle: "Tiempo de respuesta: 850 ms",
    traceback: null,
    ts: daysAgo(12, 14, 23)
  },
  {
    nivel: "ERROR",
    modulo: "api_gps",
    mensaje: "Ping GPS recibido con IMEI no registrado",
    detalle: "IMEI=999999999999999 ignorado",
    traceback: null,
    ts: daysAgo(8, 11, 7)
  },
  {
    nivel: "INFO",
    modulo: "cuidador_controller",
    mensaje: "Receta vinculada exitosamente",
    detalle: "UID=NFC-RM-001 → id_receta_medicamento=1",
    traceback: null,
    ts: daysAgo(20, 9, 15)
  },
  {
    nivel: "WARNING",
    modulo: "psycopg",
    mensaje: "Pool de conexiones cerca del límite",
    detalle: "8/10 conexiones activas",
    traceback: null,
    ts: daysAgo(5, 16, 42)
  },
  {
    nivel: "ERROR",
    modulo: "doctor_controller",
    mensaje: "Excepción al cargar dashboard del médico",
    detalle: "psycopg.errors.DataError: invalid input syntax for type integer",
    traceback: "Traceback (most recent call last):\n  File \"doctor_controller.py\", line 124, in doctor_home\n    cur.execute(...)\npsycopg.errors.DataError: invalid input syntax for type integer: \"None\"",
    ts: daysAgo(3, 10, 28)
  },
  {
    nivel: "INFO",
    modulo: "scheduler",
    mensaje: "sp_detectar_omisiones ejecutado",
    detalle: "12 tomas marcadas como omitidas",
    traceback: null,
    ts: daysAgo(0, 6, 35)
  },
  {
    nivel: "INFO",
    modulo: "scheduler",
    mensaje: "sp_detectar_omisiones ejecutado",
    detalle: "3 tomas marcadas como omitidas",
    traceback: null,
    ts: daysAgo(0, 10, 5)
  },
  {
    nivel: "INFO",
    modulo: "scheduler",
    mensaje: "sp_detectar_omisiones ejecutado",
    detalle: "0 tomas marcadas como omitidas",
    traceback: null,
    ts: daysAgo(0, 13, 0)
  }
];

db.logs_sistema.insertMany(logsSistemaDocs);
print("  ✅ " + logsSistemaDocs.length + " logs de sistema (TTL 30d)");

// ─────────────────────────────────────────────────────────────────────────────
// 10. LOGS_NFC_FALLIDOS — escaneos rechazados
// ─────────────────────────────────────────────────────────────────────────────
print("⚠️  Poblando logs_nfc_fallidos...");

const logsNfcFallidosDocs = [
  {
    pg_id_cuidador: 1,
    nombre_cuidador: "María López",
    uid_nfc: "NFC-XYZ-9999",
    motivo: "uid_desconocido",
    ip: "192.168.1.45",
    ts: daysAgo(5, 11, 23)
  },
  {
    pg_id_cuidador: 1,
    nombre_cuidador: "María López",
    uid_nfc: "NFC-OLD-0001",
    motivo: "etiqueta_inactiva",
    ip: "192.168.1.45",
    ts: daysAgo(4, 8, 12)
  },
  {
    pg_id_cuidador: 2,
    nombre_cuidador: "Carlos Ramírez",
    uid_nfc: "NFC-RM-004",
    motivo: "duplicado",
    ip: "192.168.1.78",
    ts: daysAgo(3, 7, 35)
  },
  {
    pg_id_cuidador: 3,
    nombre_cuidador: "Patricia Morales",
    uid_nfc: "NFC-UNKNOWN-123",
    motivo: "uid_desconocido",
    ip: "192.168.1.92",
    ts: daysAgo(2, 10, 5)
  },
  {
    pg_id_cuidador: 1,
    nombre_cuidador: "María López",
    uid_nfc: "NFC-RM-003",
    motivo: "receta_vencida",
    ip: "192.168.1.45",
    ts: daysAgo(2, 14, 18)
  },
  {
    pg_id_cuidador: 1,
    nombre_cuidador: "María López",
    uid_nfc: "NFC-DEAD-TAG",
    motivo: "uid_desconocido",
    ip: "192.168.1.45",
    ts: daysAgo(1, 9, 41)
  },
  {
    pg_id_cuidador: 2,
    nombre_cuidador: "Carlos Ramírez",
    uid_nfc: "NFC-RM-005",
    motivo: "duplicado",
    ip: "192.168.1.78",
    ts: daysAgo(1, 13, 22)
  },
  {
    pg_id_cuidador: 2,
    nombre_cuidador: "Carlos Ramírez",
    uid_nfc: "NFC-RM-004",
    motivo: "duplicado",
    ip: "192.168.1.78",
    ts: daysAgo(0, 7, 55)
  }
];

db.logs_nfc_fallidos.insertMany(logsNfcFallidosDocs);
print("  ✅ " + logsNfcFallidosDocs.length + " logs de NFC fallidos");

// ─────────────────────────────────────────────────────────────────────────────
// RESUMEN FINAL
// ─────────────────────────────────────────────────────────────────────────────
print("\n═══════════════════════════════════════════════════");
print("  ✅ SEED MONGODB COMPLETADO");
print("═══════════════════════════════════════════════════");
COLLECTIONS.forEach(c => {
  const n = db[c].countDocuments({});
  print("  " + c.padEnd(25) + " " + n + " docs");
});
print("═══════════════════════════════════════════════════");
print("\n📊 Verificación rápida:");
print("\nAdherencia promedio últimos 7 días por paciente:");
db.historico_adherencia.aggregate([
  { $match: { fecha: { $gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) } } },
  { $group: {
      _id: { id: "$pg_id_paciente", nombre: "$paciente" },
      adherencia_avg: { $avg: "$metricas.pct_adherencia" },
      dias: { $sum: 1 }
  }},
  { $sort: { "_id.id": 1 } }
]).forEach(r => {
  print("  " + r._id.nombre.padEnd(20) + " " + r.adherencia_avg.toFixed(1) + "% (" + r.dias + " días)");
});

print("\nAlertas pendientes por paciente:");
db.alertas_rt.aggregate([
  { $match: { estado: "Pendiente" } },
  { $group: { _id: "$paciente", n: { $sum: 1 } }},
  { $sort: { n: -1 } }
]).forEach(r => {
  print("  " + r._id.padEnd(20) + " " + r.n);
});

print("\n✨ Listo. Usa estas credenciales para entrar:");
print("   dr.garza@medinfc.mx        / Medinfc2024!");
print("   maria.lopez@medinfc.mx     / Medinfc2024!");
print("   carlos.ramirez@medinfc.mx  / Medinfc2024!");
print("   patricia.morales@medinfc.mx / Medinfc2024!");