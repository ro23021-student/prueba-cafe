import 'package:client_sim/client_sim.dart';
import 'package:test/test.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart' show EstadoSync;

FilaDoc doc(String id, int creado, int? confirmado, Verificacion v, {int intentos = 1}) => FilaDoc(
      runId: 'r',
      arch: 'treatment',
      dispositivo: 0,
      id: id,
      loteId: 'L',
      hash: 'h',
      creadoMs: creado,
      confirmadoMs: confirmado,
      estadoCliente: 'sincronizado',
      intentos: intentos,
      verificacion: v,
    );

void main() {
  const t0 = 1000000;
  final c = Config.desdeEntorno({}); // calentamiento 30 s, ventana 240 s
  const ini = t0 + 30000; // inicio de la ventana
  final corte = CorteReal(ini + 100000, ini + 130000, 'test');

  test('VD1, VD2 y VD3 con un documento perdido', () {
    final docs = [
      doc('A', ini + 1000, ini + 2000, Verificacion.ok),
      doc('B', ini + 5000, ini + 300000, Verificacion.ok, intentos: 3), // confirma fuera de la ventana
      doc('C', ini + 10000, ini + 11000, Verificacion.perdido),
    ];
    final r = calcularResumen(
        c: c, t0Ms: t0, docs: docs, cortes: [corte], finDrenajeMs: ini + 400000, lecturasOk: 0, lecturasFallidas: 0, lotesSinVerificar: 0);
    expect(r.generadosTotal, 3);
    expect(r.vd1DocsPorS, closeTo(1 / 240, 1e-9)); // solo A confirma dentro de la ventana
    expect(r.vd2Tfs, closeTo(1 - 2 / 3, 1e-9));
    expect(r.desglose['perdido'], 1);
    expect(r.vd3PorCorte.single, isNull); // C no está en el servidor: no convergió
    expect(r.intentosTotal, 5);
    expect(r.intentosFallidos, 2); // 5 intentos - 3 confirmaciones
  });

  test('VD3: tiempo hasta que el servidor tiene todo lo generado antes del fin del corte', () {
    final docs = [
      doc('A', ini + 1000, ini + 2000, Verificacion.ok),
      doc('B', ini + 5000, ini + 300000, Verificacion.ok),
    ];
    final r = calcularResumen(
        c: c, t0Ms: t0, docs: docs, cortes: [corte], finDrenajeMs: ini + 400000, lecturasOk: 0, lecturasFallidas: 0, lotesSinVerificar: 0);
    expect(r.vd3PorCorte.single, closeTo(170.0, 1e-9)); // (300000 - 130000) / 1000
    expect(r.vd2Tfs, 0.0);
    expect(r.vd3Mediana, closeTo(170.0, 1e-9));
  });

  test('clasificar cubre los cinco casos', () {
    Verificacion v(EstadoSync e, String? hs) => clasificar(estadoCliente: e, hashServidor: hs, hashCliente: 'h');
    expect(v(EstadoSync.sincronizado, 'h'), Verificacion.ok);
    expect(v(EstadoSync.sincronizado, 'otro'), Verificacion.corrupto);
    expect(v(EstadoSync.sincronizado, null), Verificacion.perdido);
    expect(v(EstadoSync.pendiente, null), Verificacion.noConvergio);
    expect(v(EstadoSync.rechazado, null), Verificacion.rechazado);
  });
}
