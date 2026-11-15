import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';

EventoLote ev(int ts, {String lote = 'LOTE-SECRETO'}) => EventoLote.crear(
  loteId: lote,
  cooperativaId: 'C1',
  etapa: Etapa.recoleccion,
  owner: 'u',
  ts: ts,
);

List<int> clave([int semilla = 1]) {
  final r = Random(semilla);
  return List<int>.generate(32, (_) => r.nextInt(256));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cola_cifrada_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('guarda, reabre con la misma clave y conserva el estado', () async {
    final f = File('${dir.path}/cola.enc');
    final a = await AlmacenArchivoCifrado.abrir(f, clave());
    await a.guardar(ev(1));
    await a.guardar(ev(2));
    final r = (await a.pendientes()).first;
    await a.actualizar(
      r.copiar(estado: EstadoSync.sincronizado, confirmadoMs: 5),
    );

    final b = await AlmacenArchivoCifrado.abrir(f, clave());
    expect((await b.todos()).length, 2);
    expect((await b.pendientes()).length, 1);
  });

  test('el archivo en disco no contiene texto legible', () async {
    final f = File('${dir.path}/cola.enc');
    final a = await AlmacenArchivoCifrado.abrir(f, clave());
    await a.guardar(ev(1));
    final crudo = String.fromCharCodes(await f.readAsBytes());
    expect(crudo.contains('LOTE-SECRETO'), isFalse);
    expect(crudo.contains('lote_id'), isFalse);
  });

  test('con otra clave o con el archivo alterado no abre', () async {
    final f = File('${dir.path}/cola.enc');
    final a = await AlmacenArchivoCifrado.abrir(f, clave(1));
    await a.guardar(ev(1));
    await expectLater(
      AlmacenArchivoCifrado.abrir(f, clave(2)),
      throwsStateError,
    );
    final bytes = await f.readAsBytes();
    bytes[bytes.length ~/ 2] ^= 0xFF;
    await f.writeAsBytes(bytes);
    await expectLater(
      AlmacenArchivoCifrado.abrir(f, clave(1)),
      throwsStateError,
    );
  });

  test('rechaza claves que no son de 32 bytes', () async {
    await expectLater(
      AlmacenArchivoCifrado.abrir(File('${dir.path}/x'), [1, 2, 3]),
      throwsArgumentError,
    );
  });

  test('escrituras concurrentes no corrompen el archivo', () async {
    final f = File('${dir.path}/cola.enc');
    final a = await AlmacenArchivoCifrado.abrir(f, clave());
    await Future.wait([
      for (var i = 0; i < 20; i++) a.guardar(ev(i + 1, lote: 'L$i')),
    ]);
    final b = await AlmacenArchivoCifrado.abrir(f, clave());
    expect((await b.todos()).length, 20);
  });

  test('importa una cola antigua en JSON plano', () async {
    final plano = File('${dir.path}/cola_eventos.json');
    final vieja = await AlmacenArchivoJson.abrir(plano);
    await vieja.guardar(ev(1));
    await vieja.guardar(ev(2));
    final destino = await AlmacenArchivoCifrado.abrir(
      File('${dir.path}/cola.enc'),
      clave(),
    );
    expect(await importarDesdeJsonPlano(plano, destino), 2);
    expect((await destino.todos()).length, 2);
  });
}
