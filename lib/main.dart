import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:ministry_shift/core/security/auth_service.dart';
import 'package:ministry_shift/core/backup/backup_service.dart';
import 'package:ministry_shift/presentation/auth/onboarding_page.dart';
import 'package:ministry_shift/presentation/auth/login_page.dart';
import 'package:ministry_shift/presentation/home/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  
  // Initialize window_manager only on actual native platform instances (not tests)
  if (!Platform.environment.containsKey('FLUTTER_TEST')) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setPreventClose(true);
    });
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthService()..checkDatabaseState(),
      child: const MinistryShiftApp(),
    ),
  );
}

class MinistryShiftApp extends StatefulWidget {
  const MinistryShiftApp({super.key});

  @override
  State<MinistryShiftApp> createState() => _MinistryShiftAppState();
}

class _MinistryShiftAppState extends State<MinistryShiftApp> with WindowListener {
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    setState(() => _isClosing = true);
    
    // Give the UI a moment to paint the closing overlay
    await Future.delayed(const Duration(milliseconds: 150));

    final authService = context.read<AuthService>();
    final db = authService.database;
    if (db != null) {
      try {
        // Enforce the automated encrypted backup on close
        await BackupService.runBackup(db);
        await authService.logout();
      } catch (e) {
        debugPrint('Error during auto-backup: $e');
      }
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    if (_isClosing) {
      return MaterialApp(
        title: 'MinistryShift',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.light),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
        ),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.teal),
                SizedBox(height: 24),
                Text(
                  'Cerrando aplicación...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Guardando copias de seguridad de forma segura...',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final authService = context.watch<AuthService>();

    return MaterialApp(
      title: 'MinistryShift',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
      ],
      locale: const Locale('es', 'ES'),
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          filled: true,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          filled: true,
        ),
      ),
      home: _getHomeWidget(authService.state),
    );
  }

  Widget _getHomeWidget(AuthState state) {
    switch (state) {
      case AuthState.initial:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Cargando base de datos segura...',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        );
      case AuthState.onboarding:
        return const OnboardingPage();
      case AuthState.locked:
        return const LoginPage();
      case AuthState.authenticated:
        return const HomePage();
    }
  }
}
