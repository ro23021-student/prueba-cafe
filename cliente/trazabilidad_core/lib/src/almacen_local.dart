import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'evento_lote.dart';

enum EstadoSync { pendiente, sincronizado, rechazado }

/// Un evento guardado en el dispositivo junto con su estado de sincronización.
class RegistroLocal {
  final EventoLote evento;
  final EstadoSync estado;
  final int intentos;
  final String? ultimoError;
  final int creadoMs;
  final int? confirmadoMs;

  const RegistroLocal({
    required this.evento,
    required this.estado,
    required this.creadoMs,
    this.intentos = 0,
    this.ultimoError,
    this.confirmadoMs,
  });

  RegistroLocal copiar({
    EstadoSync? estado,
    int? intentos,
    String? ultimoError,
    bool borrarError = false,
    int? confirmadoMs,
  }) => RegistroLocal(
    evento: evento,
    estado: estado ?? this.estado,
    creadoMs: creadoMs,
    intentos: intentos ?? this.intentos,
    ultimoError: borrarError ? null : (ultimoError ?? this.ultimoError),
    confirmadoMs: confirmadoMs ?? this.confirmadoMs,
  );

  Map<String, dynamic> aJson() => {
    'evento': evento.aJson(),
    'estado': estado.name,
    'intentos': intentos,
    'ultimo_error': ultimoError,
    'creado_ms': creadoMs,
    'confirmado_ms': confirmadoMs,
  };

  factory RegistroLocal.desdeJson(Map<String, dynamic> j) => RegistroLocal(
    evento: EventoLote.desdeJson(Map<String, dynamic>.from(j['evento'] as Map)),
    estado: EstadoSync.values.byName(j['estado'] as String),
    intentos: j['intentos'] as int,
    ultimoError: j['ultimo_error'] as String?,
    creadoMs: j['creado_ms'] as int,
    confirmadoMs: j['confirmado_ms'] as int?,
  );
}

/// Contrato del almacenamiento local. La app y el client-sim solo conocen esta interfaz.
abstract class AlmacenLocal {
  /// Guarda un evento como pendiente. Devuelve false si ya existía (mismo id).
  Future<bool> guardar(EventoLote e);
  Future<List<RegistroLocal>> todos();
  Future<List<RegistroLocal>> pendientes();
  Future<void> actualizar(RegistroLocal r);

  /// Emite un valor cada vez que algo cambia (la UI se redibuja con esto).
  Stream<void> get cambios;
}

/// Implementación en memoria (pruebas y client-sim). Las subclases pueden persistir.
class AlmacenMemoria implements AlmacenLocal {
  final Map<String, RegistroLocal> _registros = {};
  final StreamController<void> _cambios = StreamController<void>.broadcast();

  /// Eventos (por identidad de objeto) que se editaron o eliminaron en este dispositivo.
  /// El motor de sincronización trabaja con una copia de los pendientes y, al terminar un intento,
  /// llama a [actualizar] con esa copia; sin este registro un intento en curso podría deshacer una
  /// edición o resucitar un evento eliminado. Solo afecta a eventos retirados con [eliminar] o
  /// [reemplazarNoSincronizado]; el resto de flujos (app, client-sim) no cambia.
  final Set<EventoLote> _retirados = Set<EventoLote>.identity();

  @override
  Stream<void> get cambios => _cambios.stream;

  /// Gancho para que una subclase escriba a disco.
  Future<void> _persistir() async {}

  @override
  Future<bool> guardar(EventoLote e) async {
    if (_registros.containsKey(e.id)) return false;
    _registros[e.id] = RegistroLocal(
      evento: e,
      estado: EstadoSync.pendiente,
      creadoMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistir();
    _cambios.add(null);
    return true;
  }

  @override
  Future<List<RegistroLocal>> todos() async {
    final l = _registros.values.toList()
      ..sort(
        (a, b) => b.evento.ts.compareTo(a.evento.ts),
      ); // más reciente primero
    return l;
  }

  @override
  Future<List<RegistroLocal>> pendientes() async {
    final l =
        _registros.values
            .where((r) => r.estado == EstadoSync.pendiente)
            .toList()
          ..sort((a, b) {
            final c = a.evento.ts.compareTo(
              b.evento.ts,
            ); // el más antiguo se envía primero
            return c != 0 ? c : a.evento.id.compareTo(b.evento.id);
          });
    return l;
  }

  @override
  Future<void> actualizar(RegistroLocal r) async {
    // Una copia vieja de un evento ya editado o eliminado no debe volver a escribirse.
    if (_retirados.contains(r.evento)) return;
    _registros[r.evento.id] = r;
    await _persistir();
    _cambios.add(null);
  }

  /// Quita un evento SOLO de este dispositivo. No avisa ni modifica nada en el servidor:
  /// si el evento ya estaba sincronizado, el servidor lo conserva (el historial es inmutable).
  /// Devuelve false si no existía.
  Future<bool> eliminar(String id) async {
    final quitado = _registros.remove(id);
    if (quitado == null) return false;
    _retirados.add(quitado.evento);
    await _persistir();
    _cambios.add(null);
    return true;
  }

  /// Sustituye un evento que el servidor nunca aceptó (pendiente o rechazado) por su versión
  /// corregida, que queda como pendiente con los intentos y el error reiniciados. Si el id cambia,
  /// el registro anterior desaparece. Todo se guarda en una sola escritura.
  /// Devuelve false si el evento no existe, ya está sincronizado, o el id nuevo choca con otro
  /// registro distinto.
  Future<bool> reemplazarNoSincronizado(
    String idAnterior,
    EventoLote nuevo,
  ) async {
    final previo = _registros[idAnterior];
    if (previo == null || previo.estado == EstadoSync.sincronizado) {
      return false;
    }
    if (nuevo.id != idAnterior && _registros.containsKey(nuevo.id)) {
      return false;
    }
    _registros.remove(idAnterior);
    _retirados.add(previo.evento);
    _registros[nuevo.id] = RegistroLocal(
      evento: nuevo,
      estado: EstadoSync.pendiente,
      creadoMs: previo.creadoMs,
    );
    await _persistir();
    _cambios.add(null);
    return true;
  }
}

/// Persiste todo en un archivo JSON (escritura atómica: temporal + rename).
/// Suficiente para la cola de un dispositivo; el cifrado se añade en una etapa posterior.
class AlmacenArchivoJson extends AlmacenMemoria {
  final File _archivo;
  AlmacenArchivoJson._(this._archivo);

