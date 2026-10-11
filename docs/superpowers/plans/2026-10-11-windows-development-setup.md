# Windows Development Setup Implementation Plan

This is the initial delivery record, completed in `db11e99`. The user's subsequent single-script/project-derived-version amendment supersedes its original embedded toolchain choices; current requirements are in SPEC-08 and the amendment record below.

> Implement inline using the executing-plans and test-driven-development skills; request one independent review at the end.

**Goal:** Provision an existing MinistryShift checkout for Windows desktop development and hot reload.

**Architecture:** A thin PowerShell entry point delegates detection, planning, installation, and project preparation to testable functions. Native process execution, downloads, and environment persistence are explicit boundaries. Read-only modes stop before those boundaries.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7, WinGet, Visual Studio Build Tools, Flutter.

**Spec:** `specs/08_windows_development_setup.md`, approved 2026-10-11.

## Global Constraints
- Windows 11 x64, 64-bit PowerShell; Flutter 3.44.4 stable / Dart 3.12.2.
- Reviewed Build Tools installer 18.10.2; reuse compatible stable existing installations.
- Existing checkout and editor; no MSI tools, Android SDK, Java, or database server installation.
- SHA-256 verified SDK, no execution-policy changes, no elevated Flutter, no overwrite of another SDK.
- English code/help/documentation. Do not install prerequisites on the current workstation while testing.

## Review Focus
- Older PowerShell argument passing, spaces in the checkout, and reliable native exit-code propagation.
- Existing compiler installation with missing components or a pending reboot.
- An occupied SDK destination or junction must not be overwritten or recursively removed.
- Read-only modes must not initialize Flutter caches or alter PATH.
- A conflicting SDK earlier in the machine PATH must not cause project commands to use another version.

## Task 1: Detection and planning
**Files:** `scripts/windows-dev-tools.ps1`, `scripts/tests/windows-dev-tools.tests.ps1`.
**Interfaces:** `Get-DevelopmentState(ProjectDirectory, FlutterDirectory)`, `Get-ProvisioningPlan(State)`, `Invoke-CheckedCommand(FilePath, Arguments, Capture)`.
- [x] Write and run failing tests for unsupported hosts, toolchain/version drift, SDK conflicts, PATH preservation, installer reboot codes, native failures, and no-side-effect inspection.
- [x] Implement detection and planning. Inspection checks the pinned official Git revision without running Flutter; provisioning also verifies the runtime versions.
- [x] Run the harness in both PowerShell versions; require zero failures.

## Task 2: Provisioning and validation
**Files:** `scripts/setup-windows-dev.ps1`, `scripts/windows-dev-tools.ps1`, harness.
**Interfaces:** `Invoke-WindowsDevelopmentSetup(ProjectDirectory, FlutterDirectory, CheckOnly, SkipValidation)` with ShouldProcess / WhatIf; consumes Task 1 state and command helpers.
- [x] Add failing tests for SDK hash mismatch, occupied/reparse-point targets, idempotent prerequisites, argument arrays, failed project preparation, generated-file protection, and both read-only modes.
- [x] Implement trusted installers, bounded downloads, staged SDK publication, PATH update, Flutter preparation, Windows device validation, debug compilation, and tests.
- [x] Run the complete harness in both PowerShell versions. Run the real entry point in CheckOnly and WhatIf modes; require no host changes.

## Task 3: Documentation and review
**Files:** `README.md`, `docs/windows-development-validation.md`, approved specification, this plan.
- [x] Document invocation, installer agreement acceptance/UAC, hot reload, check-only limits, PATH conflicts, and clean Windows 11 VM acceptance.
- [x] Parse scripts under PowerShell 5.1 and 7, run the harness, and check the staged diff before committing.
- [x] Obtain independent review and address actionable findings. Record installation/build acceptance limitations accurately.
- [x] Include the reviewed local changes in the delivery commit on `codex/windows-development-setup`, with the script and commands documented in README.

