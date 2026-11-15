import 'package:flutter/material.dart';

import '../estado_app.dart';

/// Pantalla de inicio obligatoria: valida las credenciales contra el servidor antes de entrar.
/// La clave no se guarda: se pide en cada arranque de la app.
class PantallaInicio extends StatefulWidget {
  final EstadoApp estado;
  final VoidCallback alEntrar;
  const PantallaInicio({
    super.key,
    required this.estado,
    required this.alEntrar,
  });

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  late final TextEditingController _url;
  late final TextEditingController _usuario;
  final TextEditingController _clave = TextEditingController();
  bool _entrando = false;
  bool _verClave = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.estado.api.base);
    _usuario = TextEditingController(text: widget.estado.ajustes.usuario ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final url = _url.text.trim();
    final usuario = _usuario.text.trim();
    if (url.isEmpty || usuario.isEmpty || _clave.text.isEmpty) {
      setState(() => _error = 'Completa la URL, el usuario y la clave.');
      return;
    }

    setState(() {
      _entrando = true;
      _error = null;
    });

    try {
      await widget.estado.cambiarUrl(url);
      final error = await widget.estado.iniciarSesion(usuario, _clave.text);
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _entrando = false;
          _error = error;
        });
        return;
      }
      _clave.clear();
      widget.alEntrar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entrando = false;
        _error = 'No se pudo iniciar sesión: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AutofillGroup(
                child: ListenableBuilder(
                  listenable: widget.estado,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.agriculture,
                        size: 64,
                        color: tema.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Trazabilidad de café',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Inicia sesión para entrar. La sesión es obligatoria.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (!widget.estado.redDisponible) ...[
                        Card(
                          color: tema.colorScheme.errorContainer,
                          child: const ListTile(
                            leading: Icon(Icons.wifi_off),
                            title: Text('Sin conexión'),
                            subtitle: Text(
                              'Necesitas red para validar el usuario y la clave.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'URL de la API',
                          helperText: 'Ejemplo: http://192.168.1.20:8080',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _usuario,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _clave,
                        obscureText: !_verClave,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) {
                          if (!_entrando) _entrar();
                        },
                        decoration: InputDecoration(
                          labelText: 'Clave',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _verClave
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () =>
                                setState(() => _verClave = !_verClave),
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(color: tema.colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _entrando ? null : _entrar,
                        icon: _entrando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: const Text('Entrar'),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Los eventos guardados en este teléfono se enviarán al iniciar sesión.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
