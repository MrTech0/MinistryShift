# Windows Development Setup Validation

## Automated checks

Run `scripts/tests/setup-windows-dev.tests.ps1` using Windows PowerShell 5.1 and PowerShell 7. This is a development test harness, not a provisioning dependency. It loads the self-contained setup script without executing its entry point. No Pester or downloaded framework is needed. Tests use temporary fixtures and simulate installers, downloads, and persistent PATH changes.

Inspect the real entry point with `-WhatIf` and `-CheckOnly`. WhatIf should exit 0 on a supported host and valid checkout; CheckOnly should exit 1 when prerequisites are absent. Neither mode invokes Flutter or installs software.

## Clean Windows 11 x64 VM acceptance

Use a disposable Windows 11 x64 VM snapshot with a normal developer account, internet access, sufficient disk space for several gigabytes of tools/caches, and Microsoft App Installer providing WinGet. Keep credentials and personal data out of the VM. Use a Git checkout and an existing editor; editor setup is outside provisioning.

1. Record Windows build, PowerShell version, and existing Git/Visual Studio/Flutter installations. Include a checkout path containing spaces.
2. Run `setup-windows-dev.ps1 -WhatIf`. Confirm that no SDK directory, software installation, user PATH change, or generated file appears.
3. Run `setup-windows-dev.ps1 -CheckOnly`. On an unprovisioned snapshot it must report missing prerequisites and exit nonzero without changing the workstation.
4. Run provisioning from a non-elevated terminal. Approve UAC only for the Git/Microsoft compiler installers. If it returns `3010`, reboot the VM and rerun.
5. Confirm Flutter version/channel match the project workflow declarations and bundled Dart matches the official release manifest. Confirm Windows/Visual Studio readiness, locked dependency restoration, Drift generation, Windows debug build, and `flutter test` success.
6. Select the printed SDK in the editor and run `flutter run -d windows`. Verify the application opens; change a visible Dart UI string locally, press `r`, and confirm hot reload. Revert that disposable edit and close the app with `q`.
7. Review generated changes. Commit/back up them before rerunning if necessary. Run setup a second time; verify no prerequisite reinstall, SDK download, or duplicate Flutter PATH entry.
8. Open a new terminal. Verify SDK selection, including the printed absolute launch command if another Flutter installation is earlier in machine PATH.
9. Repeat from a snapshot with compatible existing Visual Studio/Git, and another with an incomplete Build Tools installation. Confirm valid tools are reused and missing compiler components are added without removing IDE workloads.
10. Test a failed/cancelled installer, failed network access, SDK path conflicts, and uncommitted generated files. Each failure must stop before dependent work and must not print a success result. Do not create a release tag or run MSI packaging for these tests.
11. Update the project Flutter declarations consistently to another compatible official release and update project SDK/package constraints as needed. Rerun the unchanged provisioning script; verify it selects the new release/default SDK directory and preserves the previous SDK. Conflicting declarations must fail before downloading or installing.

## Verification record

- Initial delivery, 2026-10-11: **27/27 harness tests passed** in Windows PowerShell 5.1 and PowerShell 7.6.5. Native exit handling, actual junction rejection, real temporary ZIP extraction/publication/reuse, archive traversal rejection, and mocked provisioning paths were exercised. Installer, download, and persistent PATH boundaries remained simulated.
- Single-script amendment, 2026-10-11: **42/42 harness tests passed** in both versions. Added project version upgrades without script edits, consistent/conflicting workflow inputs, CRLF, offline metadata/revision checks, manifest version/channel/architecture/integrity selection, unsupported YAML rejection, and a copied standalone script invoked with WhatIf. The helper script was removed; the separate test harness is not required to provision a checkout.
- The setup script and its test harness parsed without errors in both versions. Dot-sourcing the setup file performed no provisioning.
- Actual entry-point checks ran in both versions, using the script's absolute path from outside the repository: WhatIf returned 0; CheckOnly returned 1 because Flutter is absent. User PATH and the SDK destination were unchanged.
- Actual read-only HTTPS manifest lookups in both versions resolved the current project declaration to Flutter 3.44.4 stable, bundled Dart 3.12.2, and its published archive/SHA-256/revision. The SDK archive was not downloaded.
- Independent code review approved the corrected implementation. Regression tests cover its findings: PowerShell 5.1 multi-instance/device JSON, WinGet reboot HRESULTs, Windows SDK registry views, and apostrophes in SDK launch paths.
- A second independent review approved the single-script amendment after regression fixes for conditional/inline/folded action declarations, unsupported input keys, version-file inputs, and case-sensitive release selection. No code findings remain open; full provisioning acceptance remains pending.
- Fresh VM installation, Windows application compilation, application tests, and interactive hot reload have **not** been executed for this change. They require the acceptance procedure above; unit tests do not substitute for installer acceptance.
