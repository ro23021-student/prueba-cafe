import 'dart:async';
import 'dart:convert';
import 'dart:math' as m;
import 'package:trazabilidad_core/trazabilidad_core.dart';

/// Registro de un documento generado por un dispositivo (lo que el cliente "sabe" que creó).
class DocGenerado {
  final int dispositivo;
  final String id;
  final String loteId;
  final String hash;
  final int creadoMs;
  const DocGenerado(this.dispositivo, this.id, this.loteId, this.hash, this.creadoMs);
}

/// Un dispositivo simulado: usa el mismo almacén, API y motor de sincronización que la app Flutter.
/// Carga de trabajo (Tabla 3.6 de la Fase 3): intervalo exponencial, 70 % creación,
/// 20 % actualización de un lote existente y 10 % lectura; documentos de ~1,2 KB.
class DispositivoSim {
  final int indice;
  final int semilla;
  final double intervaloMedioS;
  final int docBytes;
  final AlmacenMemoria almacen;
  final ApiCliente api;
  final MotorSync motor;

  final m.Random _rng;
  final List<DocGenerado> generados = [];
  final List<String> _lotes = [];
  final Map<String, int> _ultimoTs = {};
  final Map<String, int> _etapaIdx = {};
  int lecturasOk = 0;
  int lecturasFallidas = 0;
  int _nLotes = 0;

  DispositivoSim({
    required this.indice,
    required this.semilla,
    required this.intervaloMedioS,
    required this.docBytes,
    required this.almacen,
    required this.api,
    required this.motor,
  }) : _rng = m.Random(semilla * 1000003 + indice);

  Future<int> pendientes() async => (await almacen.pendientes()).length;

  /// Genera acciones hasta que `debeParar()` sea verdadero.
  Future<void> ejecutar(bool Function() debeParar) async {
    while (!debeParar()) {
      final espera = -intervaloMedioS * m.log(1 - _rng.nextDouble());
      await Future<void>.delayed(Duration(microseconds: (espera * 1e6).round()));
      if (debeParar()) {
        break;
      }
      await _accion();
    }
  }

  Future<void> _accion() async {
    final u = _rng.nextDouble();
    if (_lotes.isEmpty || u < 0.7) {
      await _crear();
    } else if (u < 0.9) {
      await _actualizar();
    } else {
      await _leer();
    }
  }

  Future<void> _crear() async {
    final lote = 'S$semilla-D$indice-L${_nLotes++}';
    _lotes.add(lote);
    _etapaIdx[lote] = 0;
    await _escribir(lote, Etapa.values.first);
  }

  Future<void> _actualizar() async {
    final lote = _lotes[_rng.nextInt(_lotes.length)];
    final i = m.min((_etapaIdx[lote] ?? 0) + 1, Etapa.values.length - 1);
    _etapaIdx[lote] = i;
    await _escribir(lote, Etapa.values[i]);
  }

  Future<void> _leer() async {
    final lote = _lotes[_rng.nextInt(_lotes.length)];
    try {
      await api.consultarLote(lote);
      lecturasOk++;
    } on ErrorRed {
      lecturasFallidas++;
    } on ErrorRechazado {
      lecturasFallidas++;
    }
  }

  String _relleno(int n) {
    const alfabeto = 'abcdefghijklmnopqrstuvwxyz ';
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(alfabeto[_rng.nextInt(alfabeto.length)]);
    }
    return sb.toString();
  }

  Future<void> _escribir(String lote, Etapa etapa) async {
    final ahora = DateTime.now().millisecondsSinceEpoch;
    var ts = ahora ~/ 1000;
    final previo = _ultimoTs[lote];
    if (previo != null && ts <= previo) {
      ts = previo + 1; // el _id es lote:ts, así que dos eventos del mismo lote no pueden compartir segundo
    }
    _ultimoTs[lote] = ts;

    final extra = <String, dynamic>{
      'peso_kg': ((5 + _rng.nextDouble() * 95) * 100).round() / 100,
      'lat': ((13.80 + _rng.nextDouble() * 0.13) * 1000).round() / 1000,
      'lon': ((-89.85 + _rng.nextDouble() * 0.15) * 1000).round() / 1000,
    };
    EventoLote crear(Map<String, dynamic> x) => EventoLote.crear(
          loteId: lote,
          cooperativaId: 'SIM-COOP-${indice % 10}',
          etapa: etapa,
          owner: 'sim-d$indice',
          ts: ts,
          extra: x,
        );

    final base = crear(extra);
    final faltan = docBytes - utf8.encode(jsonEncode(base.aJson())).length - 12;
    final ev = faltan > 0 ? crear({...extra, 'notas': _relleno(faltan)}) : base;

    await almacen.guardar(ev);
    generados.add(DocGenerado(indice, ev.id, lote, ev.hash, ahora));
    // Igual que la app: guardar primero en local y luego intentar enviar.
    unawaited(motor.sincronizarAhora().catchError((Object _) => false));
  }
}
