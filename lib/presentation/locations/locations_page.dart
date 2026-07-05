import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:ministry_shift/data/database/app_database.dart';

class LocationsPage extends StatefulWidget {
  const LocationsPage({super.key});

  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  void _showAddLocationDialog(AppDatabase database) {
    showDialog(
      context: context,
      builder: (context) => _AddLocationDialog(database: database),
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
      body: StreamBuilder<List<Location>>(
        stream: db.watchActiveLocations(),
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
                  Icon(Icons.map_outlined, size: 64, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text(
                    'No hay ubicaciones registradas.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Haz clic en el botón inferior para añadir tu primera ubicación.'),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _showAddLocationDialog(db),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir Ubicación'),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(24.0),
            key: const Key('locations_list_padding'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ubicaciones de Carrito',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showAddLocationDialog(db),
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir Ubicación'),
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
                        final loc = list[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.secondaryContainer,
                            child: const Icon(Icons.place_outlined),
                          ),
                          title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(loc.description ?? 'Sin descripción'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: colorScheme.error,
                            onPressed: () async {
                              // Mark inactive to preserve references
                              await db.updateLocation(loc.copyWith(isActive: false));
                            },
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

class _AddLocationDialog extends StatefulWidget {
  final AppDatabase database;
  const _AddLocationDialog({required this.database});

  @override
  State<_AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends State<_AddLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Añadir Ubicación de Carrito'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre de Ubicación *'),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Introduce el nombre de la ubicación' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descripción / Puntos de Referencia (Opcional)'),
            ),
          ],
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

              await widget.database.insertLocation(
                LocationsCompanion.insert(
                  name: _nameController.text,
                  description: drift.Value(_descriptionController.text.isEmpty
                      ? null
                      : _descriptionController.text),
                ),
              );

              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              debugPrint('Error saving location: $e');
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
