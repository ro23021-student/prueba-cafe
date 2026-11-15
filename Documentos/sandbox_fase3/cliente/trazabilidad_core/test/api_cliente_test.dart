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

/// Servidor falso con login y rutas protegidas. `vigente` es el token que acepta en este momento.
class ServidorFalso {
  String vigente = 'tok-1';
  int logins = 0;
  int escrituras = 0;
  final List<String?> autorizaciones = [];
  String clave = 'secreta';

  MockClient get cliente => MockClient((r) async {
    if (r.url.path == '/auth/login') {
      logins++;
      final c = jsonDecode(r.body) as Map;
      if (c['pass'] != clave)
        return http.Response('{"error":"credenciales invalidas"}', 401);
      return http.Response(
        jsonEncode({'token': vigente, 'rol': 'tecnico', 'expires_in': 60}),
        200,
      );
    }
    autorizaciones.add(r.headers['authorization']);
    if (r.headers['authorization'] != 'Bearer $vigente')
      return http.Response('{"error":"token invalido"}', 401);
    if (r.url.path == '/v1/eventos') {
      escrituras++;
      return http.Response('{"ok":true}', 201);
    }
    return http.Response('{"lote_id":"L-1","eventos":[]}', 200);
  });
}

void main() {
  test(
    'inicia sesión la primera vez y envía el token en las siguientes peticiones',
    () async {
      final s = ServidorFalso();
      final api = ApiCliente(
        'http://x:8080',
        cliente: s.cliente,
        usuario: 'ana',
        clave: 'secreta',
      );
      expect(await api.enviarEvento(ev(1)), ResultadoEnvio.creado);
      expect(await api.enviarEvento(ev(2)), ResultadoEnvio.creado);
      expect(s.logins, 1);
      expect(s.autorizaciones, ['Bearer tok-1', 'Bearer tok-1']);
    },
  );

  test(
    'si el token vence, renueva la sesión y reintenta una sola vez',
    () async {
      final s = ServidorFalso();
      final api = ApiCliente(
        'http://x:8080',
        cliente: s.cliente,
        usuario: 'ana',
        clave: 'secreta',
      );
      await api.enviarEvento(ev(1));
      s.vigente = 'tok-2'; // el servidor ya no acepta tok-1
      expect(await api.enviarEvento(ev(2)), ResultadoEnvio.creado);
      expect(s.logins, 2);
      expect(api.token, 'tok-2');
    },
  );

  test(
    'clave incorrecta -> ErrorSesion (transitorio), no ErrorRechazado',
    () async {
      final s = ServidorFalso()..clave = 'otra';
      final api = ApiCliente(
        'http://x:8080',
        cliente: s.cliente,
        usuario: 'ana',
        clave: 'secreta',
      );
      await expectLater(api.enviarEvento(ev(1)), throwsA(isA<ErrorSesion>()));
      expect(s.escrituras, 0);
    },
  );

  test('sin credenciales y con 401 -> ErrorSesion', () async {
    final s = ServidorFalso();
    final api = ApiCliente('http://x:8080', cliente: s.cliente);
    await expectLater(api.consultarLote('L-1'), throwsA(isA<ErrorSesion>()));
  });

  test('iniciarSesion devuelve el rol y guarda el token', () async {
    final s = ServidorFalso();
    final api = ApiCliente('http://x:8080', cliente: s.cliente);
    expect(await api.iniciarSesion('ana', 'secreta'), 'tecnico');
    expect(api.token, 'tok-1');
    api.cerrarSesion();
    expect(api.token, isNull);
    expect(api.tieneCredenciales, isFalse);
  });

  test('403 (rol sin permiso) sí es un rechazo definitivo', () async {
    final api = ApiCliente(
      'http://x:8080',
      cliente: MockClient(
        (r) async => r.url.path == '/auth/login'
            ? http.Response('{"token":"t","rol":"auditor"}', 200)
            : http.Response(
                '{"error":"El rol auditor es de solo lectura."}',
                403,
              ),
      ),
      usuario: 'a',
      clave: 'b',
    );
    await expectLater(api.enviarEvento(ev(1)), throwsA(isA<ErrorRechazado>()));
  });

  test(
    'con la sesión caída los eventos quedan pendientes (no rechazados) y salen al iniciar sesión',
    () async {
      final s = ServidorFalso();
      final almacen = AlmacenMemoria();
      final api = ApiCliente(
        'http://x:8080',
        cliente: s.cliente,
      ); // aún sin login
      final motor = MotorSync(almacen, api);
      await almacen.guardar(ev(1));
      expect(await motor.sincronizarAhora(), isFalse);
      expect((await almacen.pendientes()).length, 1);
      await api.iniciarSesion('ana', 'secreta');
      expect(await motor.sincronizarAhora(), isTrue);
      expect(await almacen.pendientes(), isEmpty);
    },
  );

  test(
    'iniciarSesion guarda la cooperativa y la limpia al cerrar sesión',
    () async {
      final api = ApiCliente(
        'http://x:8080',
        cliente: MockClient(
          (r) async => r.url.path == '/auth/login'
              ? http.Response(
                  '{"token":"t","rol":"productor","cooperativa":"COOP-1","expires_in":60}',
                  200,
                )
              : http.Response('{"ok":true}', 200),
        ),
      );

      expect(await api.iniciarSesion('productor', 'clave'), 'productor');
      expect(api.cooperativa, 'COOP-1');

      api.cerrarSesion();
      expect(api.cooperativa, isNull);
    },
  );
}
