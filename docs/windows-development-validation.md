# Windows Development Setup Validation

## Automated checks

Run `scripts/tests/windows-dev-tools.tests.ps1` using Windows PowerShell 5.1 and PowerShell 7. The harness needs no Pester or other downloaded framework. It creates only temporary fixtures, exercises real filesystem/native-command boundaries where practical, and simulates installers, SDK downloads, and persistent PATH changes.

Inspect the real entry point with `-WhatIf` and `-CheckOnly`. WhatIf should exit 0 on a supported host and valid checkout; CheckOnly should exit 1 when prerequisites are absent. Neither mode invokes Flutter or installs software.

## Clean Windows 11 x64 VM acceptance

Use a disposable Windows 11 x64 VM snapshot with a normal developer account, internet access, sufficient disk space for several gigabytes of tools/caches, and Microsoft App Installer providing WinGet. Keep credentials and personal data out of the VM. Use a Git checkout and an existing editor; editor setup is outside provisioning.

1. Record Windows build, PowerShell version, and existing Git/Visual Studio/Flutter installations. Include a checkout path containing spaces.
2. Run `setup-windows-dev.ps1 -WhatIf`. Confirm that no SDK directory, software installation, user PATH change, or generated file appears.
3. Run `setup-windows-dev.ps1 -CheckOnly`. On an unprovisioned snapshot it must report missing prerequisites and exit nonzero without changing the workstation.
4. Run provisioning from a non-elevated terminal. Approve UAC only for the Git/Microsoft compiler installers. If it returns `3010`, reboot the VM and rerun.
5. Confirm the SDK reports Flutter 3.44.4 stable and Dart 3.12.2. Confirm Windows/Visual Studio readiness, locked dependency restoration, Drift generation, Windows debug build, and `flutter test` success.
6. Select the printed SDK in the editor and run `flutter run -d windows`. Verify the application opens; change a visible Dart UI string locally, press `r`, and confirm hot reload. Revert that disposable edit and close the app with `q`.
7. Review generated changes. Commit/back up them before rerunning if necessary. Run setup a second time; verify no prerequisite reinstall, SDK download, or duplicate Flutter PATH entry.
8. Open a new terminal. Verify SDK selection, including the printed absolute launch command if another Flutter installation is earlier in machine PATH.
9. Repeat from a snapshot with compatible existing Visual Studio/Git, and another with an incomplete Build Tools installation. Confirm valid tools are reused and missing compiler components are added without removing IDE workloads.
10. Test a failed/cancelled installer, failed network access, SDK path conflicts, and uncommitted generated files. Each failure must stop before dependent work and must not print a success result. Do not create a release tag or run MSI packaging for these tests.

## Verification record

- 2026-10-11: **27/27 harness tests passed** in Windows PowerShell 5.1 and PowerShell 7.6.5. Native exit handling, actual junction rejection, real temporary ZIP extraction/publication/reuse, archive traversal rejection, and mocked provisioning paths were exercised. Installer, download, and persistent PATH boundaries remained simulated.
- All three PowerShell files parsed without errors in both versions.
- Actual entry-point checks ran in both versions, using the script's absolute path from outside the repository: WhatIf returned 0; CheckOnly returned 1 because Flutter is absent. User PATH and the SDK destination were unchanged.
- Independent code review approved the corrected implementation. Regression tests cover its findings: PowerShell 5.1 multi-instance/device JSON, WinGet reboot HRESULTs, Windows SDK registry views, and apostrophes in SDK launch paths.
- Fresh VM installation, Windows application compilation, application tests, and interactive hot reload have **not** been executed for this change. They require the acceptance procedure above; unit tests do not substitute for installer acceptance.
