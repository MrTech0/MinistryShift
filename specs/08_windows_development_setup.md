# SPEC-08: Windows Development Environment Provisioning

## Metadata
- **Status**: Approved
- **Approval**: User approved the written design on 2026-10-11.
- **Approved amendment**: User requested a single provisioning script and project-derived tool versions on 2026-10-11; this replaces the original embedded version pins.
- **Author**: Codex
- **Created Date**: 2026-10-11
- **Last Updated**: 2026-10-11
- **User-confirmed scope**: Existing checkout, Windows desktop with hot reload, existing editor.

---

## 1. Objectives & Scope

### 1.1 Summary
Provide a repeatable PowerShell provisioning command for a Windows 11 x64 developer workstation. Prepare this checkout to build, test, and run MinistryShift with `flutter run -d windows`. Windows desktop uses a native application with Flutter's debugging connection; this project does not require a web development server.

The script will live at `scripts/setup-windows-dev.ps1`. Documentation will replace the starter README with the actual prerequisites, provisioning commands, verification, and hot reload instructions.

### 1.2 Project Review and Toolchain

| Item | Repository evidence | Provisioning decision |
| :--- | :--- | :--- |
| Flutter / Dart | Exact Flutter version/channel are declared in the workflows; `pubspec.yaml` and `pubspec.lock` declare SDK constraints | Read the exact project Flutter version/channel at runtime. Resolve the archive, integrity metadata, and bundled Dart from the official release manifest. Let locked dependency restoration validate SDK/package constraints. |
| Native Windows compilation | `windows/CMakeLists.txt` builds a C++17 runner; plugins and SQLite native assets require compilation | Reuse a complete, stable Visual Studio 2019/2022/2026 installation recognized by Flutter. Otherwise install Visual Studio 2026 Build Tools with C++ tools, CMake, and Windows SDK. |
| Git | Flutter SDK tooling depends on Git; source control uses HTTPS | Reuse Git for Windows or install `Git.Git` from the official WinGet source. Do not change Git identity, credentials, SSH keys, or remotes. |
| Dependency resolution | `pubspec.lock` is committed | Use `flutter pub get --enforce-lockfile`; stop on lockfile incompatibility rather than updating packages. |
| Generated code | Drift declares `app_database.g.dart`; CI runs build_runner | Run `dart run build_runner build --delete-conflicting-outputs`. Protect uncommitted edits to tracked generated Dart files before generation. |
| Database | SQLite 3 native hooks use `source: sqlite3mc` | Let the locked Dart packages obtain their native assets. No external database service or standalone SQLite/SQLCipher installation. |
| Fonts | Arial assets are already checked in | No system font download or installation. |
| Java / JNI | CI installs Java 17; the locked JNI 1.0.0 plugin discovers JNI optionally in Flutter builds | Do not install Java for this Windows-only workflow. Preserve any existing JDK. A real debug build must catch problems caused by native plugins or existing toolchains. |
| Packaging | `release.yml` uses WiX 3 `heat`, `candle`, and `light` and produces MSI | WiX is outside this development-only setup. The workflow name and SPEC-02 still refer to MSIX and need a separate packaging documentation update. |

At the initial project review, Flutter 3.44.4's toolchain recognized the Visual Studio 18 2026 CMake generator and the Build Tools `Microsoft.VisualStudio.Workload.VCTools` workload. Provisioning now discovers the project-selected release instead of embedding that version. Build Tools avoids installing an additional editor; each selected Flutter SDK's validation/build determines actual compatibility.

### 1.3 Approach Selection
- **Selected**: One self-contained PowerShell provisioning script, WinGet for Git and Build Tools, and the project-selected official Flutter archive verified against its published SHA-256. This works with Windows PowerShell 5.1 and keeps the SDK consistent with CI without embedding tool versions in the script.
- **Alternative**: FVM for SDK management. Useful for teams maintaining several Flutter versions, but introduces a separate tool and project configuration that this repository does not currently use.
- **Alternative**: WinGet Configuration / DSC. Suitable for managed workstation fleets, but adds configuration providers and a newer WinGet requirement to a small, single-project setup.

### 1.4 Out of Scope
- Repository cloning, editor installation, Android SDK, emulators, Java installation, web targets, macOS setup, and MSI generation.
- Running installers on the current workstation as part of implementing or testing the script.
- GitHub authentication, repository security settings, release publication, and application business logic changes.

---

## 2. Functional Requirements

### 2.1 User Stories & Use Cases
- As a developer, I can provision an existing checkout on a clean Windows 11 x64 machine using Windows PowerShell 5.1 or PowerShell 7.
- As a developer, I can rerun provisioning and reuse valid tools without reinstalling them or duplicating PATH entries.
- As a developer, I can inspect missing requirements without installing tools or changing my environment.
- As a developer, I receive the exact command to launch the Windows application with hot reload after successful provisioning.

