import 'dart:convert';
import 'dart:io';
import 'package:ministry_shift/data/database/app_database.dart';
import 'package:ministry_shift/core/backup/backup_service.dart';

class UpdateService {
  static const String latestReleaseUrl =
      'https://api.github.com/repos/polca/MinistryShift/releases/latest';

  /// Queries GitHub Releases API using native HttpClient to fetch the latest version tag.
  /// Throws an exception if there is a connection/network failure.
  static Future<String?> checkLatestVersion() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(latestReleaseUrl));
      request.headers.set('User-Agent', 'MinistryShift-Updater');
      
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        return data['tag_name'] as String?;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Triggers a backup first, then launches the installer downloaded from GitHub Releases.
  static Future<bool> performUpdate({
    required AppDatabase database,
    required String downloadUrl,
    required String targetPath,
  }) async {
    try {
      // 1. Force encrypted backup prior to executing update
      await BackupService.runBackup(database);

      // 2. Download release binary
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();
      
      if (response.statusCode != 200) return false;

      final file = File(targetPath);
      final sink = file.openWrite();
      await response.pipe(sink);

      // 3. Launch the installer process in Windows
      if (Platform.isWindows) {
        await Process.start('cmd.exe', ['/c', 'start', '', targetPath], mode: ProcessStartMode.detached);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
