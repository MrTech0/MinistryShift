import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:ministry_shift/data/database/app_database.dart';

class BackupService {
  static const String appVersion = '1.0.0';

  /// Resolves the host OS user's home directory path.
  static String getHomeDirectory() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    return Platform.environment['HOME'] ?? '/';
  }

  /// Resolves the current target directory for automatic backups.
  static Future<Directory> getBackupDirectory(AppDatabase database) async {
    final customPath = await database.getMetadataValue('backup_directory');
    if (customPath != null && customPath.isNotEmpty) {
      return Directory(customPath);
    }
    final homeDir = getHomeDirectory();
    return Directory(p.join(homeDir, 'MinistryShift_Backups'));
  }

  /// Pads numeric datetime components to 2 digits.
  static String _pad(int value) => value.toString().padLeft(2, '0');

  /// Runs the automatic encrypted database backup routine via VACUUM INTO.
  static Future<File> runBackup(AppDatabase database) async {
    final backupDir = await getBackupDirectory(database);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final now = DateTime.now();
    final timestamp = '${_pad(now.day)}_${_pad(now.hour)}_${_pad(now.minute)}_${_pad(now.second)}';
    final backupFile = File(p.join(backupDir.path, 'MinistryShift_AutoBackup_v${appVersion}_$timestamp.db'));

    // SQLite/Drift safe vacuum copy statement (maintains encryption)
    final escapedPath = backupFile.path.replaceAll("'", "''");
    await database.customStatement("VACUUM INTO '$escapedPath';");

    // Enforce the 7-day rolling retention policy
    await cleanOldBackups(backupDir);

    return backupFile;
  }

  /// Runs a manual backup to the user's chosen custom target file path.
  static Future<void> runManualBackup(AppDatabase database, String targetPath) async {
    final file = File(targetPath);
    // Ensure parent directory exists
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // SQLite/Drift safe vacuum copy statement (maintains encryption)
    final escapedPath = file.path.replaceAll("'", "''");
    await database.customStatement("VACUUM INTO '$escapedPath';");
  }

  /// Scans the backup folder and deletes files matching the backup format older than 7 days.
  static Future<void> cleanOldBackups(Directory backupDir) async {
    if (!await backupDir.exists()) return;
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    await for (final entity in backupDir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        // Only automatically clean up AutoBackups and older format names
        if (name.startsWith('MinistryShift_AutoBackup_') ||
            name.startsWith('ministry_shift_backup_')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sevenDaysAgo)) {
            try {
              await entity.delete();
            } catch (_) {
              // Ignore temporary locks or permission glitches during cleanup
            }
          }
        }
      }
    }
  }
}
