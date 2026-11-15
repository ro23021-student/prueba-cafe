import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'evento_lote.dart';

enum ResultadoEnvio { creado, duplicado }

/// Fallo transitorio (sin red, timeout, 5xx): se reintenta más tarde.
class ErrorRed implements Exception {
  final String mensaje;
  const ErrorRed(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Sin sesión válida (HTTP 401, credenciales incorrectas o token vencido que no se pudo renovar).
/// Es un [ErrorRed] a propósito: el evento NO se pierde ni se marca como rechazado, queda pendiente
/// hasta que el usuario inicie sesión de nuevo.
class ErrorSesion extends ErrorRed {
  const ErrorSesion(super.mensaje);
}

/// Rechazo definitivo del servidor (4xx): reintentar no sirve.
class ErrorRechazado implements Exception {
  final int codigo;
  final String mensaje;
  const ErrorRechazado(this.codigo, this.mensaje);
  @override
  String toString() => 'HTTP $codigo: $mensaje';
}

/// Cliente de la API Rust (POST /v1/eventos, GET /v1/lotes/:id, GET /health).
/// La app nunca habla directo con CouchDB: siempre pasa por el backend.
///
/// Autenticación: si se dan credenciales, el cliente inicia sesión (POST /auth/login) la primera vez que
/// la necesita, guarda el JWT y lo renueva solo cuando el servidor responde 401 (un reintento).
class ApiCliente {
  String base;
  String? token; // JWT de la sesión actual
  String?
  cooperativa; // Cooperativa del usuario autenticado (null = sin restricción)
  String? _usuario;
  String? _clave;
  final Duration timeout;
  final http.Client _http;

  ApiCliente(
    this.base, {
    http.Client? cliente,
    this.token,
    this.timeout = const Duration(seconds: 5),
    String? usuario,
    String? clave,
  }) : _usuario = usuario,
       _clave = clave,
       _http = cliente ?? http.Client();

  bool get tieneCredenciales => _usuario != null && _clave != null;
  String? get usuario => _usuario;

  /// Cambia las credenciales; el próximo envío inicia sesión de nuevo.
  void usarCredenciales(String usuario, String clave) {
    _usuario = usuario;
    _clave = clave;
    token = null;
    cooperativa = null;
  }

  void cerrarSesion() {
    _usuario = null;
    _clave = null;
    token = null;
    cooperativa = null;
  }

  /// Inicia sesión ahora (para validar usuario y clave desde la pantalla). Devuelve el rol del usuario.
  Future<String> iniciarSesion(String usuario, String clave) {
    usarCredenciales(usuario, clave);
    return _proteger(_login);
  }

  Future<String> _login() async {
    final r = await _http.post(
      _uri('/auth/login'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'user': _usuario, 'pass': _clave}),
    );
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map;
      token = j['token'] as String;
      cooperativa = j['cooperativa'] as String?;
      return (j['rol'] as String?) ?? '';
    }
    token = null;
    cooperativa = null;
    if (r.statusCode >= 500 || r.statusCode == 408 || r.statusCode == 429) {
      throw ErrorRed('Servidor no disponible (HTTP ${r.statusCode})');
    }
    throw ErrorSesion(
      r.statusCode == 401
          ? 'Usuario o clave incorrectos'
          : 'No se pudo iniciar sesión (HTTP ${r.statusCode})',
    );
  }

  /// Envía una petición protegida: inicia sesión si hace falta y, ante un 401, renueva el token una vez.
  Future<http.Response> _autenticado(
    Future<http.Response> Function() enviar,
  ) async {
    if (token == null && tieneCredenciales) await _login();
    var r = await enviar();
    if (r.statusCode == 401) {
      if (!tieneCredenciales)
        throw const ErrorSesion('Falta iniciar sesión (HTTP 401)');
      await _login();
      r = await enviar();
      if (r.statusCode == 401)
        throw const ErrorSesion('El servidor rechazó la sesión (HTTP 401)');
    }
    return r;
  }

  Uri _uri(String ruta) =>
      Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$ruta');

  Map<String, String> get _cabeceras => {
    'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  Future<T> _proteger<T>(Future<T> Function() f) async {
    try {
      return await f().timeout(timeout);
    } on ErrorRechazado {
      rethrow;
    } on ErrorRed {
      rethrow;
    } on TimeoutException {
      throw const ErrorRed('Tiempo de espera agotado');
    } on http.ClientException catch (e) {
      throw ErrorRed('Sin conexión: ${e.message}');
    } on FormatException catch (e) {
      throw ErrorRed('Respuesta ilegible: ${e.message}');
    }
  }

  String _mensaje(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return r.body.isEmpty ? 'sin detalle' : r.body;
  }

  /// 201 -> creado; 200 -> duplicado (ya estaba: también cuenta como éxito).
  Future<ResultadoEnvio> enviarEvento(EventoLote e) => _proteger(() async {
    final r = await _autenticado(
      () => _http.post(
        _uri('/v1/eventos'),
        headers: _cabeceras,
        body: jsonEncode(e.aJson()),
      ),
    );
    if (r.statusCode == 201) return ResultadoEnvio.creado;
    if (r.statusCode == 200) return ResultadoEnvio.duplicado;
    if (r.statusCode >= 500 || r.statusCode == 408 || r.statusCode == 429) {
      throw ErrorRed('Servidor no disponible (HTTP ${r.statusCode})');
    }
    throw ErrorRechazado(r.statusCode, _mensaje(r));
  });

  Future<List<EventoLote>> consultarLote(String loteId) => _proteger(() async {
    final r = await _autenticado(
      () => _http.get(
        _uri('/v1/lotes/${Uri.encodeComponent(loteId)}'),
        headers: _cabeceras,
      ),
    );
    if (r.statusCode >= 500)
      throw ErrorRed('Servidor no disponible (HTTP ${r.statusCode})');
    if (r.statusCode != 200) throw ErrorRechazado(r.statusCode, _mensaje(r));
    final lista = (jsonDecode(r.body)['eventos'] as List?) ?? const [];
    final out = <EventoLote>[];
    for (final x in lista) {
      try {
        out.add(EventoLote.desdeJson(Map<String, dynamic>.from(x as Map)));
      } on ErrorValidacion {
        // se ignora un documento inválido, igual que hace el backend
      }
    }
    return out;
  });

  Future<bool> salud() async {
    try {
      final r = await _http.get(_uri('/health')).timeout(timeout);
      return r.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  void cerrar() => _http.close();
}
