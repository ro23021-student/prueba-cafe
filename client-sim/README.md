# client-sim (Fase 3, escenario E2)

Agentes Dart sin interfaz que usan el mismo núcleo que la app Flutter (`../cliente/trazabilidad_core`).
Cada dispositivo simulado genera eventos (intervalo exponencial; 70 % creación, 20 % actualización, 10 % lectura),
los guarda en local y los envía con el motor de sincronización. Al terminar, verifica identificador y hash de cada
documento contra el servidor y calcula VD1, VD2 y VD3.

Variables de entorno (las mismas del docker-compose): API_URL, ARCH, DEVICES, SEED, RUN_SECONDS, WARMUP_S (30),
MEASURE_S (240), DRAIN_S (120), OUTAGE_PLAN ("60:30,180:30"), OUTAGE_MODE (self|external), NETEM_BASE,
MEAN_INTERVAL_S (2.0), API_USER y API_PASS (usuario de la API con rol tecnico; van juntas; en el sandbox: `sim` y SIM_PASS), SYNC_BASE_S (5), SYNC_MAX_S (60), HTTP_TIMEOUT_S (5), DOC_BYTES (1200), RUN_ID, OUT_DIR.

Salidas en OUT_DIR: `docs_<RUN_ID>.csv` (un renglón por documento) y `resumen_<RUN_ID>.json`.

Pruebas: `dart pub get && dart analyze && dart test`.
