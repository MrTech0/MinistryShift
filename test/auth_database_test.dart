import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ministry_shift/core/security/auth_service.dart';

void main() {
  late Directory tempDir;
  late File tempDbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ministry_shift_test_');
    tempDbFile = File(p.join(tempDir.path, 'test_database.sqlite'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AuthService & AppDatabase Encryption Tests', () {
    test('Onboarding database checks state and initializes successfully', () async {
      final authService = AuthService(overrideDbFile: tempDbFile);

      // 1. Initially check state on clean slate -> should be onboarding
      await authService.checkDatabaseState();
      expect(authService.state, AuthState.onboarding);
      expect(authService.database, isNull);

      // 2. Register a password too short -> should fail
      var result = await authService.registerPassword('12345', '12345');
      expect(result, isFalse);
      expect(authService.errorMessageKey, 'auth_password_min_length_error');
      expect(authService.state, AuthState.onboarding);

      // 3. Register mismatched passwords -> should fail
      result = await authService.registerPassword('password123', 'password1234');
      expect(result, isFalse);
      expect(authService.errorMessageKey, 'auth_passwords_mismatch_error');
      expect(authService.state, AuthState.onboarding);

      // 4. Register a valid password -> should succeed and transition to authenticated
      result = await authService.registerPassword('password123', 'password123');
      expect(result, isTrue);
      expect(authService.errorMessageKey, isNull);
      expect(authService.state, AuthState.authenticated);
      expect(authService.database, isNotNull);

      // Clean database connection
      await authService.logout();
    });

    test('Locked database login succeeds with correct password and fails with incorrect one', () async {
      // 1. Setup - Create database file and initialize with a password
      {
        final authSetup = AuthService(overrideDbFile: tempDbFile);
        final success = await authSetup.registerPassword('correct_pass', 'correct_pass');
        expect(success, isTrue);
        await authSetup.logout();
      }

      // 2. Open service on existing database -> checkDatabaseState should yield locked
      final authService = AuthService(overrideDbFile: tempDbFile);
      await authService.checkDatabaseState();
      expect(authService.state, AuthState.locked);

      // 3. Attempt login with wrong password -> should fail
      final failResult = await authService.login('wrong_pass');
      expect(failResult, isFalse);
      expect(authService.errorMessageKey, 'auth_invalid_password_error');
      expect(authService.state, AuthState.locked);

      // 4. Attempt login with correct password -> should succeed
      final successResult = await authService.login('correct_pass');
      expect(successResult, isTrue);
      expect(authService.errorMessageKey, isNull);
      expect(authService.state, AuthState.authenticated);
      expect(authService.database, isNotNull);

      // Clean up database connection
      await authService.logout();
    });

    test('SQL Injection-like passwords do not execute arbitrary code and are sanitized', () async {
      // 1. Initialize DB with a tricky password containing SQL characters
      const sqlInjectionPass = "pass' OR '1'='1";
      {
        final authSetup = AuthService(overrideDbFile: tempDbFile);
        final success = await authSetup.registerPassword(sqlInjectionPass, sqlInjectionPass);
        expect(success, isTrue);
        await authSetup.logout();
      }

      // 2. Open service on existing database
      final authService = AuthService(overrideDbFile: tempDbFile);
      await authService.checkDatabaseState();
      expect(authService.state, AuthState.locked);

      // 3. Attempt login with correct SQL Injection-like password -> should succeed
      final successResult = await authService.login(sqlInjectionPass);
      expect(successResult, isTrue);
      expect(authService.state, AuthState.authenticated);

      await authService.logout();
    });

    test('AuthService restoreBackup verification', () async {
      final tempDbFile = File(p.join(tempDir.path, 'active_db.sqlite'));
      final backupFile = File(p.join(tempDir.path, 'backup_db.sqlite'));
      const pass = 'correctPass123';

      final authService = AuthService(overrideDbFile: tempDbFile);
      await authService.checkDatabaseState();

      // 1. Initialize DB
      final registered = await authService.registerPassword(pass, pass);
      expect(registered, isTrue);
      expect(authService.state, AuthState.authenticated);

      // Create a value in metadata to verify restoration
      await authService.database!.setMetadataValue('test_key', 'original_value');

      // 2. Create the backup file
      final activeFile = await authService.databaseFile;
      await activeFile.copy(backupFile.path);

      // Modify the active database
      await authService.database!.setMetadataValue('test_key', 'changed_value');

      // 3. Restore with WRONG password -> should fail
      final failed = await authService.restoreBackup(backupFile, 'wrongPass');
      expect(failed, isFalse);
      
      // Verify database is untouched and still decryptable with correct password
      expect(authService.database, isNotNull);
      final valueAfterFail = await authService.database!.getMetadataValue('test_key');
      expect(valueAfterFail, equals('changed_value'));

      // 4. Restore with CORRECT password -> should succeed
      final success = await authService.restoreBackup(backupFile, pass);
      expect(success, isTrue);

      // Verify that the database is active and restored to the original value
      expect(authService.database, isNotNull);
      final valueAfterRestore = await authService.database!.getMetadataValue('test_key');
      expect(valueAfterRestore, equals('original_value'));

      await authService.logout();
    });

    test('AuthService resetDatabase verification', () async {
      final tempDbFile = File(p.join(tempDir.path, 'active_db_reset.sqlite'));
      const pass = 'resetPass123';

      final authService = AuthService(overrideDbFile: tempDbFile);
      await authService.checkDatabaseState();

      // 1. Initialize
      final registered = await authService.registerPassword(pass, pass);
      expect(registered, isTrue);
      expect(authService.state, AuthState.authenticated);
      expect(await tempDbFile.exists(), isTrue);

      // 2. Call reset
      final resetSuccess = await authService.resetDatabase();
      expect(resetSuccess, isTrue);

      // 3. Verify database file is deleted and state is onboarding
      expect(authService.state, AuthState.onboarding);
      expect(await tempDbFile.exists(), isFalse);
    });
  });
}
