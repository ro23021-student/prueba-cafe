import 'dart:convert';
import 'dart:io';
import 'package:trazabilidad_core/trazabilidad_core.dart';
import 'config.dart';

/// Un corte de red tal como ocurrió (marcas en epoch ms).
class CorteReal {
  final int inicioMs;
  final int finMs;
  final String fuente; // tc | outage.sh | plan
  const CorteReal(this.inicioMs, this.finMs, this.fuente);
}

enum Verificacion {
  ok, // existe en el servidor con el mismo hash
  noConvergio, // sigue pendiente en el cliente al terminar el drenaje
  perdido, // el cliente cree que lo envió pero el servidor no lo tiene
  corrupto, // existe en el servidor pero con contenido distinto
  rechazado, // el servidor lo rechazó (4xx)
}

Verificacion clasificar({
  required EstadoSync estadoCliente,
  required String? hashServidor,
  required String hashCliente,
}) {
  if (hashServidor != null) {
    return hashServidor == hashCliente ? Verificacion.ok : Verificacion.corrupto;
  }
  switch (estadoCliente) {
    case EstadoSync.rechazado:
      return Verificacion.rechazado;
    case EstadoSync.sincronizado:
      return Verificacion.perdido;
    case EstadoSync.pendiente:
      return Verificacion.noConvergio;
  }
}

class FilaDoc {
  final String runId;
  final String arch;
  final int dispositivo;
  final String id;
  final String loteId;
  final String hash;
  final int creadoMs;
  final int? confirmadoMs;
  final String estadoCliente;
  final int intentos;
  final Verificacion verificacion;
  const FilaDoc({
    required this.runId,
    required this.arch,
    required this.dispositivo,
    required this.id,
    required this.loteId,
    required this.hash,
    required this.creadoMs,
    required this.confirmadoMs,
    required this.estadoCliente,
    required this.intentos,
    required this.verificacion,
  });
}

class ResumenCorrida {
  final Map<String, dynamic> config;
  final int t0Ms;
  final int generadosTotal;
  final int generadosVentana;
  final int verificadosConfirmadosEnVentana;
  final double vd1DocsPorS;
  final double? vd2Tfs;
  final double? vd2TfsVentana;
  final Map<String, int> desglose;
  final int intentosTotal;
  final int intentosFallidos;
  final double? tasaErrorPorIntento;
  final List<CorteReal> cortes;
  final List<double?> vd3PorCorte;
  final double? vd3Mediana;
  final int lecturasOk;
  final int lecturasFallidas;
  final int lotesSinVerificar;

  const ResumenCorrida({
    required this.config,
    required this.t0Ms,
    required this.generadosTotal,
    required this.generadosVentana,
    required this.verificadosConfirmadosEnVentana,
    required this.vd1DocsPorS,
    required this.vd2Tfs,
    required this.vd2TfsVentana,
    required this.desglose,
    required this.intentosTotal,
    required this.intentosFallidos,
    required this.tasaErrorPorIntento,
    required this.cortes,
    required this.vd3PorCorte,
    required this.vd3Mediana,
    required this.lecturasOk,
    required this.lecturasFallidas,
    required this.lotesSinVerificar,
  });

  Map<String, dynamic> aJson() => {
        'config': config,
        't0_ms': t0Ms,
        'generados_total': generadosTotal,
        'generados_ventana': generadosVentana,
        'verificados_confirmados_en_ventana': verificadosConfirmadosEnVentana,
        'vd1_docs_por_s': vd1DocsPorS,
        'vd2_tfs': vd2Tfs,
        'vd2_tfs_ventana': vd2TfsVentana,
        'desglose': desglose,
        'intentos_total': intentosTotal,
        'intentos_fallidos': intentosFallidos,
        'tasa_error_por_intento': tasaErrorPorIntento,
        'cortes': [
          for (var i = 0; i < cortes.length; i++)
            {
              'inicio_ms': cortes[i].inicioMs,
              'fin_ms': cortes[i].finMs,
              'fuente': cortes[i].fuente,
              'vd3_resync_s': vd3PorCorte[i],
            }
        ],
        'vd3_mediana_s': vd3Mediana,
        'lecturas_ok': lecturasOk,
        'lecturas_fallidas': lecturasFallidas,
        'lotes_sin_verificar': lotesSinVerificar,
      };
}