### 2.2 Functional Specifications

**Command interface**
- No arguments: provision prerequisites, restore project dependencies, generate code, check the Windows device, compile a debug build, and execute `flutter test`.
- `-CheckOnly`: inspect OS, architecture, checkout, available tools, SDK identity, and native toolchain files; return a missing-requirements report without downloads, environment changes, generated files, or invoking Flutter commands that can initialize caches.
- `-WhatIf`: display the actions that provisioning would perform, with no downloads, installations, PATH changes, Flutter commands, or project writes.
- `-FlutterDirectory <absolute-path>`: choose the SDK directory. Default: `%USERPROFILE%\develop\flutter-<project-version>`. Require a writable path without whitespace, reject a filesystem root and an occupied directory that is not the requested SDK, and never overwrite another SDK. A version upgrade naturally selects a new default directory.
- `-SkipValidation`: skip the debug build and test suite. Clearly report that the setup is prepared but compilation and tests are unverified. Version, dependency restoration, generation, and Windows device checks remain mandatory during provisioning.

**Preflight**
1. Resolve the project from the script's location, independent of the caller's current directory. Require `pubspec.yaml`, `pubspec.lock`, `windows/CMakeLists.txt`, and both font assets.
2. Require Windows 11 (build 22000 or later), an x64 OS, and a 64-bit PowerShell process. Reject Windows on ARM and unsupported hosts with actionable messages.
3. Read literal exact version/channel declarations from `subosito/flutter-action` steps in `.github/workflows/*.yml` and `*.yaml`. Require a single consistent selection on stable or beta. Reject missing, conflicting, or unsupported dynamic configuration instead of guessing. Read `environment.sdk` from pubspec; do not embed or duplicate its constraint. Ordinary numeric dependency/SDK updates must not require editing provisioning code.
4. Require WinGet only when a missing native prerequisite needs installation. If missing, explain how to install Microsoft's App Installer; do not execute a remote bootstrap script.
5. Detect existing Visual Studio instances with Microsoft's installed `vswhere`, including Build Tools, required workloads, MSVC x64/x86, CMake, Windows SDK, and completion/reboot status. A pending installer reboot blocks readiness.

**Provisioning**
- Invoke native commands using executable paths and argument arrays. Check every exit code; never use `Invoke-Expression` or evaluate downloaded text.
- Use exact WinGet package IDs and `--source winget`; retain WinGet hash validation. Explain package agreement acceptance in the README. Do not upgrade existing compatible tools automatically.
- For missing compiler tools, install the current stable `Microsoft.VisualStudio.BuildTools` WinGet package with `Microsoft.VisualStudio.Workload.VCTools` and recommended components, with no automatic restart or embedded version. An existing incomplete Build Tools instance may receive these components through the signed Microsoft installer; preserve existing Visual Studio IDE workloads. Flutter's readiness/build checks validate actual compatibility; existing tools remain under normal Visual Studio Installer security maintenance.
- Keep the main script under the developer's account. Only Microsoft installer operations may request UAC elevation. Never relaunch the entire setup under another administrator account.
- During provisioning, obtain the official Windows release manifest over HTTPS and select exactly the project version/channel and x64 architecture. Require valid SHA-256/revision metadata and an archive within the official Flutter download location. Verify the published SHA-256 before extracting or running it. Do not select another release when the requested version is absent. Read-only modes perform no network requests.
- Stage extraction in a unique temporary directory; publish it to the requested empty SDK directory only after integrity and layout checks. Remove only temporary content created by this invocation, after verifying the resolved cleanup target is inside that temporary directory. Preserve partial installations for diagnosis if safe cleanup cannot be established.
- Reuse an already installed project SDK when its cached version/channel and current Git revision agree. Provisioning additionally verifies the official release revision and runtime Flutter/Dart versions. Use absolute executable paths, independent of another Flutter or Dart in PATH. Detect and report conflicting PATH entries. Do not overwrite incompatible or unverifiable SDKs.
- Add the selected Flutter `bin` to the user's PATH only once. Preserve all unrelated user and machine PATH entries; update the current process for child commands. Do not use `setx`.
- Enable the Windows desktop target if needed, without changing other Flutter platforms or telemetry preferences. Prepare Windows SDK caches.
- Restore dependencies with the lockfile enforced, run generation, and verify Flutter reports a Windows device. Preserve and restore the caller's working directory using `try/finally`.
- Print `flutter run -d windows` at completion; explain `r` for hot reload, `R` for hot restart, and `q` to stop. Do not start an indefinite debug session during provisioning.

