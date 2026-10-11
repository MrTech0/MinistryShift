# MinistryShift

Flutter desktop application for ministry scheduling. The current development target is Windows x64; a macOS target also exists.

## Windows 11 development setup

Use an existing Git checkout, a 64-bit PowerShell, and your preferred editor. Run setup as your normal developer account, without opening PowerShell as administrator. Missing Git and C++ Build Tools are installed through Microsoft's WinGet source; their installers may request UAC elevation. Provisioning accepts the required WinGet source and package agreements.

The script reads the exact `flutter-version` and `channel` declared by `subosito/flutter-action` in the project's workflows. Update those declarations when updating Flutter; the provisioning script needs no version edits. All declarations must agree. The official Windows release manifest supplies the selected archive, SHA-256, Git revision, and bundled Dart version. Dart dependencies and SDK constraints are verified by locked dependency restoration.

Compatible Git and Visual Studio installations are reused. Missing Build Tools are installed from the current stable `Microsoft.VisualStudio.BuildTools` WinGet package with C++, CMake, and Windows SDK, without a version embedded in the script. The selected Flutter SDK and the final debug build verify actual compiler compatibility. Keep existing compiler security updates current through Visual Studio Installer.

From the repository root, preview the actions:

```powershell
.\scripts\setup-windows-dev.ps1 -WhatIf
```

Provision and validate:

```powershell
.\scripts\setup-windows-dev.ps1
```

Windows PowerShell 5.1 and PowerShell 7 are supported. If Windows PowerShell's default policy blocks local scripts, the launcher can select `RemoteSigned` for this process only; it does not change the user's or machine's persistent policy and does not override organizational Group Policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\setup-windows-dev.ps1
```

`scripts/setup-windows-dev.ps1` is the only provisioning script; it contains its own functions and requires no helper script or downloaded PowerShell module. It resolves the checkout from its own location, so it also works when invoked by absolute path from another directory.

### Options

| Option | Behavior |
| :--- | :--- |
| `-WhatIf` | Preview actions without downloads, installers, PATH changes, or Flutter execution. |
| `-CheckOnly` | Inspect prerequisites without initializing Flutter caches. Exit nonzero if requirements are missing. Does not prove compilation or tests pass. |
| `-FlutterDirectory C:\dev\flutter-project` | Select an absolute, writable SDK path without whitespace, semicolons, or junctions. Existing incompatible directories are protected. |
| `-SkipValidation` | Restore dependencies and generate code, but skip the debug build and application tests; report them as unverified. |

The default SDK directory is `%USERPROFILE%\develop\flutter-<project-version>`, so a project upgrade selects a separate directory and preserves the old SDK. Without an explicit directory, setup can reuse an SDK on PATH when its cached version and Git revision match the project. Provisioning also checks the official release revision and runtime versions. The script preserves unrelated PATH entries and adds Flutter to the user's PATH once. If another SDK takes priority in new terminals, use the absolute launch command printed by setup or select this SDK in your editor.

The supported workflow layout uses separate `uses`/`with` lines, unquoted input keys, and literal exact versions on `stable` or `beta`. Expressions, version ranges, `flutter-version-file`, inline/folded action declarations, and quoted/merged input keys are rejected explicitly. A Dart SDK constraint alone cannot identify the exact Flutter version. `-WhatIf` and `-CheckOnly` use local configuration/metadata and never query the release manifest. Normal provisioning needs access to the official manifest even when reusing an SDK.

Setup runs locked dependency restoration, Drift code generation, Windows device detection, `flutter build windows --debug`, and `flutter test`. Uncommitted generated `.g.dart` files block generation; commit or back up those edits first. Generated changes are left available for review with `git diff`. No Git cleanup or automatic stash occurs.

No editor, Android SDK, Java, WiX, database service, or system fonts are installed. SQLite encryption is configured by the existing `sqlite3mc` native hook; fonts are bundled in `assets/fonts`.

### Start development with hot reload

After setup, open a new terminal and select the provisioned SDK in your editor. From the repository root:

```powershell
flutter run -d windows
```

This launches the native Windows application and Flutter's debugging connection. Press `r` for hot reload, `R` for hot restart, and `q` to stop. There is no web development server or backend server to start for this target.

### Troubleshooting

- **Missing WinGet:** install/update [Microsoft App Installer](https://aka.ms/getwinget), reopen PowerShell, and rerun setup.
- **Reboot required:** setup returns exit code `3010`; restart Windows and rerun. It never restarts the computer automatically.
- **Compiler incomplete:** open Visual Studio Installer and inspect the C++ workload, CMake, Windows SDK, or pending installation. Setup may add required components to an existing Build Tools instance, while preserving IDE workloads.
- **Flutter doctor warnings:** Android/browser warnings are not requirements for Windows desktop. Resolve Windows and Visual Studio problems; the default debug build is the final compiler check.
- **Download failure or wrong hash:** setup stops before extraction/execution. Retry after fixing connectivity; do not bypass hash verification.
- **Application build failure:** retain the native command output and investigate the failed dependency. Provisioning does not patch project dependencies, disable antivirus, or change an existing JDK.

## Script tests and installation acceptance

The dependency-free harness uses temporary fixtures and mocked installers/downloads. It does not provision the host:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\scripts\tests\setup-windows-dev.tests.ps1
pwsh.exe -NoProfile -File .\scripts\tests\setup-windows-dev.tests.ps1
```

See [Windows development validation](docs/windows-development-validation.md) for clean-machine acceptance and the recorded verification limits. The approved behavior is documented in [SPEC-08](specs/08_windows_development_setup.md).
