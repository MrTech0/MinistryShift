import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ministry_shift/data/database/app_database.dart';

enum AuthState {
  initial,
  onboarding,
  locked,
  authenticated,
}

class AuthService extends ChangeNotifier {
  final File? overrideDbFile;

  AuthService({this.overrideDbFile});

  AuthState _state = AuthState.initial;
  AuthState get state => _state;

  AppDatabase? _database;
  AppDatabase? get database => _database;

  String? _errorMessageKey;
  String? get errorMessageKey => _errorMessageKey;

  File? _dbFile;

  /// Returns the Database File location.
  Future<File> get databaseFile async {
    if (overrideDbFile != null) return overrideDbFile!;
    if (_dbFile != null) return _dbFile!;
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _dbFile = File(p.join(directory.path, 'ministry_shift.sqlite'));
    return _dbFile!;
  }

  /// Initial checks to transition from [AuthState.initial] to [AuthState.onboarding] or [AuthState.locked].
  Future<void> checkDatabaseState() async {
    try {
      final file = await databaseFile;
      if (await file.exists()) {
        _state = AuthState.locked;
      } else {
        _state = AuthState.onboarding;
      }
    } catch (e) {
      _state = AuthState.onboarding;
    }
    notifyListeners();
  }

  /// Registers a master password for a new database.
  Future<bool> registerPassword(String password, String confirmPassword) async {
    _errorMessageKey = null;

    if (password.length < 6) {
      _errorMessageKey = 'auth_password_min_length_error';
      notifyListeners();
      return false;
    }

    if (password != confirmPassword) {
      _errorMessageKey = 'auth_passwords_mismatch_error';
      notifyListeners();
      return false;
    }

    try {
      final file = await databaseFile;
      
      // Ensure file doesn't exist to prevent accidental overwrites during onboarding
      if (await file.exists()) {
        await file.delete();
      }

      final conn = openConnection(file, password);
      final db = AppDatabase(conn);

      // Force Drift to execute schemas and create tables
      await db.initializeValidationToken();

      final verified = await db.verifyEncryptionToken();
      if (verified) {
        _database = db;
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        _errorMessageKey = 'auth_generic_db_error';
        await db.close();
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessageKey = 'auth_generic_db_error';
      notifyListeners();
      return false;
    }
  }

  /// Attempts to decrypt and open an existing database file using the password.
  Future<bool> login(String password) async {
    _errorMessageKey = null;

    try {
      final file = await databaseFile;
      if (!await file.exists()) {
        _state = AuthState.onboarding;
        _errorMessageKey = 'auth_generic_db_error';
        notifyListeners();
        return false;
      }

      final conn = openConnection(file, password);
      final db = AppDatabase(conn);

      final verified = await db.verifyEncryptionToken();
      if (verified) {
        _database = db;
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        _errorMessageKey = 'auth_invalid_password_error';
        await db.close();
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessageKey = 'auth_invalid_password_error';
      notifyListeners();
      return false;
    }
  }

  /// Validates and restores a database backup file, replacing the active database.
  Future<bool> restoreBackup(File backupFile, String password) async {
    _errorMessageKey = null;

    try {
      // 1. Verify that the backup file is valid and decryptable with the provided password
      final conn = openConnection(backupFile, password);
      final tempDb = AppDatabase(conn);
      final verified = await tempDb.verifyEncryptionToken();
      await tempDb.close();

      if (!verified) {
        _errorMessageKey = 'auth_invalid_password_error';
        return false;
      }

      // 2. Close current database connection
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      // 3. Overwrite current database file with the backup file
      final activeFile = await databaseFile;
      if (await activeFile.exists()) {
        await activeFile.delete();
      }
      await backupFile.copy(activeFile.path);

      // 4. Re-open connection to restored database using the validated password
      final newConn = openConnection(activeFile, password);
      _database = AppDatabase(newConn);
      _state = AuthState.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessageKey = 'auth_generic_db_error';
      // Attempt to reload current database state if possible
      await checkDatabaseState();
      notifyListeners();
      return false;
    }
  }

  /// Deletes the local database file and resets the app state back to onboarding.
  Future<bool> resetDatabase() async {
    try {
      // 1. Close active database connection
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      // 2. Delete database file
      final file = await databaseFile;
      if (await file.exists()) {
        await file.delete();
      }

      // 3. Reset state to onboarding
      _state = AuthState.onboarding;
      _errorMessageKey = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessageKey = 'auth_generic_db_error';
      notifyListeners();
      return false;
    }
  }

  /// Closes database connection and resets app authentication state.
  Future<void> logout() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _state = AuthState.locked;
    _errorMessageKey = null;
    notifyListeners();
  }
}
