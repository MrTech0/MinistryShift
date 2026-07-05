import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:ministry_shift/core/backup/backup_service.dart';
import 'package:ministry_shift/core/update/update_service.dart';
import 'package:ministry_shift/data/database/app_database.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<File> _autoBackupsList = [];
  String _backupDirPath = '';
  String _pdfViewerMode = 'app';
  bool _isLoadingBackups = false;
  bool _isPerformingManualBackup = false;
  bool _isCheckingUpdate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadBackupSettingsAndFiles();
  }

  Future<void> _loadBackupSettingsAndFiles() async {
    final db = context.read<AuthService>().database;
    if (db == null) return;

    setState(() => _isLoadingBackups = true);
    try {
      final backupDir = await BackupService.getBackupDirectory(db);
      final mode = await db.getMetadataValue('pdf_viewer_mode') ?? 'app';
      setState(() {
        _backupDirPath = backupDir.path;
        _pdfViewerMode = mode;
      });

      if (await backupDir.exists()) {
        final list = await backupDir.list().toList();
        final files = list
            .whereType<File>()
            .where((f) {
              final name = p.basename(f.path);
              // Only display automatic backups (or old backups) in the history list
              return name.startsWith('MinistryShift_AutoBackup_') ||
                  name.startsWith('ministry_shift_backup_');
            })
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path)); // Newest first
        setState(() => _autoBackupsList = files);
      } else {
        setState(() => _autoBackupsList = []);
      }
    } catch (_) {}
    setState(() => _isLoadingBackups = false);
  }

  Future<void> _changeBackupDirectory() async {
    final db = context.read<AuthService>().database;
    if (db == null) return;

    try {
      final selectedPath = await FilePicker.getDirectoryPath(
        dialogTitle: 'Selecciona la carpeta para copias automáticas',
      );
      if (selectedPath != null && selectedPath.isNotEmpty) {
        await db.setMetadataValue('backup_directory', selectedPath);
        await _loadBackupSettingsAndFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Directorio de copias automáticas cambiado a: $selectedPath'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cambiar directorio: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _pad(int value) => value.toString().padLeft(2, '0');

  Future<void> _triggerManualBackup() async {
    final db = context.read<AuthService>().database;
    if (db == null) return;

    setState(() => _isPerformingManualBackup = true);
    try {
      final now = DateTime.now();
      final defaultFilename =
          'MinistryShift_ManualBackup_v${BackupService.appVersion}_${_pad(now.day)}_${_pad(now.hour)}_${_pad(now.minute)}_${_pad(now.second)}.db';

      // Prompt the user where to save the manual backup
      final selectedPath = await FilePicker.saveFile(
        dialogTitle: 'Guardar copia de seguridad manual',
        fileName: defaultFilename,
        type: FileType.any,
      );

      if (selectedPath != null && selectedPath.isNotEmpty) {
        await BackupService.runManualBackup(db, selectedPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copia manual guardada con éxito en: $selectedPath'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar copia manual: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
    setState(() => _isPerformingManualBackup = false);
  }

  Future<void> _restoreBackupFlow(File backupFile) async {
    final authService = context.read<AuthService>();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Show confirmation dialog with master password input field
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Restaurar Copia de Seguridad'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Estás seguro de que deseas restaurar la copia de seguridad:\n"${p.basename(backupFile.path)}"?',
                ),
                const SizedBox(height: 12),
                const Text(
                  'ATENCIÓN: Esto sobrescribirá todos los datos actuales de la aplicación. Esta acción no se puede deshacer.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña maestra de la copia',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, introduce la contraseña';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Restaurar y Sobrescribir'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      // Show loading spinner
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.teal)),
      );

      final success = await authService.restoreBackup(backupFile, passwordController.text);

      if (mounted) {
        Navigator.pop(context); // Close loading spinner
      }

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copia de seguridad restaurada con éxito.'),
              backgroundColor: Colors.teal,
            ),
          );
        }
        await _loadBackupSettingsAndFiles();
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Error de Restauración'),
              content: const Text(
                'No se pudo restaurar la copia de seguridad. Asegúrate de que la contraseña maestra ingresada sea correcta y el archivo sea una copia de base de datos válida.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  Future<void> _restoreFromExternalFile() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Selecciona una copia de seguridad para restaurar',
        type: FileType.any,
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await _restoreBackupFlow(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir explorador: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _checkSoftwareUpdate() async {
    setState(() => _isCheckingUpdate = true);
    try {
      final version = await UpdateService.checkLatestVersion();
      setState(() => _isCheckingUpdate = false);

      if (!mounted) return;

      const currentVersion = BackupService.appVersion;

      if (version == null || version == currentVersion || version == 'v$currentVersion') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Estás en la versión más reciente (v$currentVersion). No hay nuevas actualizaciones disponibles.'),
            backgroundColor: Colors.teal,
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Actualización Disponible'),
              content: Text('Se ha encontrado una nueva versión: $version. ¿Deseas descargarla?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Más tarde'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Función de descarga integrada en la release.')),
                    );
                  },
                  child: const Text('Actualizar'),
                ),
              ],
            );
          },
        );
      }
    } catch (_) {
      setState(() => _isCheckingUpdate = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo conectar con el servidor. No hay conexión a Internet.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _resetAppFlow() async {
    final authService = context.read<AuthService>();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('¿Inicializar de cero la aplicación?'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ATENCIÓN: Esta acción eliminará permanentemente todos tus predicadores, ubicaciones, turnos y configuraciones actuales de este dispositivo.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Se recomienda realizar una copia de seguridad manual antes de proceder si deseas conservar tus datos.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: confirmController,
                  decoration: const InputDecoration(
                    labelText: 'Escribe RESTABLECER para confirmar',
                    prefixIcon: Icon(Icons.warning_amber),
                  ),
                  validator: (value) {
                    if (value != 'RESTABLECER') {
                      return 'Debes escribir RESTABLECER en mayúsculas';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Eliminar Todo y Reiniciar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.teal)),
      );

      final success = await authService.resetDatabase();

      if (mounted) {
        Navigator.pop(context); // Close loading spinner
      }

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aplicación restablecida con éxito.'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Error al restablecer la aplicación.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteBackup(File file) async {
    try {
      await file.delete();
      await _loadBackupSettingsAndFiles();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configuración del Sistema',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              
              // 1. Automatic Backups Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Copias de Seguridad Automáticas',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Se generan automáticamente cada vez que cierras la aplicación.',
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _restoreFromExternalFile,
                                icon: const Icon(Icons.settings_backup_restore),
                                label: const Text('Restaurar desde Archivo...'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: _changeBackupDirectory,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Cambiar Carpeta'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_shared, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                _backupDirPath,
                                style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                      Text(
                        'Historial de Copias Automáticas (Últimos 7 días)',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _isLoadingBackups
                            ? const Center(child: CircularProgressIndicator())
                            : _autoBackupsList.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.history, size: 36, color: colorScheme.onSurfaceVariant),
                                        const SizedBox(height: 8),
                                        const Text('No se encontraron copias automáticas.'),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _autoBackupsList.length,
                                    separatorBuilder: (_, __) => const Divider(),
                                    itemBuilder: (context, index) {
                                      final file = _autoBackupsList[index];
                                      final filename = p.basename(file.path);
                                      final sizeKb = (file.lengthSync() / 1024).toStringAsFixed(1);

                                      return ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          backgroundColor: colorScheme.secondaryContainer,
                                          radius: 16,
                                          child: Icon(Icons.backup, size: 16, color: colorScheme.onSecondaryContainer),
                                        ),
                                        title: Text(filename, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                        subtitle: Text('Tamaño: $sizeKb KB'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.settings_backup_restore, size: 18),
                                              color: colorScheme.primary,
                                              onPressed: () => _restoreBackupFlow(file),
                                              tooltip: 'Restaurar esta copia',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 18),
                                              color: colorScheme.error,
                                              onPressed: () => _deleteBackup(file),
                                              tooltip: 'Eliminar copia',
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 2. Manual Backup Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      const Icon(Icons.save_as_outlined, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Copia de Seguridad Manual',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Crea un respaldo de tus datos en el momento y la ruta que decidas.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: _isPerformingManualBackup ? null : _triggerManualBackup,
                        icon: _isPerformingManualBackup
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Guardar Copia Manual...'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Preferencias de PDF Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Visualizador de PDF',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Elige si prefieres previsualizar los archivos PDF dentro de la app o con el visor del sistema (ej. Adobe Reader).',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'app',
                            icon: Icon(Icons.fit_screen_outlined),
                            label: Text('Visor Integrado'),
                          ),
                          ButtonSegment(
                            value: 'system',
                            icon: Icon(Icons.launch_outlined),
                            label: Text('Visor del Sistema'),
                          ),
                        ],
                        selected: {_pdfViewerMode},
                        onSelectionChanged: (val) async {
                          final db = context.read<AuthService>().database;
                          if (db == null) return;
                          final newMode = val.first;
                          setState(() => _pdfViewerMode = newMode);
                          await db.setMetadataValue('pdf_viewer_mode', newMode);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 3. Software Updates Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      const Icon(Icons.system_update_alt_outlined, size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Actualización de Software',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Versión instalada actual: v1.0.0. Consulta si hay parches de estabilidad.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _isCheckingUpdate ? null : _checkSoftwareUpdate,
                        icon: _isCheckingUpdate
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Buscar Actualizaciones'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 4. Reset App Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.error.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_outlined, size: 36, color: colorScheme.error),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inicializar Aplicación de Cero',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Elimina la base de datos cifrada y te devuelve a la pantalla de registro inicial.',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
                        onPressed: _resetAppFlow,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Restablecer de Fábrica...'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
