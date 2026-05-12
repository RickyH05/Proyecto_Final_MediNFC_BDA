# MediNFC — Guía de instalación y pruebas

Sistema de adherencia terapéutica para adultos mayores con NFC, GPS y dashboards analíticos.

---

## 📋 Requisitos previos

Antes de empezar, asegúrate de tener instalado:

| Software | Versión | Cómo instalar (macOS) |
|----------|---------|------------------------|
| Python | 3.10 o superior | `brew install python@3.11` |
| PostgreSQL | 14 o superior | `brew install postgresql@16` |
| MongoDB | 7.0 o superior | `brew tap mongodb/brew && brew install mongodb-community` |
| Node.js | 18 o superior | `brew install node` (solo necesario si quieres usar mongosh) |
| mongosh | última | `brew install mongosh` |
| ngrok | última | `brew install ngrok` (**solo si va a probar el escáner NFC**) |

En Windows o Linux, usar los instaladores oficiales de cada herramienta.

> ⚠️ **Importante para probar el escáner NFC**: La Web NFC API que usa el escáner **solo funciona en Chrome para Android sobre HTTPS**. Como Flask local corre en HTTP, hay que usar **ngrok** para exponer el servidor con un certificado HTTPS temporal. Sin esto, el escaneo NFC **no funcionará**.

---

## 🚀 Pasos de instalación

### 1. Clonar e instalar dependencias de Python

```bash
cd Entrega_Final
pip install -r requirements.txt
```

Si `pip` da errores de versión, usa:

```bash
pip install "psycopg[binary]" bcrypt Flask Flask-Bcrypt pymongo APScheduler pyOpenSSL tzlocal
```

### 2. Arrancar los servicios de base de datos

```bash
# PostgreSQL
brew services start postgresql@16

# MongoDB
brew services start mongodb-community
```

Verifica que ambos estén corriendo:

```bash
pg_isready -h localhost -p 5432       # debe decir "accepting connections"
mongosh --eval "db.runCommand({ping:1})"   # debe decir { ok: 1 }
```

### 3. Crear el usuario y la base de datos de PostgreSQL

Conéctate como superusuario:

```bash
psql postgres
```

Y dentro de psql ejecuta:

```sql
CREATE USER proyectofinal_user WITH PASSWORD '444';
ALTER USER proyectofinal_user CREATEDB;
CREATE DATABASE medi_nfc2 OWNER proyectofinal_user;
\q
```

### 4. Cargar el esquema PostgreSQL

Esto crea las **33 tablas**, los **60+ procedimientos almacenados**, **triggers**, **views** e **índices**:

```bash
psql -U proyectofinal_user -d medi_nfc2 -f MediNFC_test.sql
```

Cuando pida contraseña, escribe `444`.

> Si quieres evitar que pida la contraseña cada vez:
> ```bash
> export PGPASSWORD=444
> ```

### 5. Cargar los datos de prueba (seed PostgreSQL)

Inserta 3 pacientes, 3 cuidadores, 1 médico, recetas, ~100 eventos NFC históricos:

```bash
psql -U proyectofinal_user -d medi_nfc2 -f seed_test_data.sql
```

### 6. Generar las contraseñas de los usuarios

El SQL deja los usuarios con un hash placeholder no válido. Este script lo reemplaza por hashes bcrypt reales:

```bash
python mediNFC/seed_users.py
```

Salida esperada:

```
✓  dr.garza@medinfc.mx              Password actualizado [ACTUALIZADO]
✓  maria.lopez@medinfc.mx           Password actualizado [ACTUALIZADO]
✓  carlos.ramirez@medinfc.mx        Password actualizado [ACTUALIZADO]
✓  patricia.morales@medinfc.mx      Password actualizado [ACTUALIZADO]

Total usuarios: 4
Contraseña de todos los usuarios: Medinfc2024!
```

### 6.5. Generar datos de proximidad GPS + beacons

Este paso puebla las tablas `ubicacion_gps` y `evento_proximidad` con coordenadas cerca de los beacons de cada paciente, calculando la **distancia Haversine** real entre el cuidador y el beacon. Es lo que hace que la pantalla `/doctor/proximidad/historial` muestre distancias en metros y estados "Válido" o "Fuera de rango" en lugar de "Sin beacon" para todos los eventos.

```bash
psql -U proyectofinal_user -d medi_nfc2 -f seed_proximidad.sql
```

Salida esperada:

