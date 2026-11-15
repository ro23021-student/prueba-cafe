import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';

import 'ajustes.dart';
import 'boveda.dart';
import 'estado_app.dart';
import 'pantallas/inicio.dart';
import 'pantallas/lotes.dart';
import 'pantallas/registrar.dart';
import 'pantallas/sincronizacion.dart';

void main() => runApp(const AppRaiz());

/// URL por defecto de la API del sandbox. El emulador de Android ve la PC como 10.0.2.2.
/// En un teléfono físico se cambia desde la pantalla de inicio o desde Sincronización.
String urlPorDefecto() =>
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
    ? 'http://10.0.2.2:8080'
    : 'http://localhost:8080';

class AppRaiz extends StatefulWidget {
  const AppRaiz({super.key});
  @override
  State<AppRaiz> createState() => _AppRaizState();
}

class _AppRaizState extends State<AppRaiz> {
  late final Future<EstadoApp> _futuro = _iniciar();

  Future<EstadoApp> _iniciar() async {
    final dir = await getApplicationSupportDirectory();
    final ajustes = await Ajustes.cargar(File('${dir.path}/ajustes.json'));
    final boveda = Boveda();

    // Cola local cifrada (AES-256-GCM). La clave vive en el almacén seguro del sistema.
    final clave = await boveda.claveCola();
    final cifrada = File('${dir.path}/cola_eventos.enc');
    String? aviso;
    AlmacenArchivoCifrado almacen;
    try {
      almacen = await AlmacenArchivoCifrado.abrir(cifrada, clave);
    } on StateError {
      // Pasa, p. ej., si el sistema restauró el archivo desde una copia de seguridad pero no la clave.
      final copia = File(
        '${cifrada.path}.ilegible-${DateTime.now().millisecondsSinceEpoch}',
      );
      await cifrada.rename(copia.path);
      almacen = await AlmacenArchivoCifrado.abrir(cifrada, clave);
      aviso =
          'La cola local anterior no se pudo descifrar y se conservó aparte (${copia.uri.pathSegments.last}). '
          'Se empezó una cola nueva.';
    }

    // Migración única: la versión anterior guardaba la cola en JSON sin cifrar.
    final vieja = File('${dir.path}/cola_eventos.json');
    if (await vieja.exists()) {
      await importarDesdeJsonPlano(vieja, almacen);
      await vieja.delete();
    }

    // El login es obligatorio en cada arranque: la clave ya no se guarda en el dispositivo.
    try {
      await boveda.borrarClaveUsuario();
    } catch (_) {}

    final api = ApiCliente(ajustes.url ?? urlPorDefecto());
    return EstadoApp(
      almacen: almacen,
      api: api,
      motor: MotorSync(almacen, api),
      ajustes: ajustes,
      boveda: boveda,
      avisoInicio: aviso,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trazabilidad de café',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6F4E37),
        useMaterial3: true,
      ),
      home: FutureBuilder<EstadoApp>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                child: Text(
                  'No se pudo abrir el almacenamiento local:\n${snap.error}',
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return _Shell(estado: snap.data!);
        },
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  final EstadoApp estado;
  const _Shell({required this.estado});
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  bool _enInicio = true;

  void _entrar() {
    widget.estado.activarMotor();
    setState(() => _enInicio = false);
  }

  Future<void> _salir() async {
    await widget.estado.cerrarSesion();
    if (!mounted) return;
    setState(() => _enInicio = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_enInicio) {
      return PantallaInicio(estado: widget.estado, alEntrar: _entrar);
    }
    return PaginaPrincipal(estado: widget.estado, alCerrarSesion: _salir);
  }
}

class PaginaPrincipal extends StatefulWidget {
  final EstadoApp estado;
  final Future<void> Function() alCerrarSesion;
  const PaginaPrincipal({
    super.key,
    required this.estado,
    required this.alCerrarSesion,
  });
  @override
  State<PaginaPrincipal> createState() => _PaginaPrincipalState();
}

class _PaginaPrincipalState extends State<PaginaPrincipal> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    final puedeRegistrar = !e.soloLectura;
    final paginas = <Widget>[
      if (puedeRegistrar) PantallaRegistrar(estado: e),
      PantallaLotes(estado: e),
      PantallaSincronizacion(estado: e, alCerrarSesion: widget.alCerrarSesion),
    ];
    final indice = _tab >= paginas.length ? 0 : _tab;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trazabilidad de café'),
        actions: [
          if (e.rol != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    e.cooperativa == null
                        ? e.rol!
                        : '${e.rol} · ${e.cooperativa}',
                  ),
                ),
              ),
            ),
        ],
      ),
      body: IndexedStack(index: indice, children: paginas),
      bottomNavigationBar: ListenableBuilder(
        listenable: e,
        builder: (context, _) => NavigationBar(
          selectedIndex: indice,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            if (puedeRegistrar)
              const NavigationDestination(
                icon: Icon(Icons.edit_note),
                label: 'Registrar',
              ),
            const NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              label: 'Lotes',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: e.pendientes > 0,
                label: Text('${e.pendientes}'),
                child: const Icon(Icons.sync),
              ),
              label: 'Sincronización',
            ),
          ],
        ),
      ),
    );
  }
}
