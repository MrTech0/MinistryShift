import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:ministry_shift/data/database/app_database.dart';
import 'package:ministry_shift/presentation/calendar/widgets/shift_dialog.dart';
import 'package:ministry_shift/presentation/calendar/widgets/substitution_dialog.dart';
import 'package:ministry_shift/core/utils/pdf_exporter.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  bool _isWeeklyView = false;

  final List<String> _months = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
  ];

  final List<String> _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  void _addShift() {
    showDialog(
      context: context,
      builder: (context) => ShiftDialog(
        initialDate: _selectedDate,
      ),
    );
  }

  Future<void> _exportPdfWithOptions(List<ShiftWithPersonnel> shifts) async {
    final option = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exportar PDF del Mes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Selecciona qué turnos deseas incluir en el archivo PDF exportado:'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.shopping_cart_outlined, color: Colors.teal),
                title: const Text('Solo turnos con exhibidor'),
                subtitle: const Text('Excluye las salidas de predicación sin carrito.'),
                onTap: () => Navigator.pop(context, 'exhibidor_only'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.directions_walk_outlined, color: Colors.teal),
                title: const Text('Todos los turnos'),
                subtitle: const Text('Incluye exhibidores y salidas a la predicación.'),
                onTap: () => Navigator.pop(context, 'all'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (option == null || !mounted) return;

    // Filter shifts based on option
    final filteredShifts = option == 'exhibidor_only'
        ? shifts.where((s) => s.shift.type == 'exhibidor').toList()
        : shifts;

    await PdfExporter.exportMonthlySchedule(
      context: context,
      monthName: _months[_currentMonth.month - 1],
      year: _currentMonth.year,
      shifts: filteredShifts,
      exportType: option,
    );
  }

  void _substitutePreacher(Shift shift, String role, Preacher currentPreacher) {
    showDialog(
      context: context,
      builder: (context) => SubstitutionDialog(
        shift: shift,
        role: role,
        preacherToReplace: currentPreacher,
      ),
    );
  }

  int _getDaysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  int _getStartWeekday(DateTime date) {
    return DateTime(date.year, date.month, 1).weekday;
  }

  Widget _buildCalendarHeader(ColorScheme colorScheme, ThemeData theme, double width) {
    final title = '${_months[_currentMonth.month - 1]} ${_currentMonth.year}';
    final titleStyle = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: colorScheme.onSurface,
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _previousMonth,
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _nextMonth,
        ),
        const SizedBox(width: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Mensual')),
            ButtonSegment(value: true, label: Text('Semanal')),
          ],
          selected: {_isWeeklyView},
          onSelectionChanged: (val) {
            setState(() => _isWeeklyView = val.first);
          },
        ),
      ],
    );

    if (width < 650) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: controls,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: titleStyle),
        controls,
      ],
    );
  }

  Widget _buildDetailsPanel({
    required List<ShiftWithPersonnel> selectedShifts,
    required List<ShiftWithPersonnel> shifts,
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isNarrow,
  }) {
    final title = 'Turnos para el ${_selectedDate.day} de ${_months[_selectedDate.month - 1]}';
    final db = context.read<AuthService>().database!;

    final content = selectedShifts.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 48, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  const Text(
                    'No hay turnos planificados.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Añade un turno usando el botón inferior.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          )
        : ListView.builder(
            shrinkWrap: isNarrow,
            physics: isNarrow ? const NeverScrollableScrollPhysics() : const ScrollPhysics(),
            itemCount: selectedShifts.length,
            itemBuilder: (context, index) {
              final s = selectedShifts[index];
              final personnelCount = s.assignedPreachers.length + (s.captain != null ? 1 : 0);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.formattedTime,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                color: colorScheme.primary,
                                tooltip: 'Editar Turno',
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => ShiftDialog(
                                      initialDate: s.shift.date,
                                      editShift: s,
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                color: colorScheme.error,
                                tooltip: 'Eliminar Turno',
                                onPressed: () async {
                                  await db.deleteShift(s.shift.id);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.location.name,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            s.shift.type == 'exhibidor'
                                ? Icons.shopping_cart_outlined
                                : Icons.directions_walk_outlined,
                            size: 16,
                            color: s.shift.type == 'exhibidor' ? colorScheme.primary : colorScheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.shift.type == 'exhibidor' ? 'Exhibidor / Carrito' : 'Salida a la Predicación',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: s.shift.type == 'exhibidor' ? colorScheme.primary : colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (s.shift.type == 'exhibidor' && s.captain != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Capitán: ${s.captain!.firstName} ${s.captain!.lastName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.swap_horiz, size: 16),
                              tooltip: 'Sustituir Capitán',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _substitutePreacher(s.shift, 'captain', s.captain!),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        s.shift.type == 'exhibidor' ? 'Publicadores:' : 'Predicadores asignados:',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      ...s.assignedPreachers.map((p) => Padding(
                            padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline, size: 14),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${p.firstName} ${p.lastName}',
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.swap_horiz, size: 16),
                                  tooltip: 'Sustituir',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _substitutePreacher(s.shift, 'publisher', p),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 12),
                      if (s.shift.type == 'exhibidor') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Capacidad: $personnelCount personas (${personnelCount > 4 ? "2 carritos" : "1 carrito"})',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Total: $personnelCount personas asignadas',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );

    final actionButtons = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: shifts.isEmpty
              ? null
              : () => _exportPdfWithOptions(shifts),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Exportar PDF del Mes'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _addShift,
          icon: const Icon(Icons.add),
          label: const Text('Nuevo Turno'),
        ),
      ],
    );

    if (isNarrow) {
      return Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.15),
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 24),
            actionButtons,
          ],
        ),
      );
    }

    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(child: content),
          const SizedBox(height: 16),
          actionButtons,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AuthService>().database;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (db == null) {
      return const Center(child: Text('Base de datos no disponible.'));
    }

    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);

    return Scaffold(
      body: StreamBuilder<List<ShiftWithPersonnel>>(
        stream: db.watchShiftsForMonth(firstDayOfMonth),
        builder: (context, snapshot) {
          final shifts = snapshot.data ?? [];
          
          final selectedShifts = shifts.where((s) {
            final d = s.shift.date;
            return d.year == _selectedDate.year &&
                d.month == _selectedDate.month &&
                d.day == _selectedDate.day;
          }).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 950;

              if (isNarrow) {
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            _buildCalendarHeader(colorScheme, theme, constraints.maxWidth),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 400,
                              child: !_isWeeklyView
                                  ? _buildMonthlyGrid(shifts, colorScheme)
                                  : _buildWeeklyGrid(shifts, colorScheme),
                            ),
                          ],
                        ),
                      ),
                      _buildDetailsPanel(
                        selectedShifts: selectedShifts,
                        shifts: shifts,
                        colorScheme: colorScheme,
                        theme: theme,
                        isNarrow: true,
                      ),
                    ],
                  ),
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          _buildCalendarHeader(colorScheme, theme, constraints.maxWidth * 0.7),
                          const SizedBox(height: 24),
                          Expanded(
                            child: !_isWeeklyView
                                ? _buildMonthlyGrid(shifts, colorScheme)
                                : _buildWeeklyGrid(shifts, colorScheme),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildDetailsPanel(
                    selectedShifts: selectedShifts,
                    shifts: shifts,
                    colorScheme: colorScheme,
                    theme: theme,
                    isNarrow: false,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMonthlyGrid(List<ShiftWithPersonnel> shifts, ColorScheme colorScheme) {
    final startDay = _getStartWeekday(_currentMonth);
    final daysNum = _getDaysInMonth(_currentMonth);

    final offset = startDay - 1;
    final totalCells = offset + daysNum;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _weekdays
              .map((w) => Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.25,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              if (index < offset) {
                return const SizedBox.shrink();
              }
              final day = index - offset + 1;
              final cellDate = DateTime(_currentMonth.year, _currentMonth.month, day);
              final isSelected = cellDate.year == _selectedDate.year &&
                  cellDate.month == _selectedDate.month &&
                  cellDate.day == _selectedDate.day;

              final dayShifts = shifts.where((s) {
                final d = s.shift.date;
                return d.year == cellDate.year && d.month == cellDate.month && d.day == day;
              }).toList();

              return InkWell(
                onTap: () {
                  setState(() => _selectedDate = cellDate);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.surfaceVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 6,
                        left: 8,
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (dayShifts.isNotEmpty)
                        Positioned(
                          bottom: 6,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? colorScheme.onPrimary : colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${dayShifts.length}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? colorScheme.primary : colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyGrid(List<ShiftWithPersonnel> shifts, ColorScheme colorScheme) {
    final weekdayOffset = _selectedDate.weekday - 1;
    final weekStart = _selectedDate.subtract(Duration(days: weekdayOffset));

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: 7,
            itemBuilder: (context, index) {
              final day = weekStart.add(Duration(days: index));
              final isToday = day.year == _selectedDate.year &&
                  day.month == _selectedDate.month &&
                  day.day == _selectedDate.day;

              final dayShifts = shifts.where((s) {
                final d = s.shift.date;
                return d.year == day.year && d.month == day.month && d.day == day.day;
              }).toList();

              return InkWell(
                onTap: () {
                  setState(() => _selectedDate = day);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isToday
                        ? colorScheme.primaryContainer.withOpacity(0.4)
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _weekdays[index],
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isToday ? colorScheme.primary : colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              '${day.day}/${day.month}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: dayShifts.isEmpty
                            ? const Text('Sin turnos', style: TextStyle(color: Colors.grey, fontSize: 13))
                            : Wrap(
                                spacing: 8,
                                children: dayShifts.map<Widget>((s) {
                                  return Chip(
                                    label: Text('${s.shift.startTime} @ ${s.location.name}', style: const TextStyle(fontSize: 12)),
                                    backgroundColor: colorScheme.surfaceVariant,
                                    side: BorderSide(color: colorScheme.outlineVariant),
                                  );
                                }).toList(),
                              ),
                      ),
                      Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