```
BEGIN
TRUNCATE TABLE
DELETE N
NOTICE:  ──────── RESULTADO ────────
NOTICE:  Eventos procesados:          ~12
NOTICE:  Dentro del radio (válida):   ~10 (~83%)
NOTICE:  Fuera del radio (alerta):    ~2 (~17%)
NOTICE:  ───────────────────────────
COMMIT
```

> El script es **idempotente** — se puede correr varias veces sin duplicar datos. Cada ejecución regenera con distribución aleatoria 85/15 (dentro/fuera del radio del beacon), así que los porcentajes pueden variar entre corridas.

> Adicionalmente, el script genera un "ping de tracking" reciente (últimas 2h) para cada cuidador activo, simulando que Traccar Client sigue publicando posición aunque el cuidador no esté escaneando medicamentos. Esto hace que `/doctor/mapa` muestre todos los cuidadores con su posición GPS.

### 7. Cargar el esquema y los datos de MongoDB

Crea las **9 colecciones** con sus **índices** y **TTL** (90d para logs de acceso, 30d para logs de sistema):

```bash
mongosh medinfc_mongo mongo_schema.js
```

Luego inserta los datos de prueba (~1,000 documentos: adherencia diaria, eventos NFC, alertas, GPS de Traccar, logs):

```bash
mongosh medinfc_mongo seed_mongo.js
```

Al final verás un resumen:

```
historico_adherencia      93 docs
eventos_nfc_rt            174 docs
alertas_rt                14 docs
ubicaciones_gps_hist      170 docs
historial_gps             600 docs
logs_acceso               100 docs
logs_sistema              10 docs
logs_nfc_fallidos         8 docs

Adherencia promedio últimos 7 días por paciente:
  Elena Martínez       92.9%
  Héctor González      35.7%
  Consuelo Vázquez     42.9%
```

> 📝 La colección `perfil_clinico_paciente` está definida en el esquema (paso anterior) pero comienza vacía. Se llena automáticamente cuando un médico añade notas clínicas, alergias o condiciones extras desde la app. Total: **9 colecciones** disponibles.

### 8. Arrancar Flask

```bash
python app.py
```

Deberías ver:

```
* Running on http://127.0.0.1:5000
* Debug mode: on
```

Abre el navegador en **http://127.0.0.1:5000** y haz login.

---

## 👤 Credenciales de prueba

Todos usan la misma contraseña: **`Medinfc2024!`**

| Rol | Email | Qué verá |
|-----|-------|----------|
| **Médico** | `dr.garza@medinfc.mx` | Dashboard, 3 pacientes, alertas, riesgo de omisión, mapa, tendencia |
| **Cuidador** | `maria.lopez@medinfc.mx` | Atiende a Elena y Héctor — adherencia buena/regular |
| **Cuidador** | `carlos.ramirez@medinfc.mx` | Atiende a Consuelo — caso clínico CRÍTICO |
| **Cuidador** | `patricia.morales@medinfc.mx` | Cuidador secundario de fin de semana |

> El **administrador** se autentica con credenciales separadas que están definidas en `config.py`. Pregunta al equipo si necesitas acceso de admin.

---

## 📱 Cómo probar el escáner NFC (requiere ngrok + Android)

El escáner NFC usa la **Web NFC API (NDEFReader)** del navegador, que tiene dos restricciones técnicas:

1. **Solo funciona en Chrome para Android** (no Safari, no iOS, no Chrome de escritorio, no Firefox)
2. **Requiere HTTPS obligatoriamente** (no funciona sobre HTTP)

Como Flask corre en HTTP local, hay que exponerlo con HTTPS usando **ngrok**.

### Paso 1: Crear cuenta gratuita en ngrok

1. Ve a https://ngrok.com/signup y crea una cuenta gratuita.
2. Copia tu token de autenticación desde el dashboard.
3. Configúralo localmente:

```bash
ngrok config add-authtoken TU_TOKEN_AQUI
```

### Paso 2: Exponer Flask con ngrok

Con Flask corriendo en otra terminal (`python app.py`), abre una nueva terminal y ejecuta:

```bash
ngrok http 5000
```

ngrok te dará una URL pública del tipo:

```
Forwarding   https://a1b2-c3d4-e5f6.ngrok-free.app -> http://localhost:5000
```

**Copia esa URL HTTPS**.

### Paso 3: Probar desde un teléfono Android

