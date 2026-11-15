import 'package:test/test.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';

Map<String, dynamic> base() => {
  'type': 'evento_lote',
  'lote_id': 'L-1',
  'cooperativa_id': 'C1',
  'etapa': 'secado',
  'ts': 1700000000,
  'owner': 'u1',
  'peso_kg': 42.5,
};

void main() {
  test('acepta y conserva campos extra, id determinista', () {
    final e = EventoLote.desdeJson(base());
    expect(e.etapa, Etapa.secado);
    expect(e.extra['peso_kg'], 42.5);
    expect(e.aJson()['peso_kg'], 42.5);
    expect(e.id, 'L-1:1700000000');
  });

  test('rechaza etapa, type, ts y textos vacíos', () {
    for (final c in {
      'etapa': 'x',
      'type': 'otro',
      'ts': 'hoy',
      'owner': '  ',
    }.entries) {
      final d = base()..[c.key] = c.value;
      expect(
        () => EventoLote.desdeJson(d),
        throwsA(isA<ErrorValidacion>()),
        reason: c.key,
      );
    }
    final sinLote = base()..remove('lote_id');
    expect(
      () => EventoLote.desdeJson(sinLote),
      throwsA(isA<ErrorValidacion>()),
    );
  });

  test('ignora campos internos de CouchDB', () {
    final d = base()
      ..['_id'] = 'a'
      ..['_rev'] = '1-x';
    expect(EventoLote.desdeJson(d).extra.containsKey('_rev'), isFalse);
  });

  test('el hash no depende del orden de las claves', () {
    final a = EventoLote.desdeJson(base());
    final inv = Map.fromEntries(base().entries.toList().reversed);
    expect(EventoLote.desdeJson(inv).hash, a.hash);
  });

  test('crear: extra no puede pisar campos conocidos', () {
    final e = EventoLote.crear(
      loteId: 'L-2',
      cooperativaId: 'C1',
      etapa: Etapa.beneficio,
      owner: 'u',
      ts: 5,
      extra: {'owner': 'intruso'},
    );
    expect(e.owner, 'u');
  });
}
