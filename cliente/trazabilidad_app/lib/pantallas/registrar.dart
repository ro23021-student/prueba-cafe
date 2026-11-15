import 'package:flutter/material.dart';
import 'package:trazabilidad_core/trazabilidad_core.dart';
import '../estado_app.dart';

/// Formulario de registro en campo. Guarda en el dispositivo aunque no haya señal.
class PantallaRegistrar extends StatefulWidget {
  final EstadoApp estado;
  const PantallaRegistrar({super.key, required this.estado});
  @override
  State<PantallaRegistrar> createState() => _PantallaRegistrarState();
}

class _PantallaRegistrarState extends State<PantallaRegistrar> {
  final _form = GlobalKey<FormState>();
  final _lote = TextEditingController();
  final _coop = TextEditingController();
  final _owner = TextEditingController();
  final _peso = TextEditingController();
  final _notas = TextEditingController();
  Etapa _etapa = Etapa.recoleccion;

  @override
  void initState() {
    super.initState();
    final e = widget.estado;
    _owner.text = e.usuario ?? '';
    _coop.text = e.cooperativa ?? '';
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
  RegistroLocal? _masReciente() {
    final r = widget.estado.registros;
    if (r.isEmpty) return null;
    return r.reduce((a, b) => a.creadoMs >= b.creadoMs ? a : b);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final peso = _peso.text.trim().isEmpty
        ? null
        : double.parse(_peso.text.trim().replaceAll(',', '.'));
    final mensajero = ScaffoldMessenger.of(context);
    final error = await widget.estado.registrar(
      loteId: _lote.text,
      cooperativaId: _coop.text,
      etapa: _etapa,
      owner: _owner.text,
      pesoKg: peso,
      notas: _notas.text,
    );
    if (!mounted) return;
    if (error != null) {
      mensajero.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Se conservan cooperativa y responsable para registrar varios seguidos.
    _lote.clear();
    _peso.clear();
    _notas.clear();

    // Margen para que el motor intente enviar antes de decidir el mensaje.
    await Future.delayed(const Duration(milliseconds: 1500));
    final r = _masReciente();
    final String texto;
    if (r?.estado == EstadoSync.sincronizado) {
      texto = 'Guardado y enviado al servidor.';
    } else if (r?.estado == EstadoSync.rechazado) {
      texto = 'El servidor rechazó el evento: ${r?.ultimoError ?? ''}';
    } else {
      texto = 'Guardado en el dispositivo. Se enviará cuando haya conexión.';
    }
    mensajero.showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.estado;
    if (e.soloLectura) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El rol auditor es de solo lectura.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final ownerBloqueado = e.esProductor;
    final coopBloqueada = e.cooperativa != null;

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              for (final e in Etapa.values)
                DropdownMenuItem(value: e, child: Text(e.name)),
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            onPressed: _guardar,
            icon: const Icon(Icons.save),
            label: const Text('Guardar evento'),
          ),
        ],
      ),
    );
  }
}
