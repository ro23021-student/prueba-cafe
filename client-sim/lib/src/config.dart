/// Un corte total de red: empieza `inicioS` segundos después del arranque y dura `duracionS`.
class Interrupcion {
  final int inicioS;
  final int duracionS;
  const Interrupcion(this.inicioS, this.duracionS);
  int get finS => inicioS + duracionS;
}

/// Convierte "60:30,180:30" (inicio_s:duracion_s separados por coma) en una lista validada.
List<Interrupcion> parsearPlanCortes(String texto) {
  final t = texto.trim();
  if (t.isEmpty) {
    return const [];
  }
  final lista = <Interrupcion>[];
  for (final parte in t.split(',')) {
    final p = parte.trim().split(':');
    final i = p.length == 2 ? int.tryParse(p[0].trim()) : null;
    final d = p.length == 2 ? int.tryParse(p[1].trim()) : null;
    if (i == null || d == null || i < 0 || d <= 0) {
      throw FormatException('OUTAGE_PLAN inválido en "$parte": use inicio_s:duracion_s');
    }
    lista.add(Interrupcion(i, d));
  }
  lista.sort((a, b) => a.inicioS.compareTo(b.inicioS));
  for (var k = 1; k < lista.length; k++) {
    if (lista[k].inicioS < lista[k - 1].finS) {
      throw const FormatException('OUTAGE_PLAN: los cortes no pueden solaparse');
    }
  }
  return lista;
}

/// Parámetros de una corrida, leídos de variables de entorno (las mismas que declara docker-compose).
class Config {
  final String apiUrl;
  final String? apiUser; // credenciales del usuario de la simulación (rol tecnico); null = sin autenticación
  final String? apiPass;
  final String arch;
  final int dispositivos;
  final int semilla;
  final int runSegundos;
  final int calentamientoS;
  final int medicionS;
  final int drenajeS;
  final List<Interrupcion> cortes;
  final String modoCortes; // self = el propio cliente corta la red con tc; external = lo hace outage.sh desde el anfitrión
  final String netemBase; // perfil de red de la corrida (ej. "delay 50ms 10ms loss 5% rate 2mbit")
  final String outDir;
  final String runId;
  final double intervaloMedioS;
  final int syncBaseS;
  final int syncMaxS;
  final int timeoutS;
  final int docBytes;
  final int? maxIntentosSincronizacion; // null = ilimitado

  const Config({
    required this.apiUrl,
    required this.arch,
    required this.dispositivos,
    required this.semilla,
    required this.runSegundos,
    required this.calentamientoS,
    required this.medicionS,
    required this.drenajeS,
    required this.cortes,
    required this.modoCortes,
    required this.netemBase,
    required this.outDir,
    required this.runId,
    required this.intervaloMedioS,
    required this.syncBaseS,
    required this.syncMaxS,
    required this.timeoutS,
    required this.docBytes,
    this.maxIntentosSincronizacion,
    this.apiUser,
    this.apiPass,
  });

