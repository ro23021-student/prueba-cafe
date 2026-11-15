import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Error de validación del dominio (equivale a ErrorDominio::Invalido en Rust).
class ErrorValidacion implements Exception {
  final String mensaje;
  const ErrorValidacion(this.mensaje);
  @override
  String toString() => mensaje;
}

enum Etapa {
  recoleccion,
  beneficio,
  secado,
  almacen,
  despacho;

  static Etapa parse(String? s) {
    for (final e in Etapa.values) {
      if (e.name == s) return e;
    }
    throw const ErrorValidacion('Etapa invalida');
  }
}

/// Un evento en la cadena de trazabilidad de un lote de café.
/// Mismas reglas que backend-rust/src/domain/evento.rs: campos conocidos
/// validados y el resto (`extra`) se conserva tal cual.
class EventoLote {
  static const tipo = 'evento_lote';
  static const _conocidos = {
    'type',
    'lote_id',
    'cooperativa_id',
    'etapa',
    'ts',
    'owner',
  };

  final String loteId;
  final String cooperativaId;
  final Etapa etapa;
  final int ts; // epoch en segundos
  final String owner;
  final Map<String, dynamic> extra;

  const EventoLote._(
    this.loteId,
    this.cooperativaId,
    this.etapa,
    this.ts,
    this.owner,
    this.extra,
  );

  /// Crea un evento nuevo (ts = ahora, en segundos) validando igual que el servidor.
  factory EventoLote.crear({
    required String loteId,
    required String cooperativaId,
    required Etapa etapa,
    required String owner,
    int? ts,
    Map<String, dynamic> extra = const {},
  }) {
    return EventoLote.desdeJson({
      ...extra, // primero extra, para que nunca pise los campos conocidos
      'type': tipo,
      'lote_id': loteId,
      'cooperativa_id': cooperativaId,
      'etapa': etapa.name,
      'ts': ts ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'owner': owner,
    });
  }

  /// Construye y valida desde JSON (sirve también para documentos leídos del servidor).
  factory EventoLote.desdeJson(Map<String, dynamic> j) {
    for (final c in _conocidos) {
      if (!j.containsKey(c)) throw ErrorValidacion('Campo obligatorio: $c');
    }
    if (j['type'] != tipo) throw const ErrorValidacion('type debe ser "$tipo"');
    String texto(String k) {
      final v = j[k];
      if (v is String && v.trim().isNotEmpty) return v;
      throw ErrorValidacion('$k debe ser texto no vacio');
    }

    final ts = j['ts'];
    if (ts is! int)
      throw const ErrorValidacion('ts debe ser un entero (epoch)');
    final e = j['etapa'];
    return EventoLote._(
      texto('lote_id'),
      texto('cooperativa_id'),
      Etapa.parse(e is String ? e : null),
      ts,
      texto('owner'),
      {
        for (final x in j.entries)
          if (!_conocidos.contains(x.key) && !x.key.startsWith('_'))
            x.key: x.value,
      },
    );
  }

  /// Identificador determinista: reintentar el mismo evento produce el mismo _id (idempotencia).
  String get id => '$loteId:$ts';

  Map<String, dynamic> aJson() => {
    ...extra,
    'type': tipo,
    'lote_id': loteId,
    'cooperativa_id': cooperativaId,
    'etapa': etapa.name,
    'ts': ts,
    'owner': owner,
  };

  /// SHA-256 del contenido canónico (claves ordenadas): sirve para verificar integridad
  /// cliente vs. servidor (VD2 de la Fase 3).
  String get hash =>
      sha256.convert(utf8.encode(jsonEncode(_canonico(aJson())))).toString();

  static Object? _canonico(Object? v) {
    if (v is Map) {
      final claves = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in claves) k: _canonico(v[k])};
    }
    if (v is List) return v.map(_canonico).toList();
    return v;
  }
}
