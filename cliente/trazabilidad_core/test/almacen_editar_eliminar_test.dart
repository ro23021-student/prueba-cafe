import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';

EventoLote ev(
  int ts, {
  String lote = 'L-1',
  Etapa etapa = Etapa.recoleccion,
  Map<String, dynamic> extra = const {},
}) => EventoLote.crear(
  loteId: lote,
  cooperativaId: 'C1',
  etapa: etapa,
  owner: 'u',
  ts: ts,
  extra: extra,
);

List<int> clave() {
  final r = Random(7);
  return List<int>.generate(32, (_) => r.nextInt(256));
}

void main() {
  group('eliminar', () {
    test('quita el evento, avisa del cambio y devuelve false si no existe', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1));
      var avisos = 0;
      final sub = a.cambios.listen((_) => avisos++);

      expect(await a.eliminar('L-1:1'), isTrue);
      expect(await a.todos(), isEmpty);
      expect(await a.eliminar('L-1:1'), isFalse);

      await Future<void>.delayed(Duration.zero);
      expect(avisos, 1); // solo el borrado real emite cambio
      await sub.cancel();
    });

    test('también quita un evento ya sincronizado (solo del dispositivo)', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1));
      final r = (await a.pendientes()).single;
      await a.actualizar(r.copiar(estado: EstadoSync.sincronizado));

      expect(await a.eliminar('L-1:1'), isTrue);
      expect(await a.todos(), isEmpty);
    });

    test('un intento de sincronización en curso no resucita el evento eliminado', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1));
      final copiaDelMotor = (await a.pendientes()).single;

      await a.eliminar('L-1:1');
      // El motor termina su intento y guarda su copia vieja.
      await a.actualizar(
        copiaDelMotor.copiar(estado: EstadoSync.sincronizado, intentos: 1),
      );

      expect(await a.todos(), isEmpty);
    });

    test('el borrado se conserva en la cola cifrada al reabrirla', () async {
      final dir = Directory.systemTemp.createTempSync('cola_eliminar_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/cola.enc');

      final a = await AlmacenArchivoCifrado.abrir(f, clave());
      await a.guardar(ev(1));
      await a.guardar(ev(2));
      await a.eliminar('L-1:1');

      final b = await AlmacenArchivoCifrado.abrir(f, clave());
      final ids = (await b.todos()).map((r) => r.evento.id).toList();
      expect(ids, ['L-1:2']);
    });
  });

  group('reemplazarNoSincronizado', () {
    test('con el mismo id deja el evento nuevo como pendiente y reinicia intentos y error', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1, extra: {'peso_kg': 10}));
      final r = (await a.pendientes()).single;
      await a.actualizar(
        r.copiar(
          estado: EstadoSync.rechazado,
          intentos: 3,
          ultimoError: 'peso invalido',
        ),
      );

      final nuevo = ev(1, etapa: Etapa.secado, extra: {'peso_kg': 12.5});
      expect(await a.reemplazarNoSincronizado('L-1:1', nuevo), isTrue);

      final lista = await a.todos();
      expect(lista, hasLength(1));
      final x = lista.single;
      expect(x.estado, EstadoSync.pendiente);
      expect(x.intentos, 0);
      expect(x.ultimoError, isNull);
      expect(x.evento.etapa, Etapa.secado);
      expect(x.evento.extra['peso_kg'], 12.5);
      expect(x.creadoMs, r.creadoMs); // se conserva cuándo se creó el registro
    });

    test('si el id cambia, el registro anterior desaparece', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1));

      expect(await a.reemplazarNoSincronizado('L-1:1', ev(1, lote: 'L-2')), isTrue);

      final ids = (await a.todos()).map((r) => r.evento.id).toList();
      expect(ids, ['L-2:1']);
    });

    test('no reemplaza un evento ya sincronizado', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1));
      final r = (await a.pendientes()).single;
      await a.actualizar(r.copiar(estado: EstadoSync.sincronizado));

      expect(
        await a.reemplazarNoSincronizado('L-1:1', ev(1, etapa: Etapa.despacho)),
        isFalse,
      );
      final x = (await a.todos()).single;
      expect(x.estado, EstadoSync.sincronizado);
      expect(x.evento.etapa, Etapa.recoleccion);
    });

    test('no reemplaza un evento que no existe', () async {
      final a = AlmacenMemoria();
      expect(await a.reemplazarNoSincronizado('L-9:9', ev(9, lote: 'L-9')), isFalse);
      expect(await a.todos(), isEmpty);
    });

    test('si el id nuevo choca con otro evento, no cambia nada', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1));
      await a.guardar(ev(1, lote: 'L-2'));

      expect(await a.reemplazarNoSincronizado('L-1:1', ev(1, lote: 'L-2')), isFalse);
      final ids = (await a.todos()).map((r) => r.evento.id).toSet();
      expect(ids, {'L-1:1', 'L-2:1'});
    });

    test('un intento de sincronización en curso no deshace la edición', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1, extra: {'peso_kg': 10}));
      final copiaDelMotor = (await a.pendientes()).single;

      await a.reemplazarNoSincronizado('L-1:1', ev(1, extra: {'peso_kg': 99}));
      // El motor termina un intento fallido y guarda su copia vieja.
      await a.actualizar(
        copiaDelMotor.copiar(intentos: 1, ultimoError: 'tiempo agotado'),
      );

      final x = (await a.todos()).single;
      expect(x.evento.extra['peso_kg'], 99);
      expect(x.intentos, 0);
      expect(x.ultimoError, isNull);
    });

    test('una edición que cambia el id tampoco deja volver al registro viejo', () async {
      final a = AlmacenMemoria();
      await a.guardar(ev(1));
      final copiaDelMotor = (await a.pendientes()).single;

      await a.reemplazarNoSincronizado('L-1:1', ev(1, lote: 'L-2'));
      await a.actualizar(copiaDelMotor.copiar(intentos: 1));

      final ids = (await a.todos()).map((r) => r.evento.id).toList();
      expect(ids, ['L-2:1']);
    });

    test('la edición se conserva en la cola cifrada al reabrirla', () async {
      final dir = Directory.systemTemp.createTempSync('cola_editar_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/cola.enc');

      final a = await AlmacenArchivoCifrado.abrir(f, clave());
      await a.guardar(ev(1));
      await a.reemplazarNoSincronizado('L-1:1', ev(1, etapa: Etapa.beneficio));

      final b = await AlmacenArchivoCifrado.abrir(f, clave());
      final x = (await b.todos()).single;
      expect(x.evento.etapa, Etapa.beneficio);
      expect(x.estado, EstadoSync.pendiente);
    });
  });

  group('compatibilidad con el flujo existente', () {
    test('actualizar sigue insertando registros nuevos y sobrescribiendo los existentes', () async {
      final a = AlmacenMemoria();
      final r = RegistroLocal(
        evento: ev(5),
        estado: EstadoSync.sincronizado,
        creadoMs: 1,
      );
      await a.actualizar(r); // inserta (así lo usa importarDesdeJsonPlano)
      expect((await a.todos()).single.estado, EstadoSync.sincronizado);

      await a.actualizar(r.copiar(intentos: 2));
      expect((await a.todos()).single.intentos, 2);
    });
  });
}