  factory Config.desdeEntorno(Map<String, String> env) {
    String texto(String k, String def) {
      final v = env[k]?.trim();
      return (v == null || v.isEmpty) ? def : v;
    }

    int entero(String k, int def) {
      final v = texto(k, '$def');
      final n = int.tryParse(v);
      if (n == null) {
        throw FormatException('$k debe ser un entero (recibido "$v")');
      }
      return n;
    }

    double real(String k, double def) {
      final v = texto(k, '$def');
      final n = double.tryParse(v);
      if (n == null) {
        throw FormatException('$k debe ser un número (recibido "$v")');
      }
      return n;
    }

    final arch = texto('ARCH', 'treatment');
    final dispositivos = entero('DEVICES', 10);
    final semilla = entero('SEED', 1);
    final runS = entero('RUN_SECONDS', 300);
    final warm = entero('WARMUP_S', 30);
    final medicion = entero('MEASURE_S', 240);
    final drenaje = entero('DRAIN_S', 120);
    final planCortes = env.containsKey('OUTAGE_PLAN')
        ? (env['OUTAGE_PLAN'] ?? '').trim()
        : '60:30,180:30';
    final cortes = parsearPlanCortes(planCortes);
    final modo = texto('OUTAGE_MODE', 'self');
    final intervalo = real('MEAN_INTERVAL_S', 2.0);
    final syncBase = entero('SYNC_BASE_S', 5);
    final syncMax = entero('SYNC_MAX_S', 60);
    final docBytes = entero('DOC_BYTES', 1200);
    final rawMaxIntentos = env['MAX_INTENTOS_SINCRONIZACION'];
    final maxIntentosSincronizacion = rawMaxIntentos != null && rawMaxIntentos.isNotEmpty
        ? int.tryParse(rawMaxIntentos)
        : null;

    if (dispositivos < 1) {
      throw const FormatException('DEVICES debe ser al menos 1');
    }
    if (runS <= 0 || warm < 0 || medicion <= 0 || drenaje < 0) {
      throw const FormatException('RUN_SECONDS y MEASURE_S deben ser > 0; WARMUP_S y DRAIN_S >= 0');
    }
    if (warm + medicion > runS) {
      throw const FormatException('WARMUP_S + MEASURE_S no puede superar RUN_SECONDS');
    }
    if (modo != 'self' && modo != 'external') {
      throw FormatException('OUTAGE_MODE debe ser self o external (recibido "$modo")');
    }
    if (cortes.isNotEmpty && cortes.last.finS > runS) {
      throw const FormatException('OUTAGE_PLAN: el último corte termina después de RUN_SECONDS');
    }
    if (intervalo <= 0) {
      throw const FormatException('MEAN_INTERVAL_S debe ser > 0');
    }
    if (syncBase <= 0 || syncMax < syncBase) {
      throw const FormatException('SYNC_BASE_S > 0 y SYNC_MAX_S >= SYNC_BASE_S');
    }
    if (docBytes < 300) {
      throw const FormatException('DOC_BYTES debe ser al menos 300');
    }

    final usuarioApi = texto('API_USER', '');
    final claveApi = env['API_PASS'] ?? '';
    if (usuarioApi.isEmpty != claveApi.isEmpty) {
      throw const FormatException('API_USER y API_PASS deben definirse juntas');
    }
    final id = texto('RUN_ID', '$arch-d$dispositivos-s$semilla-${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    return Config(
      apiUrl: texto('API_URL', 'http://api:8080'),
      arch: arch,
      dispositivos: dispositivos,
      semilla: semilla,
      runSegundos: runS,
      calentamientoS: warm,
      medicionS: medicion,
      drenajeS: drenaje,
      cortes: cortes,
      modoCortes: modo,
      netemBase: texto('NETEM_BASE', ''),
      outDir: texto('OUT_DIR', '/results'),
      runId: id,
      intervaloMedioS: intervalo,
      syncBaseS: syncBase,
      syncMaxS: syncMax,
      timeoutS: entero('HTTP_TIMEOUT_S', 5),
      docBytes: docBytes,
      maxIntentosSincronizacion: maxIntentosSincronizacion,
      apiUser: usuarioApi.isEmpty ? null : usuarioApi,
      apiPass: claveApi.isEmpty ? null : claveApi,
    );
  }

  Map<String, dynamic> aJson() => {
        'run_id': runId,
        'arch': arch,
        'api_url': apiUrl,
        'api_user': apiUser, // la clave nunca se guarda en los resultados
        'dispositivos': dispositivos,
        'semilla': semilla,
        'run_s': runSegundos,
        'calentamiento_s': calentamientoS,
        'medicion_s': medicionS,
        'drenaje_s': drenajeS,
        'cortes_plan': [
          for (final k in cortes) {'inicio_s': k.inicioS, 'duracion_s': k.duracionS}
        ],
        'modo_cortes': modoCortes,
        'netem_base': netemBase,
        'intervalo_medio_s': intervaloMedioS,
        'sync_base_s': syncBaseS,
        'sync_max_s': syncMaxS,
        'http_timeout_s': timeoutS,
        'doc_bytes': docBytes,
        'max_intentos_sincronizacion': maxIntentosSincronizacion,
      };
}
