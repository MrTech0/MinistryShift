# SPEC-07: CodeQL scanning for Flutter desktop

## Scope

Repair the failed Swift analysis introduced by CodeQL default setup. The
automatic Xcode build cannot find Flutter's generated plugin Swift package.
Keep Actions and C/C++ analysis and restore Swift coverage; Dart is not a
CodeQL-supported language and remains covered by the existing Flutter tests.

## Requirements

- Use advanced CodeQL setup on pushes to `main`, pull requests, manual runs,
  and a weekly schedule.
- Scan Actions on Ubuntu, Windows C/C++ with `build-mode: none`, and Swift on
  macOS ARM64 with `build-mode: manual`.
- Match the existing Flutter SDK version, 3.44.4. Resolve locked dependencies,
  generate Dart code, and run `flutter build macos --debug --config-only`
  before initializing CodeQL. This prepares Flutter's ephemeral configuration,
  plugin Swift package, and any CocoaPods dependencies.
- After initialization, build the Runner Xcode workspace for ARM64 without
  signing or compilation caches so CodeQL observes the Swift compilation.
- Do not suppress build errors or remove a failing language from the matrix.
- Pin all workflow actions to verified full commit SHAs; use Dependabot for
  weekly updates. Disable checkout credential persistence and bound job times.
- Default tokens have `contents: read`; grant `security-events: write` only
  to analysis jobs and `contents: write` only to the release job.

## Validation and migration

The failing setup job is
https://github.com/MrTech0/MinistryShift/actions/runs/37985701961/job/114007041032.
Validate the proposal with actionlint, the three real CodeQL jobs, and the
existing Windows Flutter test job on a pull request.

Default and advanced CodeQL uploads cannot coexist. During pre-merge
validation, keep default setup active and set repository variable
`CODEQL_UPLOAD_MODE` to `never`. The custom jobs still build their databases
and run queries; they do not replace the existing production analysis.

After the pull request has been reviewed and approved:

1. Merge the workflow changes into `main`.
2. Switch CodeQL from default to advanced setup (set default setup state to
   `unconfigured`).
3. Delete `CODEQL_UPLOAD_MODE` so uploads default to `always`.
4. Dispatch the CodeQL workflow on `main`; confirm successful uploaded
   analyses with nonzero rules for Actions, C/C++, and Swift.

The migration remains pending until the main-branch uploads are verified.