  static Future<AlmacenArchivoJson> abrir(File archivo) async {
    final a = AlmacenArchivoJson._(archivo);
    if (await archivo.exists()) {
      final texto = await archivo.readAsString();
      if (texto.trim().isNotEmpty) {
        final lista = jsonDecode(texto) as List;
        for (final x in lista) {
          final r = RegistroLocal.desdeJson(
            Map<String, dynamic>.from(x as Map),
          );
          a._registros[r.evento.id] = r;
        }
      }
    }
    return a;
  }

  @override
  Future<void> _persistir() async {
    final tmp = File('${_archivo.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(_registros.values.map((r) => r.aJson()).toList()),
      flush: true,
    );
    await tmp.rename(_archivo.path);
  }
}

/// Cola local CIFRADA en reposo (AES-256-GCM, Fase 3 §3.4.3). El archivo guarda nonce + texto cifrado + MAC:
/// sin la clave no se lee nada y cualquier alteración se detecta al abrir. La clave (32 bytes) la entrega
/// quien llama; la app la guarda en el almacén seguro del sistema (Keystore/Keychain).
class AlmacenArchivoCifrado extends AlmacenMemoria {
  static const _largoNonce = 12;
  static const _largoMac = 16;
  static final AesGcm _aes = AesGcm.with256bits();

  final File _archivo;
  final SecretKey _clave;
  Future<void> _cola = Future<void>.value();

  AlmacenArchivoCifrado._(this._archivo, this._clave);

  /// Lanza [StateError] si el archivo existe pero no se puede descifrar (clave incorrecta o archivo alterado).
  static Future<AlmacenArchivoCifrado> abrir(
    File archivo,
    List<int> clave,
  ) async {
    if (clave.length != 32)
      throw ArgumentError('La clave AES-256 debe tener 32 bytes');
    final a = AlmacenArchivoCifrado._(
      archivo,
      SecretKey(List<int>.from(clave)),
    );
    if (await archivo.exists()) {
      final bytes = await archivo.readAsBytes();
      if (bytes.isNotEmpty) {
        final List<int> plano;
        try {
          final caja = SecretBox.fromConcatenation(
            bytes,
            nonceLength: _largoNonce,
            macLength: _largoMac,
          );
          plano = await _aes.decrypt(caja, secretKey: a._clave);
        } catch (_) {
          throw StateError(
            'No se pudo descifrar la cola local (clave incorrecta o archivo alterado)',
          );
        }
        final lista = jsonDecode(utf8.decode(plano)) as List;
        for (final x in lista) {
          final r = RegistroLocal.desdeJson(
            Map<String, dynamic>.from(x as Map),
          );
          a._registros[r.evento.id] = r;
        }
      }
    }
    return a;
  }

  /// Las escrituras se encolan: así dos cambios seguidos nunca pisan el mismo archivo temporal.
  @override
  Future<void> _persistir() {
    final instantanea = jsonEncode(
      _registros.values.map((r) => r.aJson()).toList(),
    );
    final p = _cola.then((_) => _escribir(instantanea));
    _cola = p.catchError((Object _) {});
    return p;
  }

  Future<void> _escribir(String json) async {
    final caja = await _aes.encrypt(
      utf8.encode(json),
      secretKey: _clave,
    ); // nonce aleatorio nuevo en cada escritura
    final tmp = File('${_archivo.path}.tmp');
    await tmp.writeAsBytes(caja.concatenation(), flush: true);
    await tmp.rename(_archivo.path);
  }
}

/// Pasa los registros de una cola antigua en JSON plano a otro almacén (p. ej. el cifrado).
/// Devuelve cuántos registros copió. Quien llama borra el archivo plano después.
Future<int> importarDesdeJsonPlano(File plano, AlmacenLocal destino) async {
  final origen = await AlmacenArchivoJson.abrir(plano);
  final todos = await origen.todos();
  for (final r in todos) {
    await destino.actualizar(r);
  }
  return todos.length;
}
