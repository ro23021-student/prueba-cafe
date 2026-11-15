import 'package:flutter/material.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';
import '../estado_app.dart';

/// Estado de la cola, cuenta, URL de la API y lista de eventos rechazados con su motivo.
class PantallaSincronizacion extends StatefulWidget {
  final EstadoApp estado;
  final Future<void> Function() alCerrarSesion;
  const PantallaSincronizacion({
    super.key,
    required this.estado,
    required this.alCerrarSesion,
  });

  @override
  State<PantallaSincronizacion> createState() => _PantallaSincronizacionState();
}

class _PantallaSincronizacionState extends State<PantallaSincronizacion> {
  late final TextEditingController _url = TextEditingController(
    text: widget.estado.api.base,
  );

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Widget _tarjetaSesion() {
    final e = widget.estado;
    final rol = e.rol ?? 'sin rol';
    final cooperativa = e.cooperativa ?? 'sin restricción';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_user),
        title: Text('Usuario: ${e.usuario ?? '—'} ($rol)'),
        subtitle: Text(
          'Cooperativa: $cooperativa\n'
          '${e.sesionIniciada ? 'Sesión iniciada' : 'Sesión no válida'}',
        ),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: () async {
            await widget.alCerrarSesion();
          },
          child: const Text('Salir'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EstadoMotor>(
      stream: widget.estado.motor.cambios,
      initialData: widget.estado.motor.estado,
      builder: (context, snap) {
        final m = snap.data!;
        return ListenableBuilder(
          listenable: widget.estado,
          builder: (context, _) {
            final rechazados = widget.estado.registros
                .where((r) => r.estado == EstadoSync.rechazado)
                .toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.estado.avisoInicio != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber),
                      title: Text(widget.estado.avisoInicio!),
                    ),
                  ),
                _tarjetaSesion(),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: m.sincronizando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            m.ultimoError == null
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                          ),
                    title: Text(
                      m.sincronizando
                          ? 'Sincronizando…'
                          : (m.ultimoError == null
                                ? 'Conectado'
                                : 'Sin conexión con el servidor'),
                    ),
                    subtitle: Text(
                      'Pendientes: ${widget.estado.pendientes}'
                      '${m.ultimoError != null ? '\n${m.ultimoError}' : ''}'
                      '${m.ultimaSyncOk != null ? '\nÚltima sincronización correcta: ${m.ultimaSyncOk!.toLocal().toString().substring(0, 19)}' : ''}',
                    ),
                    isThreeLine: true,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: m.sincronizando
                      ? null
                      : widget.estado.reintentarAhora,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sincronizar ahora'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'URL de la API',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Aplicar',
                      onPressed: () async {
                        await widget.estado.cambiarUrl(_url.text);
                        widget.estado.reintentarAhora();
                      },
                    ),
                  ),
                ),
                if (rechazados.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Rechazados por el servidor (${rechazados.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'No se reintentan: hay que corregir los datos y registrar el evento de nuevo.',
                  ),
                  for (final r in rechazados)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.error_outline),
                      title: Text(
                        '${r.evento.loteId} · ${r.evento.etapa.name}',
                      ),
                      subtitle: Text(r.ultimoError ?? ''),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
