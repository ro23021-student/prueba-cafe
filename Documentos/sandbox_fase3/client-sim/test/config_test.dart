import 'package:client_sim/client_sim.dart';
import 'package:test/test.dart';

void main() {
  test('valores por defecto = los del docker-compose / Fase 3', () {
    final c = Config.desdeEntorno({});
    expect(c.dispositivos, 10);
    expect(c.runSegundos, 300);
    expect(c.calentamientoS, 30);
    expect(c.medicionS, 240);
    expect(c.drenajeS, 120);
    expect(c.cortes.map((k) => [k.inicioS, k.duracionS]), [
      [60, 30],
      [180, 30],
    ]);
    expect(c.modoCortes, 'self');
  });

  test('parsea el plan de cortes y lo ordena', () {
    final p = parsearPlanCortes('180:30, 60:30');
    expect(p.first.inicioS, 60);
    expect(p.last.finS, 210);
    expect(parsearPlanCortes(''), isEmpty);
  });

  test('rechaza planes y parámetros inválidos', () {
    expect(() => parsearPlanCortes('60'), throwsFormatException);
    expect(() => parsearPlanCortes('60:0'), throwsFormatException);
    expect(() => parsearPlanCortes('10:30,20:30'), throwsFormatException); // solapados
    expect(() => Config.desdeEntorno({'DEVICES': '0'}), throwsFormatException);
    expect(() => Config.desdeEntorno({'DEVICES': 'x'}), throwsFormatException);
    expect(() => Config.desdeEntorno({'OUTAGE_MODE': 'otro'}), throwsFormatException);
    expect(() => Config.desdeEntorno({'RUN_SECONDS': '100'}), throwsFormatException); // 30+240 > 100
    expect(() => Config.desdeEntorno({'RUN_SECONDS': '300', 'OUTAGE_PLAN': '290:30'}), throwsFormatException);
  });

  test('credenciales de la API: opcionales, pero siempre en pareja', () {
    expect(Config.desdeEntorno({}).apiUser, isNull);
    final c = Config.desdeEntorno({'API_USER': ' sim ', 'API_PASS': 'abc'});
    expect(c.apiUser, 'sim');
    expect(c.apiPass, 'abc');
    expect(c.aJson().containsValue('abc'), isFalse); // la clave no se vuelca a los resultados
    expect(() => Config.desdeEntorno({'API_USER': 'sim'}), throwsFormatException);
    expect(() => Config.desdeEntorno({'API_PASS': 'abc'}), throwsFormatException);
  });
}
