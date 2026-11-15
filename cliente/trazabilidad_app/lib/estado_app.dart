import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';

import 'ajustes.dart';
import 'boveda.dart';

/// Une el núcleo (almacén + API + motor de sync) con la interfaz.
/// Las pantallas escuchan este objeto y se redibujan cuando cambia algo.
class EstadoApp extends ChangeNotifier with WidgetsBindingObserver {
  final AlmacenLocal almacen;
  final ApiCliente api;
  final MotorSync motor;
  final Ajustes ajustes;
  final Boveda boveda;

  /// Mensaje que la pantalla de sincronización muestra una vez (p. ej. cola local irrecuperable).
  String? avisoInicio;

  /// Rol devuelto por el servidor en el último inicio de sesión correcto (tecnico, productor, auditor).
  String? rol;

  /// Cooperativa del usuario autenticado (null = sin restricción).
  String? cooperativa;

  /// Último estado de conectividad del dispositivo, para avisar en la pantalla de inicio.
  bool redDisponible = true;

  List<RegistroLocal> registros = [];
  late final StreamSubscription<void> _subAlmacen;
  late final StreamSubscription<EstadoMotor> _subMotor;
  late final StreamSubscription<List<ConnectivityResult>> _subRed;
  final Connectivity _conectividad = Connectivity();

  EstadoApp({
    required this.almacen,
    required this.api,
    required this.motor,
    required this.ajustes,
    required this.boveda,
    this.avisoInicio,
  }) {
    _subAlmacen = almacen.cambios.listen((_) => _recargar());
    _subMotor = motor.cambios.listen((_) => notifyListeners());
    _subRed = _conectividad.onConnectivityChanged.listen(
      _alCambiarRed,
      onError: (_) {},
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_comprobarRed());
    _recargar();
  }

  void _alCambiarRed(List<ConnectivityResult> resultados) {
    final hay = resultados.any((r) => r != ConnectivityResult.none);
    if (hay != redDisponible) {
      redDisponible = hay;
      notifyListeners();
    }
    if (hay && sesionIniciada) motor.despertar();
  }

  Future<void> _comprobarRed() async {
    try {
      final resultados = await _conectividad.checkConnectivity();
      final hay = resultados.any((r) => r != ConnectivityResult.none);
      if (hay != redDisponible) {
        redDisponible = hay;
        notifyListeners();
      }
    } catch (_) {
      // Si la plataforma no puede informar, se conserva el último valor.
    }
  }

  /// Al volver a primer plano se intenta sincronizar de inmediato
  /// (no se espera al siguiente ciclo del temporizador ni al backoff).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && sesionIniciada) motor.despertar();
  }

  Future<void> _recargar() async {
    registros = await almacen.todos();
    notifyListeners();
  }

  /// Guarda SIEMPRE en el dispositivo primero (funciona sin señal) y luego intenta sincronizar.
  /// Devuelve un mensaje de error de validación, o null si todo salió bien.
  Future<String?> registrar({
    required String loteId,
    required String cooperativaId,
    required Etapa etapa,
    required String owner,
    double? pesoKg,
    String? notas,
  }) async {
    final rolActual = rol;
    final usuarioActual = usuario;
    if (rolActual == null) return 'Inicia sesión para registrar.';
    if (rolActual == 'auditor') return 'El rol auditor es de solo lectura.';
    if (rolActual == 'productor' &&
        (usuarioActual == null || owner.trim() != usuarioActual)) {
      return 'Como productor, el responsable debe ser tu usuario'
          '${usuarioActual == null ? '' : ' ($usuarioActual)'}.';
    }
    if (cooperativa != null && cooperativaId.trim() != cooperativa) {
      return 'Tu usuario solo puede registrar en la cooperativa $cooperativa.';
    }

    final EventoLote evento;
    try {
      evento = EventoLote.crear(
        loteId: loteId.trim(),
        cooperativaId: cooperativaId.trim(),
        etapa: etapa,
        owner: owner.trim(),
        extra: {
          if (pesoKg != null) 'peso_kg': pesoKg,
          if (notas != null && notas.trim().isNotEmpty) 'notas': notas.trim(),
        },
      );
    } on ErrorValidacion catch (e) {
      return e.mensaje;
    }
    final nuevo = await almacen.guardar(evento);
    if (!nuevo) {
      return 'Ya registraste un evento de este lote en este mismo segundo.';
    }
    motor.despertar();
    return null;
  }

  /// Arranca el motor al entrar a la app (después del login obligatorio).
  void activarMotor() {
    motor.iniciar();
    motor.despertar();
  }

  void reintentarAhora() => motor.despertar();

  /// Cambia la URL de la API y la recuerda para la próxima vez que se abra la app.
  Future<void> cambiarUrl(String url) async {
    api.base = url.trim();
    ajustes.url = api.base;
    await ajustes.guardar();
    notifyListeners();
  }

  String? get usuario => api.usuario;
  bool get sesionIniciada => api.token != null;
  bool get soloLectura => rol == 'auditor';
  bool get esProductor => rol == 'productor';

  /// Valida usuario y clave contra el servidor. La clave NO se guarda en el dispositivo:
  /// se pide en cada arranque y solo vive en memoria mientras dura la sesión.
  /// Devuelve un mensaje de error o null si salió bien.
  Future<String?> iniciarSesion(String usuario, String clave) async {
    try {
      rol = await api.iniciarSesion(usuario.trim(), clave);
      cooperativa = api.cooperativa;
    } on ErrorSesion catch (e) {
      return e.mensaje;
    } on ErrorRed catch (e) {
      return 'No se pudo contactar al servidor: ${e.mensaje}';
    } on ErrorRechazado catch (e) {
      return e.toString();
    }
    ajustes.usuario = usuario.trim();
    await ajustes.guardar();
    try {
      // Migración: versiones anteriores guardaban la clave para auto-login.
      await boveda.borrarClaveUsuario();
    } catch (_) {}
    notifyListeners();
    motor.despertar();
    return null;
  }

  Future<void> cerrarSesion() async {
    motor.detener();
    api.cerrarSesion();
    rol = null;
    cooperativa = null;
    try {
      await boveda.borrarClaveUsuario();
    } catch (_) {}
    notifyListeners();
  }

  int get pendientes =>
      registros.where((r) => r.estado == EstadoSync.pendiente).length;
  int get rechazados =>
      registros.where((r) => r.estado == EstadoSync.rechazado).length;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subRed.cancel();
    _subAlmacen.cancel();
    _subMotor.cancel();
    motor.liberar();
    super.dispose();
  }
}