double? _mediana(List<double> v) {
  if (v.isEmpty) {
    return null;
  }
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Calcula las variables dependientes de la Fase 3 a partir del registro por documento.
///  VD1: documentos verificados cuya confirmación cae en la ventana de medición ÷ duración de la ventana.
///  VD2 (TFS): 1 − (documentos íntegros en el servidor ÷ documentos generados).
///  VD3: tiempo desde el fin de cada corte hasta que el servidor contiene todo lo generado hasta ese instante.
ResumenCorrida calcularResumen({
  required Config c,
  required int t0Ms,
  required List<FilaDoc> docs,
  required List<CorteReal> cortes,
  required int finDrenajeMs,
  required int lecturasOk,
  required int lecturasFallidas,
  required int lotesSinVerificar,
}) {
  final ini = t0Ms + c.calentamientoS * 1000;
  final fin = ini + c.medicionS * 1000;
  bool enVentana(int ms) => ms >= ini && ms < fin;

  final total = docs.length;
  final ok = docs.where((d) => d.verificacion == Verificacion.ok).toList();
  final generadosVentana = docs.where((d) => enVentana(d.creadoMs)).toList();
  final okGenVentana = generadosVentana.where((d) => d.verificacion == Verificacion.ok).length;
  final confirmadosVentana = ok.where((d) => d.confirmadoMs != null && enVentana(d.confirmadoMs!)).length;

  final intentosTotal = docs.fold<int>(0, (s, d) => s + d.intentos);
  final confirmados = docs.where((d) => d.confirmadoMs != null).length;
  final fallidos = intentosTotal - confirmados < 0 ? 0 : intentosTotal - confirmados;

  final vd3 = <double?>[];
  for (final k in cortes) {
    final previos = docs.where((d) => d.creadoMs <= k.finMs).toList();
    if (previos.any((d) => d.verificacion != Verificacion.ok)) {
      vd3.add(null); // no convergió
      continue;
    }
    var ultimo = k.finMs;
    for (final d in previos) {
      final t = d.confirmadoMs ?? finDrenajeMs; // en servidor pero sin confirmación del cliente: cota superior
      if (t > ultimo) {
        ultimo = t;
      }
    }
    vd3.add((ultimo - k.finMs) / 1000.0);
  }

  return ResumenCorrida(
    config: c.aJson(),
    t0Ms: t0Ms,
    generadosTotal: total,
    generadosVentana: generadosVentana.length,
    verificadosConfirmadosEnVentana: confirmadosVentana,
    vd1DocsPorS: confirmadosVentana / c.medicionS,
    vd2Tfs: total == 0 ? null : 1 - ok.length / total,
    vd2TfsVentana: generadosVentana.isEmpty ? null : 1 - okGenVentana / generadosVentana.length,
    desglose: {for (final v in Verificacion.values) v.name: docs.where((d) => d.verificacion == v).length},
    intentosTotal: intentosTotal,
    intentosFallidos: fallidos,
    tasaErrorPorIntento: intentosTotal == 0 ? null : fallidos / intentosTotal,
    cortes: cortes,
    vd3PorCorte: vd3,
    vd3Mediana: _mediana([for (final v in vd3) if (v != null) v]),
    lecturasOk: lecturasOk,
    lecturasFallidas: lecturasFallidas,
    lotesSinVerificar: lotesSinVerificar,
  );
}

Future<List<double>> _marcas(String dir, String prefijo, double desdeS) async {
  final out = <double>[];
  await for (final f in Directory(dir).list()) {
    if (f is! File) {
      continue;
    }
    final nombre = f.uri.pathSegments.last;
    if (!nombre.startsWith(prefijo) || !nombre.endsWith('.txt')) {
      continue;
    }
    final v = double.tryParse((await f.readAsString()).trim());
    if (v != null && v >= desdeS) {
      out.add(v);
    }
  }
  out.sort();
  return out;
}

/// Modo external: lee las marcas que escribe outage.sh (outage_start_*.txt / outage_end_*.txt en OUT_DIR).
/// Devuelve null si no coinciden con el número de cortes esperado.
Future<List<CorteReal>?> cortesDesdeOutageSh(String dir, int t0Ms, int esperados) async {
  if (!await Directory(dir).exists()) {
    return null;
  }
  final desde = t0Ms / 1000 - 1;
  final inicios = await _marcas(dir, 'outage_start_', desde);
  final fines = await _marcas(dir, 'outage_end_', desde);
  if (inicios.length != esperados || fines.length != esperados) {
    return null;
  }
  return [
    for (var i = 0; i < esperados; i++) CorteReal((inicios[i] * 1000).round(), (fines[i] * 1000).round(), 'outage.sh')
  ];
}

Future<void> escribirResultados(Config c, List<FilaDoc> docs, ResumenCorrida r) async {
  await Directory(c.outDir).create(recursive: true);
  final csv = StringBuffer(
      'run_id,arch,dispositivo,doc_id,lote_id,hash,creado_ms,confirmado_ms,estado_cliente,intentos,verificacion\n');
  for (final d in docs) {
    csv.writeln([
      d.runId,
      d.arch,
      d.dispositivo,
      d.id,
      d.loteId,
      d.hash,
      d.creadoMs,
      d.confirmadoMs ?? '',
      d.estadoCliente,
      d.intentos,
      d.verificacion.name,
    ].join(','));
  }
  await File('${c.outDir}/docs_${c.runId}.csv').writeAsString(csv.toString());
  await File('${c.outDir}/resumen_${c.runId}.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(r.aJson()));
}