## Execution Record
- Baseline: `710bae1`; primary checkout clean except the specification prepared for this task. Flutter is unavailable locally, so application tests cannot be run without installing the toolchain.
- Ruling: execute on a dedicated local branch in the existing checkout. All current edits belong to this task; another checkout and an additional approval round would not improve isolation from user changes.
- Ruling: inline implementation follows the user's approval to implement and test. No second approval of implementation mechanics is required.
- Ruling: use a dependency-free PowerShell harness so developers can verify this provisioning script without first provisioning a test framework.
- Implementation: entry point, testable provisioning helpers, README, and clean-machine acceptance procedure completed.
- Tests: 27/27 passed in Windows PowerShell 5.1 and PowerShell 7.6.5. All three PowerShell files parsed without errors in both versions.
- Read-only entry point: invoked by absolute path from outside the repository in both versions. WhatIf returned 0; CheckOnly returned 1 for the absent Flutter SDK. User PATH and SDK destination remained unchanged.
- Review: one independent reviewer approved after fixes for PowerShell 5.1 JSON arrays, WinGet reboot HRESULTs, Windows SDK registration in both registry views, and apostrophe escaping in the printed launch command. Regression tests reproduced each problem before its correction.
- Git: the staged diff passed `git diff --cached --check`; all seven changed files belong to this task.
- Acceptance limitation: no actual prerequisite installation, full SDK download, application build/tests, or interactive hot reload was run. These are documented VM acceptance checks, not claims supported by the mocked harness.
- Delivery: preserve the dedicated local branch; publishing or merging is outside this approved implementation task.

## User-requested amendment: single script and project-derived versions
- Authorization: the user explicitly requested one provisioning script and automatic discovery of the project's current versions. Implement this bounded correction within the already approved Windows desktop scope; no additional design approval is needed.
- Implementation: `setup-windows-dev.ps1` now contains the entry point and all functions. The helper was removed. The renamed `scripts/tests/setup-windows-dev.tests.ps1` harness loads functions without provisioning and is not a runtime dependency.
- Version discovery: read consistent literal Flutter version/channel inputs from project workflows and the Dart constraint from pubspec. Select the exact official Windows x64 release from Flutter's HTTPS manifest, including SHA-256/revision/bundled Dart. Build Tools installation uses WinGet's current stable package rather than an embedded version. Preserve existing tools and rely on locked restoration/debug compilation for compatibility validation.
- Test evidence: initial new behavior produced eight failing tests against the old implementation. Additional CRLF and review regressions also failed before correction. The final harness passed 42/42 in Windows PowerShell 5.1 and PowerShell 7.6.5.
- Read-only evidence: both PowerShell parsers and real WhatIf/CheckOnly checks passed from outside the repository, preserving user PATH and the SDK destination. Real official manifest lookups in both PowerShell versions resolved the project's current selection without installing/downloading the SDK.
- Review/delivery: one independent reviewer approved this amendment after the parser regressions were addressed. The staged diff passed whitespace/error checks. Preserve the reviewed changes in a local commit on the existing task branch.
- Acceptance limit: clean-machine provisioning, installers/UAC, actual application build/tests, and hot reload remain unperformed. The documented VM procedure includes a project-version upgrade and old-SDK preservation check.

## User-requested amendment: explicit extraction directory
- Remove both the default SDK destination and automatic selection from PATH. When FlutterDirectory is omitted, ask for the exact SDK directory before provisioning; empty input cancels. Explicit parameters remain available for unattended execution and read-only modes.
- Test evidence: three new cases failed against the previous behavior. After the correction, 46/46 tests passed in Windows PowerShell 5.1 and PowerShell 7.6.5, including an actual noninteractive entry-point check. The existing installation safeguards still apply to the chosen path.
- Read-only evidence: real entry-point checks in both versions from outside the repository used the exact explicitly supplied temporary path. WhatIf returned 0; CheckOnly returned 1 for the absent SDK; noninteractive execution without a path returned 1 with parameter instructions. No SDK directory was created and user PATH was preserved.
- Review/delivery: independent review approved the directory-selection amendment without outstanding findings. Preserve the tested changes in a local commit on the existing task branch; full clean-machine provisioning acceptance remains pending.
