import 'package:flutter/material.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';
import '../estado_app.dart';

/// Corrección de un evento que el servidor todavía no aceptó (pendiente o rechazado).
/// Un evento ya sincronizado forma parte del historial y no se edita desde aquí.
class PantallaEditar extends StatefulWidget {
  final EstadoApp estado;
  final RegistroLocal registro;
  const PantallaEditar({
    super.key,
    required this.estado,
    required this.registro,
  });
  @override
  State<PantallaEditar> createState() => _PantallaEditarState();
}

class _PantallaEditarState extends State<PantallaEditar> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _lote;
  late final TextEditingController _coop;
  late final TextEditingController _owner;
  late final TextEditingController _peso;
  late final TextEditingController _notas;
  late Etapa _etapa;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final ev = widget.registro.evento;
    _lote = TextEditingController(text: ev.loteId);
    _coop = TextEditingController(text: ev.cooperativaId);
    _owner = TextEditingController(text: ev.owner);
    final peso = ev.extra['peso_kg'];
    _peso = TextEditingController(text: peso == null ? '' : '$peso');
    final notas = ev.extra['notas'];
    _notas = TextEditingController(text: notas == null ? '' : '$notas');
    _etapa = ev.etapa;
  }

  @override
  void dispose() {
    for (final c in [_lote, _coop, _owner, _peso, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _requerido(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;

  String? _validarPeso(String? v) {
    if (v == null || v.trim().isEmpty) return null; // opcional
    final n = double.tryParse(v.trim().replaceAll(',', '.'));
    return (n == null || n <= 0) ? 'Número mayor que 0' : null;
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final peso = _peso.text.trim().isEmpty
        ? null
        : double.parse(_peso.text.trim().replaceAll(',', '.'));
    final error = await widget.estado.editar(
      original: widget.registro,
      loteId: _lote.text,
      cooperativaId: _coop.text,
      etapa: _etapa,
      owner: _owner.text,
      pesoKg: peso,
      notas: _notas.text,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // El mensaje se muestra en la pantalla anterior, que es la que queda a la vista.
    final mensajero = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    mensajero.showSnackBar(
      const SnackBar(
        content: Text(
          'Cambios guardados. El evento se enviará cuando haya conexión.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    final r = widget.registro;
    final ownerBloqueado = e.esProductor;
    final coopBloqueada = e.cooperativa != null;
    final yaSeIntento = r.intentos > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar evento')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (r.estado == EstadoSync.rechazado)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('El servidor rechazó este evento'),
                  subtitle: Text(
                    r.ultimoError ?? 'Corrígelo y se volverá a enviar.',
                  ),
                ),
              ),
            if (yaSeIntento)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Este evento ya se intentó enviar. Al guardar se registrará '
                  'con la fecha y hora actuales, para no chocar con una copia '
                  'que el servidor pudiera haber recibido.',
                ),
              ),
            TextFormField(
              controller: _lote,
              decoration: const InputDecoration(
                labelText: 'Lote (ej. L-000123)',
                border: OutlineInputBorder(),
              ),
              validator: _requerido,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _coop,
              readOnly: coopBloqueada,
              decoration: InputDecoration(
                labelText: 'Cooperativa (ej. COOP-01)',
                border: const OutlineInputBorder(),
                helperText: coopBloqueada
                    ? 'Tu usuario está limitado a esta cooperativa.'
                    : null,
              ),
              validator: _requerido,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Etapa>(
              initialValue: _etapa,
              decoration: const InputDecoration(
                labelText: 'Etapa',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final et in Etapa.values)
                  DropdownMenuItem(value: et, child: Text(et.name)),
              ],
              onChanged: (v) => setState(() => _etapa = v ?? _etapa),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _owner,
              readOnly: ownerBloqueado,
              decoration: InputDecoration(
                labelText: 'Responsable (ej. prod-0001)',
                border: const OutlineInputBorder(),
                helperText: ownerBloqueado
                    ? 'Como productor, solo puedes registrar a tu nombre.'
                    : null,
              ),
              validator: _requerido,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _peso,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Peso (kg), opcional',
                border: OutlineInputBorder(),
              ),
              validator: _validarPeso,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notas,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas, opcional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: const Icon(Icons.save),
              label: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}
