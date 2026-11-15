import 'dart:async';
import 'almacen_local.dart';
import 'api_cliente.dart';

class EstadoMotor {
  final bool sincronizando;
  final int pendientes;
  final DateTime? ultimaSyncOk;
  final String? ultimoError;
  const EstadoMotor({
    this.sincronizando = false,
    this.pendientes = 0,
    this.ultimaSyncOk,
    this.ultimoError,
  });
}

/// Controla la sincronización con retry exponencial y límite opcional de intentos por evento.
class MotorSync {
  final AlmacenLocal _almacen;
  final ApiCliente api;
  final Duration intervaloBase;
  final Duration intervaloMaximo;
  final int? maxIntentos; // límite de intentos por evento (null = ilimitado)
  final StreamController<EstadoMotor> _ctrl =
      StreamController<EstadoMotor>.broadcast();
  EstadoMotor _estado = const EstadoMotor();
  Timer? _timer;
  bool _activo = false;
  bool _enCurso = false;
  late Duration _espera = intervaloBase;
  // Contador de intentos por evento id (en memoria, para esta corrida)
  final Map<String, int> _intentosPorEvento = {};

  MotorSync(
    this._almacen,
    this.api, {
    this.intervaloBase = const Duration(seconds: 5),
    this.intervaloMaximo = const Duration(seconds: 60),
    this.maxIntentos,
  }) : assert(maxIntentos == null || maxIntentos > 0);

  EstadoMotor get estado => _estado;
  Stream<EstadoMotor> get cambios => _ctrl.stream;

  void iniciar() {
    if (_activo) return;
    _activo = true;
    _espera = intervaloBase;
    _programar();
  }

  void detener() {
    _activo = false;
    _timer?.cancel();
  }

  void _programar() {
    _timer?.cancel();
    if (!_activo) return;
    _timer = Timer(_espera, () => unawaited(_ejecutarCiclo()));
  }

  Future<void> _ejecutarCiclo() async {
    var ok = false;
    try {
      ok = await sincronizarAhora();
    } catch (_) {
      ok = false;
    }
    final doble = _espera * 2;
    _espera = ok
        ? intervaloBase
        : (doble > intervaloMaximo ? intervaloMaximo : doble);
    _programar();
  }

  /// Fuerza un intento inmediato y reinicia el backoff. Se usa al recuperar red, al volver
  /// a primer plano, al iniciar sesión y al pulsar "Sincronizar ahora".
  void despertar() {
    _espera = intervaloBase;
    _timer?.cancel();
    if (!_activo) return;
    unawaited(_ejecutarCiclo());
  }

  /// Devuelve true si no hubo fallo de red (aunque haya habido rechazos).
  Future<bool> sincronizarAhora() async {
    if (_enCurso) return true;
    _enCurso = true;
    String? error;
    try {
      final pend = await _almacen.pendientes();
      _emitir(
        EstadoMotor(
          sincronizando: true,
          pendientes: pend.length,
          ultimaSyncOk: _estado.ultimaSyncOk,
        ),
      );
      for (final r in pend) {
        // Si hay límite de intentos y ya se alcanzó, saltar este evento
        final limite = maxIntentos;
        if (limite != null &&
            ((_intentosPorEvento[r.evento.id] ?? 0) >= limite)) {
          // marcar como rechazado por exceso de intentos
          await _almacen.actualizar(
            r.copiar(
              estado: EstadoSync.rechazado,
              ultimoError: 'máximo de intentos ($limite) alcanzado',
              intentos: r.intentos + 1,
            ),
          );
          continue;
        }
        try {
          await api.enviarEvento(r.evento);
          await _almacen.actualizar(
            r.copiar(
              estado: EstadoSync.sincronizado,
              intentos: r.intentos + 1,
              confirmadoMs: DateTime.now().millisecondsSinceEpoch,
              borrarError: true,
            ),
          );
          // reset contador para este evento al éxito
          _intentosPorEvento[r.evento.id] = 0;
        } on ErrorRechazado catch (e) {
          await _almacen.actualizar(
            r.copiar(
              estado: EstadoSync.rechazado,
              intentos: r.intentos + 1,
              ultimoError: e.toString(),
            ),
          );
        } on ErrorRed catch (e) {
          await _almacen.actualizar(
            r.copiar(intentos: r.intentos + 1, ultimoError: e.mensaje),
          );
          error = e.mensaje;
          // incrementar contador aunque haya error de red
          _intentosPorEvento[r.evento.id] =
              (_intentosPorEvento[r.evento.id] ?? 0) + 1;
        }
      }
      final restantes = (await _almacen.pendientes()).length;
      _emitir(
        EstadoMotor(
          pendientes: restantes,
          ultimaSyncOk: error == null ? DateTime.now() : _estado.ultimaSyncOk,
          ultimoError: error,
        ),
      );
      return error == null;
    } finally {
      _enCurso = false;
    }
  }

  void _emitir(EstadoMotor e) {
    _estado = e;
    if (!_ctrl.isClosed) _ctrl.add(e);
  }

  void liberar() {
    detener();
    _ctrl.close();
  }
}
