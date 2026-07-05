import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ministry_shift/data/database/app_database.dart';

class PreachersPage extends StatefulWidget {
  const PreachersPage({super.key});

  @override
  State<PreachersPage> createState() => _PreachersPageState();
}

class _PreachersPageState extends State<PreachersPage> {
  void _showAddPreacherDialog(AppDatabase database) {
    showDialog(
      context: context,
      builder: (context) => _AddPreacherDialog(database: database),
    );
  }

  void _showEditPreacherDialog(AppDatabase database, Preacher preacher) {
    showDialog(
      context: context,
      builder: (context) => _EditPreacherDialog(database: database, preacher: preacher),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AuthService>().database;
    final colorScheme = Theme.of(context).colorScheme;

    if (db == null) {
      return const Center(child: Text('Base de datos no disponible.'));
    }

    return Scaffold(
      body: StreamBuilder<List<Preacher>>(
        stream: db.watchActivePreachers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text(
                    'No hay predicadores registrados.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Haz clic en el botón inferior para añadir tu primer predicador.'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _showAddPreacherDialog(db),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir Predicador'),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24.0),
            key: const Key('preachers_list_padding'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Predicadores Activos',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showAddPreacherDialog(db),
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir Predicador'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                    ),
                    child: ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: colorScheme.outlineVariant.withOpacity(0.5)),
                      itemBuilder: (context, index) {
                        final p = list[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              '${p.firstName[0]}${p.lastName[0]}',
                              style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text('${p.firstName} ${p.lastName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(p.phone ?? 'Sin teléfono'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p.canBeCaptain)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Chip(
                                    label: const Text('Capitán', style: TextStyle(fontSize: 11)),
                                    backgroundColor: colorScheme.tertiaryContainer,
                                    side: BorderSide.none,
                                  ),
                                ),
                              if (p.canBePublisher)
                                Chip(
                                  label: const Text('Publicador', style: TextStyle(fontSize: 11)),
                                  backgroundColor: colorScheme.secondaryContainer,
                                  side: BorderSide.none,
                                ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                color: colorScheme.primary,
                                onPressed: () => _showEditPreacherDialog(db, p),
                                tooltip: 'Editar predicador',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: colorScheme.error,
                                onPressed: () async {
                                  // Mark inactive instead of hard delete to preserve history
                                  await db.updatePreacher(p.copyWith(isActive: false));
                                },
                                tooltip: 'Dar de baja predicador',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AddPreacherDialog extends StatefulWidget {
  final AppDatabase database;
  const _AddPreacherDialog({required this.database});

  @override
  State<_AddPreacherDialog> createState() => _AddPreacherDialogState();
}

class _AddPreacherDialogState extends State<_AddPreacherDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _canBeCaptain = false;
  bool _canBePublisher = true;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Añadir Predicador'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Introduce el nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Apellidos *'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Introduce los apellidos' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Teléfono (Opcional)'),
              ),
              const SizedBox(height: 24),
              CheckboxListTile(
                title: const Text('¿Puede ser Capitán?'),
                subtitle: const Text('Autoriza a liderar turnos y gestionar carritos.'),
                value: _canBeCaptain,
                onChanged: (val) {
                  setState(() => _canBeCaptain = val ?? false);
                },
              ),
              CheckboxListTile(
                title: const Text('¿Puede ser Publicador de Carrito?'),
                subtitle: const Text('Autoriza a participar en turnos con carritos.'),
                value: _canBePublisher,
                onChanged: (val) {
                  setState(() => _canBePublisher = val ?? false);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              if (!_formKey.currentState!.validate()) return;

              await widget.database.insertPreacher(
                PreachersCompanion.insert(
                  firstName: _firstNameController.text,
                  lastName: _lastNameController.text,
                  phone: drift.Value(_phoneController.text.isEmpty ? null : _phoneController.text),
                  canBeCaptain: drift.Value(_canBeCaptain),
                  canBePublisher: drift.Value(_canBePublisher),
                ),
              );

              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              debugPrint('Error saving preacher: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al guardar: $e'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _EditPreacherDialog extends StatefulWidget {
  final AppDatabase database;
  final Preacher preacher;
  const _EditPreacherDialog({required this.database, required this.preacher});

  @override
  State<_EditPreacherDialog> createState() => _EditPreacherDialogState();
}

class _EditPreacherDialogState extends State<_EditPreacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late bool _canBeCaptain;
  late bool _canBePublisher;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.preacher.firstName);
    _lastNameController = TextEditingController(text: widget.preacher.lastName);
    _phoneController = TextEditingController(text: widget.preacher.phone ?? '');
    _canBeCaptain = widget.preacher.canBeCaptain;
    _canBePublisher = widget.preacher.canBePublisher;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Predicador'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Introduce el nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Apellidos *'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Introduce los apellidos' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Teléfono (Opcional)'),
              ),
              const SizedBox(height: 24),
              CheckboxListTile(
                title: const Text('¿Puede ser Capitán?'),
                subtitle: const Text('Autoriza a liderar turnos y gestionar carritos.'),
                value: _canBeCaptain,
                onChanged: (val) {
                  setState(() => _canBeCaptain = val ?? false);
                },
              ),
              CheckboxListTile(
                title: const Text('¿Puede ser Publicador de Carrito?'),
                subtitle: const Text('Autoriza a participar en turnos con carritos.'),
                value: _canBePublisher,
                onChanged: (val) {
                  setState(() => _canBePublisher = val ?? false);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              if (!_formKey.currentState!.validate()) return;

              await widget.database.updatePreacher(
                widget.preacher.copyWith(
                  firstName: _firstNameController.text,
                  lastName: _lastNameController.text,
                  phone: drift.Value(_phoneController.text.isEmpty ? null : _phoneController.text),
                  canBeCaptain: _canBeCaptain,
                  canBePublisher: _canBePublisher,
                ),
              );

              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              debugPrint('Error updating preacher: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al guardar: $e'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