**Errors and results**
- Return 0 only when the requested checks pass; nonzero on missing requirements, download/hash failure, blocked installation, failed generation, compilation, or tests. Propagate a reboot-required outcome separately and tell the developer to reboot and rerun.
- Fail immediately on a bad hash, invalid SDK, or failed native command. Never continue to a success message after a failure.
- Use concise stage output. Report the selected SDK and compiler locations, validation status, and next command. Do not collect credentials or dump environment variables.

### 2.3 User Interface (UI) Strings (Spanish Translation Mapping)
No application UI is introduced. Source comments, help, diagnostics, and documentation are English, following the repository's technical language policy. The conversational walkthrough can be Spanish.

---

## 3. Data Models & Database Schemas

### 3.1 Table Definitions (Drift / SQLCipher)
No schema changes or application database creation. Dependency preparation must preserve the existing SQLite encryption hook.

### 3.2 Relations & Integrity
No migrations. The script must not open the application, modify a developer's database or backups, or run destructive Git cleanup/reset commands. Generated source changes are reported and remain reviewable.

---

## 4. Test / Harness Plan

### 4.1 Test Harness Structure
- Parse and run isolated PowerShell tests in both Windows PowerShell 5.1 and PowerShell 7.
- Mock downloads, installers, subprocesses, and PATH persistence. Use temporary fixtures for SDKs and checkouts; tests must not install software or alter the host PATH.
- Test functions for version validation, native command failure, PATH handling, SDK reuse, archive integrity, safe directory handling, and prerequisite planning.
- Document a separate clean Windows 11 x64 VM acceptance procedure. Mock tests and the developer's existing workstation do not prove a fresh installation works.

### 4.2 Test Scenarios (Unit & Integration)
- Already provisioned environment: no installer call, no SDK download, no duplicate PATH entry.
- Project version update: changed Flutter/Dart declarations are read without code edits; conflicting workflows stop early. Validate Windows CRLF, cached metadata/revision agreement, manifest architecture/hash selection, and a copied single script with no helper.
- Missing native tools: only the expected exact WinGet packages and components are requested.
- `-CheckOnly` and `-WhatIf`: zero download, installer, environment persistence, Flutter, or generation calls.
- Conflicting SDK, occupied directory, path containing spaces, unsupported OS/architecture, incomplete toolchain, and pending reboot: actionable failure without overwriting existing tools.
- Failed download, hash mismatch, installer cancellation/failure/reboot, and Flutter command failures: no false success and no subsequent dependent command.
- Checkout with spaces and caller in another directory: commands target the correct repository; caller's directory is restored.
- Modified tracked generated Dart source: stop before overwrite.
- VM acceptance: provision, compile Windows debug, pass `flutter test`, run the app with hot reload, then rerun provisioning to confirm prerequisite reuse.

---

## 5. Security, Performance & System Constraints

### 5.1 Security
- No secrets, elevated Flutter execution, execution-policy changes, antivirus exclusions, certificate bypasses, or download-and-execute pipelines.
- Use the project-selected official Flutter archive with its manifest integrity metadata and trusted WinGet source. Verify the signature of any directly invoked Visual Studio installer before requesting elevation.
- Check final absolute targets before recursive cleanup or SDK movement; never remove or replace a pre-existing SDK.
- The existing SQLCipher configuration and authentication tests remain unchanged.

### 5.2 Performance & Memory
- Downloads and compiler installation can take several gigabytes and substantial time. Show progress and stage transitions, use bounded network retries/timeouts, and preserve actionable installer errors.
- Reuse tool installations and Flutter/Pub caches. Extraction should stream from disk rather than loading the SDK archive into memory.
- No ongoing background process or scheduled task is created.

### 5.3 Reference Sources and Review Limits
- [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).
- [Flutter manual installation](https://docs.flutter.dev/install/manual).
- [Official Windows release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json), checked on 2026-10-11 for the SDK, bundled Dart, revision, and SHA-256.
- [Flutter 3.44.4 Visual Studio detection](https://github.com/flutter/flutter/blob/3.44.4/packages/flutter_tools/lib/src/windows/visual_studio.dart).
- [Microsoft Visual Studio installer parameters](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio).
- [Official WinGet Build Tools manifests](https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/VisualStudio/BuildTools).
- [Dart lockfile enforcement](https://dart.dev/tools/pub/cmd/pub-get).

This review inspected project configuration and official toolchain sources. Flutter is absent from the current command PATH, so no local Windows application build or test run was performed for this review. Script implementation and installation acceptance results must be recorded separately.
