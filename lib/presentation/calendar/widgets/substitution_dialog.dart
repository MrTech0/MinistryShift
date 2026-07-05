import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:ministry_shift/data/database/app_database.dart';
import 'package:ministry_shift/core/scheduler/substitution_service.dart';

class SubstitutionDialog extends StatefulWidget {
  final Shift shift;
  final String role; // 'captain' or 'publisher'
  final Preacher preacherToReplace;

  const SubstitutionDialog({
    super.key,
    required this.shift,
    required this.role,
    required this.preacherToReplace,
  });

  @override
  State<SubstitutionDialog> createState() => _SubstitutionDialogState();
}

class _SubstitutionDialogState extends State<SubstitutionDialog> {
  List<PreacherLraRecommendation> _candidates = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    final db = context.read<AuthService>().database;
    if (db == null) return;

    final subService = SubstitutionService(db);
    try {
      final list = await subService.getLraCandidates(
        targetDate: widget.shift.date,
        requireCaptain: widget.role == 'captain',
        requirePublisher: widget.role == 'publisher',
      );

      // Exclude all preachers already assigned to this specific shift
      final assigned = await (db.select(db.shiftAssignments)
            ..where((sa) => sa.shiftId.equals(widget.shift.id)))
          .get();
      final assignedIds = assigned.map((a) => a.preacherId).toSet();
      if (widget.shift.captainId != null) {
        assignedIds.add(widget.shift.captainId!);
      }

      setState(() {
        _candidates = list.where((c) => !assignedIds.contains(c.preacher.id)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar candidatos.';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectCandidate(Preacher newPreacher) async {
    final db = context.read<AuthService>().database;
    if (db == null) return;

    setState(() => _isLoading = true);

    try {
      if (widget.role == 'captain') {
        // Update captain on the shift directly
        await (db.update(db.shifts)
              ..where((s) => s.id.equals(widget.shift.id)))
            .write(ShiftsCompanion(captainId: Value(newPreacher.id)));
      } else {
        // Update shift assignment for the specific preacher
        await (db.update(db.shiftAssignments)
              ..where((sa) => sa.shiftId.equals(widget.shift.id) & sa.preacherId.equals(widget.preacherToReplace.id)))
            .write(ShiftAssignmentsCompanion(preacherId: Value(newPreacher.id)));
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al realizar la sustitución.';
      });
    }
  }

  String _formatLastAssigned(DateTime? date) {
    if (date == null) return 'Nunca';
    final diff = DateTime.now().difference(date).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return 'Hace $diff días (${date.day}/${date.month}/${date.year})';
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
      title: Text('Sustituir a ${widget.preacherToReplace.firstName}'),
      content: SizedBox(
        width: 450,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rol: ${widget.role == "captain" ? "Capitán" : "Publicador de Carrito"}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Recomendaciones del motor "Menos Asignado Recientemente" (LRA):',
              style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: TextStyle(color: colorScheme.error)),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _candidates.isEmpty
                  ? const Center(child: Text('No hay candidatos disponibles para esta fecha.'))
                  : Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        itemCount: _candidates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final cand = _candidates[index];
                          final p = cand.preacher;
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${p.firstName} ${p.lastName}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('Última vez: ${_formatLastAssigned(cand.lastAssignedDate)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.swap_horiz),
                              tooltip: 'Asignar como sustituto',
                              onPressed: () => _selectCandidate(p),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
