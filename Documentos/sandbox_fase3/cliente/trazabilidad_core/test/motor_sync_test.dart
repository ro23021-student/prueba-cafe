import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';

EventoLote ev(int ts) => EventoLote.crear(
  loteId: 'L-1',
  cooperativaId: 'C1',
  etapa: Etapa.recoleccion,
  owner: 'u',
  ts: ts,
);

void main() {
  late AlmacenMemoria almacen;
  setUp(() => almacen = AlmacenMemoria());

  MotorSync motor(http.Client c) =>
      MotorSync(almacen, ApiCliente('http://x:8080', cliente: c));

  test('envía los pendientes y los marca sincronizados', () async {
    final m = motor(MockClient((r) async => http.Response('{"ok":true}', 201)));
    await almacen.guardar(ev(1));
    expect(await m.sincronizarAhora(), isTrue);
    expect((await almacen.todos()).single.estado, EstadoSync.sincronizado);
  });

  test('sin red queda pendiente y, al volver, se envía una sola vez', () async {
    var hayRed = false;
    final recibidos = <String>[];
    final m = motor(
      MockClient((r) async {
        if (!hayRed) throw http.ClientException('sin red');
        recibidos.add(jsonDecode(r.body)['lote_id'] as String);
        return http.Response('{"ok":true}', 201);
      }),
    );
    await almacen.guardar(ev(1));
    expect(await m.sincronizarAhora(), isFalse);
    final r = (await almacen.pendientes()).single;
    expect(r.intentos, 1);
    expect(m.estado.ultimoError, isNotNull);

    hayRed = true;
    expect(await m.sincronizarAhora(), isTrue);
    expect(await almacen.pendientes(), isEmpty);
    expect(recibidos.length, 1);
  });

  test('422 -> rechazado y no se reintenta', () async {
    var llamadas = 0;
    final m = motor(
      MockClient((r) async {
        llamadas++;
        return http.Response('{"error":"Etapa invalida"}', 422);
      }),
    );
    await almacen.guardar(ev(1));
    await m.sincronizarAhora();
    await m.sincronizarAhora();
    final reg = (await almacen.todos()).single;
    expect(reg.estado, EstadoSync.rechazado);
    expect(reg.ultimoError, contains('Etapa invalida'));
    expect(llamadas, 1);
  });

  test('200 (duplicado) cuenta como éxito', () async {
    final m = motor(
      MockClient((r) async => http.Response('{"duplicado":true}', 200)),
    );
    await almacen.guardar(ev(1));
    await m.sincronizarAhora();
    expect((await almacen.todos()).single.estado, EstadoSync.sincronizado);
  });

  test('guardar dos veces el mismo evento no duplica la cola', () async {
    expect(await almacen.guardar(ev(7)), isTrue);
    expect(await almacen.guardar(ev(7)), isFalse);
    expect((await almacen.todos()).length, 1);
  });

  test('envía en orden cronológico', () async {
    final orden = <int>[];
    final m = motor(
      MockClient((r) async {
        orden.add(jsonDecode(r.body)['ts'] as int);
        return http.Response('{"ok":true}', 201);
      }),
    );
    await almacen.guardar(ev(30));
    await almacen.guardar(ev(10));
    await almacen.guardar(ev(20));
    await m.sincronizarAhora();
    expect(orden, [10, 20, 30]);
  });

  test('despertar fuerza un envío inmediato al recuperar la red', () async {
    var hayRed = false;
    final m = motor(
      MockClient((r) async {
        if (!hayRed) throw http.ClientException('sin red');
        return http.Response('{"ok":true}', 201);
      }),
    );
    await almacen.guardar(ev(1));
    m.iniciar();

    m.despertar();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect((await almacen.todos()).single.estado, EstadoSync.pendiente);

    hayRed = true;
    m.despertar();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect((await almacen.todos()).single.estado, EstadoSync.sincronizado);
    m.detener();
  });
}
