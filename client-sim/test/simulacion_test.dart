import 'dart:convert';
import 'package:client_sim/client_sim.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Servidor en memoria que imita la API Rust: POST /v1/eventos (201/200) y GET /v1/lotes/:id.
class ServidorFalso {
  bool caido = false;
  final docs = <String, Map<String, dynamic>>{};

  late final MockClient cliente = MockClient((req) async {
    if (caido) {
      throw http.ClientException('sin red');
    }
    if (req.method == 'POST' && req.url.path == '/v1/eventos') {
      final j = jsonDecode(req.body) as Map<String, dynamic>;
      final id = '${j['lote_id']}:${j['ts']}';
      if (docs.containsKey(id)) {
        return http.Response('{"duplicado":true}', 200);
      }
      docs[id] = j;
      return http.Response('{"ok":true}', 201);
    }
    if (req.method == 'GET' && req.url.path.startsWith('/v1/lotes/')) {
      final lote = Uri.decodeComponent(req.url.path.substring('/v1/lotes/'.length));
      final eventos = docs.values.where((d) => d['lote_id'] == lote).toList();
      return http.Response(jsonEncode({'lote_id': lote, 'eventos': eventos}), 200);
    }
    return http.Response('no encontrado', 404);
  });
}

class RedFalsa implements ControladorRed {
  final ServidorFalso s;
  int cortes = 0;
  RedFalsa(this.s);
  @override
  String get fuente => 'test';
  @override
  Future<void> preparar() async {}
  @override
  Future<void> cortar() async {
    s.caido = true;
    cortes++;
  }

  @override
  Future<void> restaurar() async => s.caido = false;
  @override
  Future<void> quitarDegradacion() async => s.caido = false;
}

void main() {
  test('corrida completa con un corte: no se pierde ningún documento', () async {
    final servidor = ServidorFalso();
    final red = RedFalsa(servidor);
    final c = Config.desdeEntorno({
      'DEVICES': '3',
      'RUN_SECONDS': '8',
      'WARMUP_S': '1',
      'MEASURE_S': '5',
      'DRAIN_S': '20',
      'OUTAGE_PLAN': '3:2',
      'MEAN_INTERVAL_S': '0.3',
      'SYNC_BASE_S': '1',
      'SYNC_MAX_S': '2',
      'OUTAGE_MODE': 'self',
      'RUN_ID': 'prueba',
    });

    final r = await correrSimulacion(c, red: red, fabricaHttp: () => servidor.cliente);

    expect(red.cortes, 1);
    expect(r.docs, isNotEmpty);
    expect(servidor.docs.length, r.docs.length, reason: 'todo lo generado llegó al servidor');
    expect(r.resumen.vd2Tfs, 0.0);
    expect(r.resumen.desglose['ok'], r.docs.length);
    expect(r.resumen.cortes.length, 1);
    expect(r.resumen.vd3PorCorte.single, isNotNull);
    // Durante el corte hubo intentos fallidos, así que la tasa de error por intento es > 0.
    expect(r.resumen.tasaErrorPorIntento, greaterThan(0));
    // Los documentos tienen ~1,2 KB.
    final tam = utf8.encode(jsonEncode(servidor.docs.values.first)).length;
    expect(tam, inInclusiveRange(1000, 1300));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('si el servidor cambia el contenido, se detecta como corrupto', () async {
    final servidor = ServidorFalso();
    final c = Config.desdeEntorno({
      'DEVICES': '1',
      'RUN_SECONDS': '4',
      'WARMUP_S': '0',
      'MEASURE_S': '3',
      'DRAIN_S': '10',
      'OUTAGE_PLAN': '',
      'MEAN_INTERVAL_S': '0.3',
      'SYNC_BASE_S': '1',
      'SYNC_MAX_S': '2',
      'RUN_ID': 'corrupto',
    });
    // Cliente HTTP que altera el peso al guardar
    final alterador = MockClient((req) async {
      if (req.method == 'POST') {
        final j = jsonDecode(req.body) as Map<String, dynamic>;
        j['peso_kg'] = 999.0;
        return servidor.cliente.send(http.Request('POST', req.url)..body = jsonEncode(j)).then(http.Response.fromStream);
      }
      return servidor.cliente.get(req.url);
    });
    final r = await correrSimulacion(c, red: RedFalsa(servidor), fabricaHttp: () => alterador);
    expect(r.docs, isNotEmpty);
    expect(r.resumen.desglose['corrupto'], r.docs.length);
    expect(r.resumen.vd2Tfs, 1.0);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