1. Abre **Chrome** en un teléfono Android.
2. Entra a la URL HTTPS que te dio ngrok (ejemplo: `https://a1b2-c3d4-e5f6.ngrok-free.app`).
3. Salta el aviso de ngrok ("Visit Site").
4. Haz login como **cuidador** (por ejemplo `maria.lopez@medinfc.mx` / `Medinfc2024!`).
5. Ve al perfil de un paciente y abre **"Escanear NFC"**.
6. El navegador pedirá permiso para usar NFC — acéptalo.
7. Acerca cualquier etiqueta NFC al teléfono. El UID aparecerá automáticamente en el formulario.

> Si no tienes etiquetas NFC físicas, puedes usar **cualquier tarjeta NFC** que tengas a la mano: tarjetas de transporte público, tarjetas hoteleras, llaveros NFC, etc. Solo se lee el UID; no se modifican datos. Como esa tarjeta no estará vinculada a una receta en la BD, se registrará como "UID desconocido" en la colección `logs_nfc_fallidos` de MongoDB — exactamente el flujo de error que el sistema está diseñado para manejar.

> ⚠️ **Si no tienes Android**, el escáner NFC no funcionará. Las demás pantallas (dashboards, gráficas, reportes, mapas, alertas) funcionan perfectamente desde cualquier navegador en escritorio.

---

## 🗺️ Recorrido sugerido para evaluar el sistema

### Como administrador (necesitas las credenciales de admin)

1. `/admin` → Dashboard global con KPIs
2. `/admin/dispositivos` → Lista de 3 GPS Teltonika/Queclink y 3 beacons
3. `/admin/reportes/ranking` → Ranking de mejora por cuidador y médico
4. `/admin/reporte-tendencia-global` → Tendencia global con clasificación ESTABLE/DECLIVE
5. `/admin/supervision` → Vista global médico-paciente-cuidador
6. `/admin/logs-mongo` → Logs MongoDB con TTL automático

### Como médico (`dr.garza@medinfc.mx`)

1. `/doctor` → Dashboard con 3 pacientes, adherencia por paciente
2. `/doctor/riesgo-omision` → **Pantalla estrella**: rachas críticas de omisión
3. `/doctor/mapa` → Mapa interactivo con beacons y GPS de cuidadores
4. `/doctor/pacientes/3` → Perfil de Consuelo (caso crítico — Alzheimer + Osteoporosis)
5. `/doctor/pacientes/1/tendencia` → Línea ascendente de Elena (MEJORA)
6. `/doctor/alertas` → 13 alertas pendientes

### Como cuidador (`carlos.ramirez@medinfc.mx`)

1. `/cuidador` → Agenda del día con próxima toma 19:30
2. `/cuidador/mi-gps` → Su dispositivo Teltonika activo
3. `/cuidador/grafica-adherencia` → Su gráfica personal de tomas (rojas = omisiones de Consuelo)
4. `/cuidador/paciente/3/escaneo` → **Aquí va el escaneo NFC con ngrok+Android**
5. `/cuidador/alertas` → 4 alertas pendientes

---

## 🧪 Verificación rápida de que todo funciona

Si quieres comprobar que el seed corrió bien sin entrar a la app:

```sql
-- En PostgreSQL
psql -U proyectofinal_user -d medi_nfc2 -c "
SELECT estado_agenda, COUNT(*) FROM agenda_toma
WHERE fecha_hora_programada::DATE < CURRENT_DATE
GROUP BY estado_agenda;
"
```

Esperado: `cumplida ~65, tardia ~10, omitida ~85`

```javascript
// En MongoDB
mongosh medinfc_mongo --eval '
db.historico_adherencia.aggregate([
  { $match: { fecha: { $gte: new Date(Date.now() - 7*24*60*60*1000) } } },
  { $group: { _id: "$paciente", avg: { $avg: "$metricas.pct_adherencia" } } },
  { $sort: { _id: 1 } }
]).forEach(r => print(r._id + ": " + r.avg.toFixed(1) + "%"))
'
```

Esperado: Elena ~92%, Héctor ~36%, Consuelo ~43%

```sql
-- Verificar proximidades generadas (eventos NFC con GPS y distancia)
psql -U proyectofinal_user -d medi_nfc2 -c "
SELECT
    CASE WHEN proximidad_valida THEN 'Válida' ELSE 'Inválida' END AS estado,
    COUNT(*),
    ROUND(AVG(distancia_metros)::numeric, 2) AS dist_promedio_m
FROM evento_proximidad
GROUP BY proximidad_valida;
"
```

Esperado: alrededor de **9-10 eventos válidos** (~3-5 m de distancia promedio) y **2-3 eventos inválidos** (~30-50 m de distancia promedio).

---

## ❓ Solución de problemas comunes

