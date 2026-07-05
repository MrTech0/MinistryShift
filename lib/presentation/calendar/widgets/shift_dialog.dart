import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ministry_shift/data/database/app_database.dart';
import 'package:ministry_shift/core/scheduler/shift_validator.dart';

class ShiftDialog extends StatefulWidget {
  final DateTime initialDate;
  final ShiftWithPersonnel? editShift;
  const ShiftDialog({
    super.key,
    required this.initialDate,
    this.editShift,
  });

  @override
  State<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<ShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  final _startController = TextEditingController(text: '09:00');
  final _endController = TextEditingController(text: '11:00');
  
  String _selectedType = 'exhibidor'; // 'exhibidor' or 'salida'
  int? _selectedLocationId;
  int? _selectedCaptainId;
  final Set<int> _selectedPreacherIds = {};

  List<Location> _locations = [];
  List<Preacher> _captains = [];
  List<Preacher> _publishers = [];
  List<Preacher> _allPreachers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.editShift != null) {
      final es = widget.editShift!;
      _selectedDate = es.shift.date;
      _startController.text = es.shift.startTime;
      _endController.text = es.shift.endTime;
      _selectedType = es.shift.type;
      _selectedLocationId = es.shift.locationId;
      _selectedCaptainId = es.shift.captainId;
      _selectedPreacherIds.addAll(es.assignedPreachers.map((p) => p.id));
    } else {
      _selectedDate = widget.initialDate;
    }
    _loadData();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = context.read<AuthService>().database;
    if (db == null) return;

    // Retrieve active resources
    final locs = await db.watchActiveLocations().first;
    final preachersList = await db.watchActivePreachers().first;

    setState(() {
      _locations = List<Location>.from(locs);
      if (widget.editShift != null && !_locations.any((l) => l.id == widget.editShift!.location.id)) {
        _locations.add(widget.editShift!.location);
      }

      _captains = preachersList.where((p) => p.canBeCaptain).toList();
      if (widget.editShift != null && widget.editShift!.captain != null) {
        final cap = widget.editShift!.captain!;
        if (!_captains.any((p) => p.id == cap.id)) {
          _captains.add(cap);
        }
      }

      _publishers = preachersList.where((p) => p.canBePublisher).toList();
      _allPreachers = List<Preacher>.from(preachersList);

      if (widget.editShift != null) {
        for (final p in widget.editShift!.assignedPreachers) {
          if (!_allPreachers.any((ap) => ap.id == p.id)) {
            _allPreachers.add(p);
          }
          if (p.canBePublisher && !_publishers.any((ap) => ap.id == p.id)) {
            _publishers.add(p);
          }
        }
      }
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocationId == null) {
      setState(() => _errorMessage = 'Selecciona una ubicación.');
      return;
    }
    if (_selectedType == 'exhibidor' && _selectedCaptainId == null) {
      setState(() => _errorMessage = 'Selecciona un capitán de turno.');
      return;
    }

    // Capacity check based on type and personnel
    final listPublishers = _selectedPreacherIds.toList();
    try {
      ShiftValidator.validateShiftCapacity(
        type: _selectedType,
        hasCaptain: _selectedCaptainId != null,
        additionalPreachersCount: listPublishers.length,
      );
    } on ShiftValidationException catch (e) {
      setState(() {
        if (e.messageKey == 'shift_error_captain_required') {
          _errorMessage = 'Se requiere un capitán para turnos con exhibidor.';
        } else if (e.messageKey == 'shift_error_capacity_min') {
          _errorMessage = 'Capacidad mínima no alcanzada. Se requieren al menos 2 personas en total (Capitán + 1 publicador).';
        } else if (e.messageKey == 'shift_error_capacity_max') {
          _errorMessage = 'Capacidad máxima superada. Se permite un máximo de 6 personas en total.';
        } else if (e.messageKey == 'shift_error_salida_empty') {
          _errorMessage = 'Se debe asignar un predicador para la salida.';
        } else if (e.messageKey == 'shift_error_salida_max') {
          _errorMessage = 'Solo se permite un predicador asignado para la salida.';
        } else {
          _errorMessage = 'Error de validación de capacidad.';
        }
      });
      return;
    }

    final db = context.read<AuthService>().database;
    if (db == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.editShift != null) {
        // Update existing shift record
        final updatedShift = widget.editShift!.shift.copyWith(
          date: _selectedDate,
          startTime: _startController.text,
          endTime: _endController.text,
          locationId: _selectedLocationId!,
          captainId: drift.Value(_selectedCaptainId),
          type: _selectedType,
        );
        await db.updateShift(updatedShift, listPublishers);
      } else {
        // Create new shift record
        await db.createShift(
          ShiftsCompanion.insert(
            date: _selectedDate,
            startTime: _startController.text,
            endTime: _endController.text,
            locationId: _selectedLocationId!,
            captainId: drift.Value(_selectedCaptainId),
            type: drift.Value(_selectedType),
          ),
          listPublishers,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving shift: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al guardar el turno: $e';
      });
    }
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
    TimeOfDay initialTime = const TimeOfDay(hour: 9, minute: 0);
    if (controller.text.isNotEmpty) {
      final parts = controller.text.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          initialTime = TimeOfDay(hour: h, minute: m);
        }
      }
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minuteStr = picked.minute.toString().padLeft(2, '0');
      controller.text = '$hourStr:$minuteStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: Text(widget.editShift != null ? 'Editar Turno de Predicación' : 'Nuevo Turno de Predicación'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.error.withOpacity(0.5)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Tipo de Turno Selector
                const Text(
                  'Tipo de Turno',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'exhibidor',
                      icon: Icon(Icons.shopping_cart_outlined),
                      label: Text('Exhibidor'),
                    ),
                    ButtonSegment(
                      value: 'salida',
                      icon: Icon(Icons.directions_walk_outlined),
                      label: Text('Salida Predicación'),
                    ),
                  ],
                  selected: {_selectedType},
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedType = val.first;
                      if (_selectedType == 'salida') {
                        _selectedCaptainId = null;
                        if (_selectedPreacherIds.length > 1) {
                          final first = _selectedPreacherIds.first;
                          _selectedPreacherIds.clear();
                          _selectedPreacherIds.add(first);
                        }
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Date Picker field
                ListTile(
                  title: const Text('Fecha del Turno'),
                  subtitle: Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2026),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                ),
                const Divider(),

                // Time Pickers
                 Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _startController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Hora Inicio',
                          hintText: 'Selecciona hora',
                          prefixIcon: Icon(Icons.access_time),
                        ),
                        onTap: () => _selectTime(context, _startController),
                        validator: (val) => val == null || val.isEmpty ? 'Selecciona una hora' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _endController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Hora Fin',
                          hintText: 'Selecciona hora',
                          prefixIcon: Icon(Icons.access_time),
                        ),
                        onTap: () => _selectTime(context, _endController),
                        validator: (val) => val == null || val.isEmpty ? 'Selecciona una hora' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Location Dropdown
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Ubicación / Punto de Encuentro',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  value: _selectedLocationId,
                  items: _locations
                      .map((l) => DropdownMenuItem(
                            value: l.id,
                            child: Text(l.name),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedLocationId = val),
                ),
                const SizedBox(height: 16),

                // Captain Dropdown (only for Exhibidor)
                if (_selectedType == 'exhibidor') ...[
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Capitán de Turno',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                    value: _selectedCaptainId,
                    items: _captains
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.firstName} ${c.lastName}'),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedCaptainId = val;
                        // Remove captain from publishers checklist if selected
                        if (val != null) {
                          _selectedPreacherIds.remove(val);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                // Preachers checklist
                Text(
                  _selectedType == 'exhibidor'
                      ? 'Asignar Publicadores de Carrito (Mínimo 1, Máximo 5)'
                      : 'Asignar Predicador para la Salida (Selecciona 1)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: (_selectedType == 'exhibidor' ? _publishers : _allPreachers).isEmpty
                      ? const Center(child: Text('No hay predicadores activos.'))
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: (_selectedType == 'exhibidor' ? _publishers : _allPreachers)
                              .where((p) => p.id != _selectedCaptainId) // Exclude selected Captain if any
                              .map((p) {
                            return CheckboxListTile(
                              dense: true,
                              title: Text('${p.firstName} ${p.lastName}'),
                              value: _selectedPreacherIds.contains(p.id),
                              onChanged: (selected) {
                                setState(() {
                                  if (selected == true) {
                                    if (_selectedType == 'salida') {
                                      _selectedPreacherIds.clear();
                                    }
                                    _selectedPreacherIds.add(p.id);
                                  } else {
                                    _selectedPreacherIds.remove(p.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _save,
          child: Text(widget.editShift != null ? 'Guardar Cambios' : 'Crear Turno'),
        ),
      ],
    );
  }
}
