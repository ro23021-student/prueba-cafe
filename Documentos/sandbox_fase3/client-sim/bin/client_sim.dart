import 'dart:io';
import 'package:client_sim/client_sim.dart';
import 'package:http/http.dart' as http;

String _pct(double? v) => v == null ? 'n/d' : '${(v * 100).toStringAsFixed(2)} %';

Future<void> main() async {
  final Config c;
  try {
    c = Config.desdeEntorno(Platform.environment);
  } on FormatException catch (e) {
    stderr.writeln('Configuración inválida: ${e.message}');
    exitCode = 2;
    return;
  }

  final ControladorRed red = c.modoCortes == 'self' ? RedTc(c.netemBase) : RedNinguna();
  try {
    final r = await correrSimulacion(
      c,
      red: red,
      fabricaHttp: () => http.Client(),
      log: (s) => stdout.writeln('[client-sim] $s'),
    );
    await escribirResultados(c, r.docs, r.resumen);
    final s = r.resumen;
    stdout.writeln('[client-sim] Listo. Archivos: ${c.outDir}/docs_${c.runId}.csv y resumen_${c.runId}.json');
    stdout.writeln('[client-sim] Generados: ${s.generadosTotal} (ventana: ${s.generadosVentana})');
    stdout.writeln('[client-sim] VD1 throughput: ${s.vd1DocsPorS.toStringAsFixed(3)} docs/s');
    stdout.writeln('[client-sim] VD2 TFS: ${_pct(s.vd2Tfs)}  desglose: ${s.desglose}');
    stdout.writeln('[client-sim] VD3 resincronización por corte (s): ${s.vd3PorCorte}');
    stdout.writeln('[client-sim] Error por intento: ${_pct(s.tasaErrorPorIntento)}');
    if (s.lotesSinVerificar > 0) {
      stdout.writeln('[client-sim] AVISO: ${s.lotesSinVerificar} lotes no se pudieron leer del servidor');
    }
    if (s.generadosTotal == 0 && Platform.environment['ALLOW_EMPTY'] != '1') {
      stderr.writeln('[client-sim] ERROR: la corrida genero 0 documentos; se considera invalida.');
      exitCode = 3;
    }
  } on StateError catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1); // exit() y no return: hay temporizadores de los dispositivos todavía activos
  }
}
