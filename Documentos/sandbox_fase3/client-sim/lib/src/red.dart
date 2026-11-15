import 'dart:io';

/// Controla la degradación de red del contenedor del cliente.
abstract class ControladorRed {
  /// De dónde vienen las marcas de tiempo de los cortes (se anota en el resumen).
  String get fuente;

  /// Aplica el perfil de red base de la corrida (si lo hay).
  Future<void> preparar();

  /// Corte total (100 % de pérdida).
  Future<void> cortar();

  /// Vuelve al perfil base tras un corte.
  Future<void> restaurar();

  /// Quita toda degradación (se usa antes de verificar contra el servidor).
  Future<void> quitarDegradacion();
}

/// Modo `external`: el cliente no toca la red; los cortes los aplica outage.sh desde el anfitrión.
class RedNinguna implements ControladorRed {
  @override
  String get fuente => 'plan';
  @override
  Future<void> preparar() async {}
  @override
  Future<void> cortar() async {}
  @override
  Future<void> restaurar() async {}
  @override
  Future<void> quitarDegradacion() async {}
}

/// Modo `self`: usa `tc qdisc netem` sobre eth0 dentro del contenedor (necesita NET_ADMIN y el paquete iproute2).
class RedTc implements ControladorRed {
  final String netemBase;
  final String interfaz;
  RedTc(this.netemBase, {this.interfaz = 'eth0'});

  @override
  String get fuente => 'tc';

  Future<void> _tc(List<String> args, {bool toleraError = false}) async {
    final ProcessResult r;
    try {
      r = await Process.run('tc', args);
    } on ProcessException catch (e) {
      throw StateError('No se pudo ejecutar tc (¿falta iproute2?): ${e.message}');
    }
    if (r.exitCode != 0 && !toleraError) {
      throw StateError('tc ${args.join(' ')} falló: ${r.stderr}');
    }
  }

  @override
  Future<void> preparar() => restaurar();

  @override
  Future<void> cortar() => _tc(['qdisc', 'replace', 'dev', interfaz, 'root', 'netem', 'loss', '100%']);

  @override
  Future<void> restaurar() {
    if (netemBase.trim().isEmpty) {
      return quitarDegradacion();
    }
    return _tc(['qdisc', 'replace', 'dev', interfaz, 'root', 'netem', ...netemBase.trim().split(RegExp(r'\s+'))]);
  }

  @override
  Future<void> quitarDegradacion() => _tc(['qdisc', 'del', 'dev', interfaz, 'root'], toleraError: true);
}
