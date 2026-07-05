# SPEC-03: Encrypted Backups and Auto-Updates

## Metadata
- **Status**: Draft
- **Author**: Spec Author (The Architect)
- **Created Date**: 2026-06-30
- **Last Updated**: 2026-06-30

---

## 1. Objectives & Scope

### 1.1 Summary
This specification outlines the backup and software update system. It details the automated generation of encrypted database backups to the user's HOME directory on app exit, the 7-day rolling retention policy, and the update engine checking GitHub Releases, including forcing a backup before executing updates.

### 1.2 Out of Scope
- Direct restoration UI inside the application (if needed, a backup file can be restored by manually replacing the main database file in the application support directory).
- Incremental database backups (only full backups are performed).

---

## 2. Functional Requirements

### 2.1 User Stories & Use Cases
- **Auto Backup on Close**: As a user, when I close the application, I want my data to be backed up to my home directory so that I do not lose it if my application files are corrupted or deleted.
- **7-Day Retention**: As a user, I want the backup system to clean up old backups so that it doesn't consume all my disk space over time.
- **Update Check**: As a user, when I launch the application, I want it to check for updates so that I can easily upgrade to the latest features.
- **Pre-Update Backup**: As a user updating the app, I want a backup to be generated automatically before the installer runs, so I can revert if the update fails.

### 2.2 Functional Specifications

#### 2.2.1 Backup Lifecycle
1. **Trigger**: Triggered when the application lifecycle detects it is closing (using Flutter's `AppLifecycleListener` or `WindowListener` from native window management plugins like `window_manager`).
2. **Execution**:
   - Locate user's HOME directory (`%USERPROFILE%` on Windows, `~` on macOS).
   - Target directory: `~/MinistryShift_Backups/`. Create it if it doesn't exist.
   - Backup Filename: `ministry_shift_backup_YYYYMMDD_HHMMSS.db`.
   - **Safe File Copy**: Instead of a simple file copy while the database is locked, execute SQLite's `VACUUM INTO 'path_to_backup_file'` query through Drift. This creates an exact, encrypted, and unfragmented copy of the database.
3. **Retention**:
   - List files in `~/MinistryShift_Backups/` matching `ministry_shift_backup_*.db`.
   - Sort them by creation time or name.
   - Retain only the backups created in the last 7 calendar days. Delete any files older than 7 days.

#### 2.2.2 Update Engine
1. **Trigger**: Occurs asynchronously on app launch (or manually via a button in settings).
2. **Process**:
   - Fetch metadata from GitHub Releases API: `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
   - Compare `tag_name` (e.g. `v1.1.0`) with the current application version (retrieved via `package_info_plus`).
   - If a new version is available, prompt the user in Spanish:
     - Title: `Actualización Disponible`
     - Subtitle: `Una nueva versión está disponible. ¿Deseas descargarla e instalarla? Se realizará una copia de seguridad automática.`
   - If user agrees:
     - Run the backup routine immediately (blocking action with loading spinner).
     - Download the `.msix` / installer binary to a temporary folder.
     - Run the installer executable in a detached process (using Dart `Process.start` with shell execute options).
     - Exit the current running application instance so the installer can replace the files.

### 2.3 User Interface (UI) Strings (Spanish Translation Mapping)

| English Key | Spanish UI Translation (es_ES) | Notes / Context |
| :--- | :--- | :--- |
| `update_available_title` | `Actualización Disponible` | Update dialog title |
| `update_available_message` | `Una nueva versión ({version}) está disponible. ¿Deseas actualizar ahora? Se creará una copia de seguridad primero.` | Description text |
| `update_btn_confirm` | `Actualizar` | Dialog confirm button |
| `update_btn_cancel` | `Más tarde` | Dialog cancel button |
| `update_backing_up` | `Realizando copia de seguridad de seguridad...` | Progress text |
| `update_downloading` | `Descargando actualización...` | Progress text |
| `update_error` | `Error al actualizar. Comprueba tu conexión a Internet.` | Error toast |

---

## 3. Data Models & Integrity

No database changes are required. The backup process uses the raw connection handler:
```dart
Future<void> createBackup(File targetFile) async {
  // Drift provides raw access to the underlying sqlite3 library
  await customStatement("VACUUM INTO '${targetFile.path.replaceAll("'", "''")}';");
}
```

---

## 4. Test / Harness Plan

### 4.1 Test Scenarios
- **Scenario 1 (Backup Execution)**:
  - Run a database instance, write metadata.
  - Invoke backup routing to a temp folder.
  - Verify that the backup file is created.
  - Verify that opening the backup file with the correct password works and contains the same metadata.
- **Scenario 2 (Retention Enforcement)**:
  - Create 10 dummy files in the backup directory with mocked timestamps (some 10 days old, some 2 days old).
  - Run the retention cleaner.
  - Verify that only files from the last 7 days remain.
- **Scenario 3 (Version Checker)**:
  - Mock the GitHub Releases HTTP endpoint.
  - Verify that if the remote version is greater (e.g. `v1.2.0` vs `v1.0.0`), the update alert triggers.
  - Verify that if the remote version is equal or lesser, no action is taken.

---

## 5. Security & System Constraints
- **Unencrypted Temporary Files**: No temporary plaintext databases are created. The `VACUUM INTO` command preserves the encryption configuration of the main database.
- **System Resource Usage**: Backup operations run asynchronously in background isolate connections to prevent locking the main UI thread.
