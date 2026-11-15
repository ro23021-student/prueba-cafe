import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';
import '../estado_app.dart';

String fechaCorta(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
}

/// Eventos guardados en el dispositivo, con filtro por lote y consulta del lote en el servidor.
class PantallaLotes extends StatefulWidget {
  final EstadoApp estado;
  const PantallaLotes({super.key, required this.estado});
  @override
  State<PantallaLotes> createState() => _PantallaLotesState();
}

class _PantallaLotesState extends State<PantallaLotes> {
  final _filtro = TextEditingController();
  final _consulta = TextEditingController();

  @override
  void dispose() {
    _filtro.dispose();
    _consulta.dispose();
    super.dispose();
  }

  void _consultar(String valor) {
    final loteId = valor.trim();
    if (loteId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe el ID del lote que quieres consultar.'),
        ),
      );
      return;
    }
    unawaited(_verEnServidor(loteId));
  }

  Future<void> _verEnServidor(String loteId) async {
    String mensaje;
    try {
      final eventos = await widget.estado.api.consultarLote(loteId);
      mensaje = eventos.isEmpty
          ? 'El servidor aún no tiene eventos de $loteId.'
          : 'En el servidor: ${eventos.length} evento(s): ${eventos.map((e) => e.etapa.name).join(' → ')}';
    } on ErrorRed catch (e) {
      mensaje = 'No se pudo consultar: ${e.mensaje}';
    } on ErrorRechazado catch (e) {
      mensaje = 'El servidor rechazó la consulta: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Widget _chip(EstadoSync s) {
    final (texto, icono) = switch (s) {
      EstadoSync.pendiente => ('Pendiente', Icons.schedule),
      EstadoSync.sincronizado => ('Sincronizado', Icons.cloud_done),
      EstadoSync.rechazado => ('Rechazado', Icons.error_outline),
    };
    return Chip(
      avatar: Icon(icono, size: 16),
      label: Text(texto),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.estado, _filtro]),
      builder: (context, _) {
        final q = _filtro.text.trim().toLowerCase();
        final lista = widget.estado.registros
            .where(
              (r) => q.isEmpty || r.evento.loteId.toLowerCase().contains(q),
            )
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                controller: _filtro,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Filtrar por lote',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _consulta,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _consultar,
                      decoration: const InputDecoration(
                        labelText: 'Consultar lote en el servidor',
                        hintText: 'L-000123',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Consultar en el servidor',
                    onPressed: () => _consultar(_consulta.text),
                    icon: const Icon(Icons.cloud_download_outlined),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lista.isEmpty
                  ? const Center(child: Text('Sin eventos todavía'))
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = lista[i];
                        final ev = r.evento;
                        final peso = ev.extra['peso_kg'];
                        return ListTile(
                          title: Text('${ev.loteId} · ${ev.etapa.name}'),
                          subtitle: Text(
                            '${ev.cooperativaId} · ${ev.owner} · ${fechaCorta(ev.ts)}'
                            '${peso != null ? ' · $peso kg' : ''}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _chip(r.estado),
                              IconButton(
                                tooltip: 'Ver este lote en el servidor',
                                icon: const Icon(Icons.cloud_download_outlined),
                                onPressed: () =>
                                    unawaited(_verEnServidor(ev.loteId)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
