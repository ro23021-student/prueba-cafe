import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secretos del dispositivo en el almacén seguro del sistema (Keystore en Android, Keychain en iOS).
/// - clave AES-256 de la cola local (se genera una vez, nunca sale del dispositivo)
/// - clave del usuario de la API (para renovar el token sin volver a pedirla)
class Boveda {
  static const _kCola = 'clave_cola_aes256';
  static const _kClaveUsuario = 'clave_usuario_api';
  final FlutterSecureStorage _s;

  Boveda([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();

  /// Devuelve la clave de cifrado de la cola; si no existe aún, la genera con `Random.secure()`.
  Future<List<int>> claveCola() async {
    final guardada = await _s.read(key: _kCola);
    if (guardada != null) {
      final bytes = base64Decode(guardada);
      if (bytes.length == 32) return bytes;
    }
    final r = Random.secure();
    final nueva = List<int>.generate(32, (_) => r.nextInt(256));
    await _s.write(key: _kCola, value: base64Encode(nueva));
    return nueva;
  }

  Future<String?> leerClaveUsuario() => _s.read(key: _kClaveUsuario);
  Future<void> guardarClaveUsuario(String clave) =>
      _s.write(key: _kClaveUsuario, value: clave);
  Future<void> borrarClaveUsuario() => _s.delete(key: _kClaveUsuario);
}
