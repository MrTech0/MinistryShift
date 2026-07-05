import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:ministry_shift/presentation/locations/locations_page.dart';

void main() {
  late Directory tempDir;
  late File tempDbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('locations_ui_test_');
    tempDbFile = File(p.join(tempDir.path, 'test_db.sqlite'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Add location dialog saves successfully', (WidgetTester tester) async {
    final authService = AuthService(overrideDbFile: tempDbFile);
    await authService.registerPassword('test_pass', 'test_pass');
    expect(authService.state, AuthState.authenticated);

    // Build the LocationsPage widget
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AuthService>.value(
          value: authService,
          child: const LocationsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify "No hay ubicaciones registradas" is visible
    expect(find.text('No hay ubicaciones registradas.'), findsOneWidget);

    // Tap the "Añadir Ubicación" button to open dialog
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Verify dialog is open
    expect(find.text('Añadir Ubicación de Carrito'), findsOneWidget);

    // Enter location name
    await tester.enterText(find.byType(TextFormField).first, 'Parque Central');
    await tester.enterText(find.byType(TextFormField).last, 'Cerca de la fuente');
    await tester.pumpAndSettle();

    // Tap "Guardar"
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    // Verify dialog is closed (popped)
    expect(find.text('Añadir Ubicación de Carrito'), findsNothing);

    // Verify location is displayed on the screen
    expect(find.text('Parque Central'), findsOneWidget);
    expect(find.text('Cerca de la fuente'), findsOneWidget);
    
    await authService.logout();
  });
}