### "Password authentication failed for user proyectofinal_user"

La contraseña del usuario no es `444`. Recréalo:

```sql
psql postgres
ALTER USER proyectofinal_user WITH PASSWORD '444';
```

### "Database medi_nfc2 does not exist"

No corriste el paso 3. Regresa y créala con `CREATE DATABASE medi_nfc2 ...`.

### "Connection refused" al arrancar Flask

PostgreSQL o MongoDB no están corriendo. Vuelve a arrancarlos:

```bash
brew services restart postgresql@16
brew services restart mongodb-community
```

### "ModuleNotFoundError: No module named 'psycopg'"

Faltan dependencias de Python. Reinstala:

```bash
pip install -r requirements.txt
```

### El escáner NFC no detecta nada en Android

Verifica:
- Estás usando **Chrome para Android** (no otro navegador)
- La URL empieza con **https://** (la de ngrok, no la local)
- El teléfono tiene **NFC habilitado** en ajustes
- Le diste **permiso de NFC** al navegador cuando lo pidió
- La etiqueta NFC está **cerca de la antena** del teléfono (suele estar en la parte trasera superior)

### Veo "Credenciales incorrectas" aunque escribo bien la contraseña

Asegúrate de haber corrido `python mediNFC/seed_users.py` después de `seed_test_data.sql`. El SQL deja un hash placeholder que no es válido; el Python lo reemplaza con bcrypt real.

### En `/doctor/proximidad/historial` todos los eventos dicen "Sin beacon"

Falta correr `seed_proximidad.sql`. Es el paso 6.5 de la instalación. Lo arregla así:

```bash
psql -U proyectofinal_user -d medi_nfc2 -f seed_proximidad.sql
```

Después recarga la pantalla y verás distancias en metros + badges "Válido"/"Fuera de rango". Los eventos viejos (>5 días) seguirán como "Sin beacon" — es normal, el script solo genera proximidades para eventos recientes.

### En `/doctor/mapa` Consuelo aparece con "Sin cuidador asignado"

Falta correr `seed_proximidad.sql` (paso 6.5). Ese script genera el ping de tracking reciente que asocia GPS a cada cuidador, incluyendo a Carlos (cuidador principal de Consuelo).

### El mapa de "Trayecto GPS" dice "Sin datos GPS en las últimas 12 horas"

Cuando un cuidador no tiene escaneos NFC recientes, su trayecto puede aparecer vacío. Para inflar los datos, vuelve a correr `seed_mongo.js`:

```bash
mongosh medinfc_mongo seed_mongo.js
```

Eso recarga 170 puntos GPS densos repartidos en las últimas 48h.

### Marcar alerta como "Atendida" tira error `null value in column "id_evento"`

Tu `MediNFC_test.sql` está desactualizado. La tabla `bitacora_regla_negocio` debe permitir `id_evento NULL` porque las alertas de Omisión no tienen evento NFC asociado. Aplica el ALTER en caliente:

```bash
psql -U proyectofinal_user -d medi_nfc2 -c "ALTER TABLE bitacora_regla_negocio ALTER COLUMN id_evento DROP NOT NULL;"
```

---

## 📦 Resumen de archivos del proyecto

| Archivo | Propósito |
|---------|-----------|
| `MediNFC_test.sql` | Esquema PostgreSQL completo (33 tablas, 60+ SPs, triggers, views) |
| `seed_test_data.sql` | Datos de prueba PostgreSQL (3 pacientes, 100 eventos NFC) |
| `mediNFC/seed_users.py` | Genera hashes bcrypt válidos para los 4 usuarios |
| `seed_proximidad.sql` | Genera coordenadas GPS y proximidades para eventos NFC recientes |
| `mongo_schema.js` | Esquema MongoDB (9 colecciones, índices, TTL) |
| `seed_mongo.js` | Datos de prueba MongoDB (~1,000 documentos) |
| `app.py` | Aplicación Flask principal |
| `config.py` | Configuración (DSN PostgreSQL, secret key, hash admin) |
| `mongo_client.py` | Funciones de lectura/escritura MongoDB |
| `controllers/` | Lógica por rol (auth, admin, doctor, cuidador) |
| `templates/` | Plantillas Jinja2 |
| `static/` | CSS, JS, imágenes, librerías |
| `requirements.txt` | Dependencias Python |

---

## 📞 Contacto del equipo

Si algo no funciona, contacta al equipo de desarrollo de MediNFC.

**Universidad de Monterrey — Ingeniería en Tecnologías Computacionales — 4° semestre**