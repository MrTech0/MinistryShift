import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:ministry_shift/presentation/calendar/calendar_page.dart';
import 'package:ministry_shift/presentation/preachers/preachers_page.dart';
import 'package:ministry_shift/presentation/locations/locations_page.dart';
import 'package:ministry_shift/presentation/settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  List<Widget> get _pages => const [
        CalendarPage(),
        PreachersPage(),
        LocationsPage(),
        SettingsPage(),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authService = context.watch<AuthService>();

    return Scaffold(
      body: Row(
        children: [
          // Left: Side Navigation Rail (Desktop friendly)
          NavigationRail(
            selectedIndex: _selectedIndex,
            labelType: NavigationRailLabelType.all,
            backgroundColor: colorScheme.surfaceVariant.withOpacity(0.2),
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            leading: Column(
              children: [
                const SizedBox(height: 16),
                CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  radius: 24,
                  child: Icon(
                    Icons.shield_outlined,
                    color: colorScheme.onPrimary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: IconButton(
                    tooltip: 'Cerrar Sesión',
                    icon: Icon(Icons.logout, color: colorScheme.error),
                    onPressed: () {
                      context.read<AuthService>().logout();
                    },
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: Text('Calendario'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Predicadores'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: Text('Ubicaciones'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Configuración'),
              ),
            ],
          ),
          
          // Right: Content Page
          Expanded(
            child: Container(
              color: colorScheme.surface,
              child: _pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }
}
