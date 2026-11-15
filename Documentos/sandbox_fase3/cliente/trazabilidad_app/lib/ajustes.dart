import 'dart:convert';
import 'dart:io';

/// Ajustes no sensibles que la app recuerda entre sesiones: URL de la API y nombre de usuario.
/// (La clave del usuario y la clave de cifrado NO van aquí: están en el almacén seguro, ver `boveda.dart`.)
class Ajustes {
  final File _archivo;
  String? url;
  String? usuario;

  Ajustes._(this._archivo, {this.url, this.usuario});

  /// Lee el archivo; si no existe o está dañado, empieza con ajustes vacíos.
  static Future<Ajustes> cargar(File archivo) async {
    try {
      if (await archivo.exists()) {
        final j = jsonDecode(await archivo.readAsString());
        if (j is Map) {
          return Ajustes._(
            archivo,
            url: j['url'] as String?,
            usuario: j['usuario'] as String?,
          );
        }
      }
    } on FormatException {
      // archivo dañado: se ignora y se vuelve a escribir al guardar
    } on TypeError {
      // campos con tipo inesperado
    }
    return Ajustes._(archivo);
  }

  Future<void> guardar() async {
    final tmp = File('${_archivo.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'url': url, 'usuario': usuario}),
      flush: true,
    );
    await tmp.rename(_archivo.path);
  }
}
