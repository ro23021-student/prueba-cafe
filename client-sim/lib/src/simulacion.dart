import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:trazabilidad_core/trazabilidad_core.dart';
import 'config.dart';
import 'dispositivo.dart';
import 'red.dart';
import 'resultados.dart';

class ResultadoCorrida {
  final ResumenCorrida resumen;
  final List<FilaDoc> docs;
  const ResultadoCorrida(this.resumen, this.docs);
}

Future<void> _hasta(Stopwatch reloj, Duration objetivo) async {
  final falta = objetivo - reloj.elapsed;
  if (falta > Duration.zero) {
    await Future<void>.delayed(falta);
  }
}

Future<void> _ejecutarCortes(Config c, ControladorRed red, Stopwatch reloj, List<CorteReal> salida) async {
  for (final k in c.cortes) {
    await _hasta(reloj, Duration(seconds: k.inicioS));
    final ini = DateTime.now().millisecondsSinceEpoch;
    await red.cortar();
    await _hasta(reloj, Duration(seconds: k.finS));
    await red.restaurar();
    final fin = DateTime.now().millisecondsSinceEpoch;
    salida.add(CorteReal(ini, fin, red.fuente));
  }
}

/// Lee del servidor, lote por lote, el hash de cada evento. Devuelve (id → hash, lotes que no se pudieron leer).
Future<(Map<String, String>, List<String>)> _leerServidor(Set<String> lotes, ApiCliente api) async {
  final hashes = <String, String>{};
  final fallidos = <String>[];
  final cola = lotes.toList();
  var siguiente = 0;

  Future<void> trabajador() async {
    while (siguiente < cola.length) {
      final lote = cola[siguiente++];
      var leido = false;
      for (var intento = 0; intento < 5 && !leido; intento++) {
        try {
          for (final e in await api.consultarLote(lote)) {
            hashes[e.id] = e.hash;
          }
          leido = true;
        } on ErrorRed {
          await Future<void>.delayed(const Duration(seconds: 1));
        } on ErrorRechazado {
          break;
        }
      }
      if (!leido) {
        fallidos.add(lote);
      }
    }
  }

  await Future.wait([for (var i = 0; i < 16; i++) trabajador()]);
  return (hashes, fallidos);
}

/// Ejecuta una corrida completa del escenario E2 (Fase 3, 3.2.6):
/// calentamiento + ventana de medición con cortes, drenaje y verificación de identificadores y hashes.
Future<ResultadoCorrida> correrSimulacion(
  Config c, {
  required ControladorRed red,
  required http.Client Function() fabricaHttp,
  void Function(String)? log,
}) async {
  final escribir = log ?? (String _) {};
  await red.preparar();

  final disp = <DispositivoSim>[];
  for (var i = 0; i < c.dispositivos; i++) {
    final almacen = AlmacenMemoria();
    final api = ApiCliente(c.apiUrl,
        cliente: fabricaHttp(), timeout: Duration(seconds: c.timeoutS), usuario: c.apiUser, clave: c.apiPass);
    final motor = MotorSync(
      almacen,
      api,
      intervaloBase: Duration(seconds: c.syncBaseS),
      intervaloMaximo: Duration(seconds: c.syncMaxS),
      maxIntentos: c.maxIntentosSincronizacion,
    );
    disp.add(DispositivoSim(
      indice: i,
      semilla: c.semilla,
      intervaloMedioS: c.intervaloMedioS,
      docBytes: c.docBytes,
      almacen: almacen,
      api: api,
      motor: motor,
    ));
  }
  for (final d in disp) {
    d.motor.iniciar();
  }

  final reloj = Stopwatch()..start();
  final t0Ms = DateTime.now().millisecondsSinceEpoch;
  final limite = Duration(seconds: c.runSegundos);
  bool debeParar() => reloj.elapsed >= limite;
  final cortes = <CorteReal>[];
  escribir('Corrida ${c.runId}: ${c.dispositivos} dispositivos, ${c.runSegundos} s, cortes: ${c.cortes.length}');

  await Future.wait<void>([
    for (final d in disp) d.ejecutar(debeParar),
    _ejecutarCortes(c, red, reloj, cortes),
  ]);

  escribir('Generación terminada; drenando hasta ${c.drenajeS} s…');
  final drenaje = Stopwatch()..start();
  while (drenaje.elapsed < Duration(seconds: c.drenajeS)) {
    var pend = 0;
    for (final d in disp) {
      pend += await d.pendientes();
    }
    if (pend == 0) {
      break;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  final finDrenajeMs = DateTime.now().millisecondsSinceEpoch;
  for (final d in disp) {
    d.motor.detener();
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await red.quitarDegradacion();

  escribir('Verificando contra el servidor…');
  final verificador =
      ApiCliente(c.apiUrl, cliente: fabricaHttp(), timeout: const Duration(seconds: 10), usuario: c.apiUser, clave: c.apiPass);
  final lotes = {
    for (final d in disp)
      for (final g in d.generados) g.loteId
  };
  final (servidor, sinVerificar) = await _leerServidor(lotes, verificador);

  final filas = <FilaDoc>[];
  for (final d in disp) {
    final registros = {for (final r in await d.almacen.todos()) r.evento.id: r};
    for (final g in d.generados) {
      final r = registros[g.id]!;
      filas.add(FilaDoc(
        runId: c.runId,
        arch: c.arch,
        dispositivo: g.dispositivo,
        id: g.id,
        loteId: g.loteId,
        hash: g.hash,
        creadoMs: g.creadoMs,
        confirmadoMs: r.confirmadoMs,
        estadoCliente: r.estado.name,
        intentos: r.intentos,
        verificacion: clasificar(
          estadoCliente: r.estado,
          hashServidor: servidor[g.id],
          hashCliente: g.hash,
        ),
      ));
    }
  }

  var cortesFinales = cortes;
  if (c.modoCortes == 'external') {
    final reales = await cortesDesdeOutageSh(c.outDir, t0Ms, c.cortes.length);
    if (reales != null) {
      cortesFinales = reales;
    }
  }

  for (final d in disp) {
    d.api.cerrar();
  }
  verificador.cerrar();

  final resumen = calcularResumen(
    c: c,
    t0Ms: t0Ms,
    docs: filas,
    cortes: cortesFinales,
    finDrenajeMs: finDrenajeMs,
    lecturasOk: disp.fold(0, (s, d) => s + d.lecturasOk),
    lecturasFallidas: disp.fold(0, (s, d) => s + d.lecturasFallidas),
    lotesSinVerificar: sinVerificar.length,
  );
  return ResultadoCorrida(resumen, filas);
}
