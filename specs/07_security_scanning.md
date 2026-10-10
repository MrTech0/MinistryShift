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
  plugin Swift package, and any CocoaPods dependencies. Resolve Xcode's Swift
  package dependencies into the same derived-data directory before tracing.
- After initialization, build the Runner Xcode workspace for ARM64 without
  signing or compilation caches so CodeQL observes the Swift compilation. Use
  the generic macOS destination with `ARCHS=arm64` and `ONLY_ACTIVE_ARCH=NO`;
  an ARM64 device destination can disappear when CodeQL traces under Rosetta.
- Do not suppress build errors or remove a failing language from the matrix.
- Pin all workflow actions to verified full commit SHAs; use Dependabot for
  weekly updates. Disable checkout credential persistence and bound job times.
- Default tokens have `contents: read`; grant `security-events: write` only
  to analysis jobs and `contents: write` only to the release job.

## Action version compatibility

Use the latest stable releases verified on 2026-10-10, pinned to their
official tag commits in every workflow:

| Action | Release | Compatibility |
| --- | --- | --- |
| `actions/checkout` | [v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1) | Node 24; normal `pull_request`, `push`, scheduled, and manual events remain supported. Keep `persist-credentials: false`. The new restrictions for fork code in `pull_request_target` and `workflow_run` do not affect these workflows. |
| `actions/setup-java` | [v6.0.1](https://github.com/actions/setup-java/releases/tag/v6.0.1) | Node 24; `distribution: zulu` and `java-version: '17'` remain supported. No deprecated inputs or removed AdoptOpenJDK distributions are used. |
| `subosito/flutter-action` | [v2.23.0](https://github.com/subosito/flutter-action/releases/tag/v2.23.0) | Already current. Its composite setup supports Windows x64 and macOS ARM64 and the explicitly selected Flutter 3.44.4 stable SDK. |
| `softprops/action-gh-release` | [v3.0.3](https://github.com/softprops/action-gh-release/releases/tag/v3.0.3) | Node 24; Windows asset uploads and existing tag-only publication remain supported. Use the `token` input instead of the deprecated environment fallback, and fail if the MSI asset is missing. |

Node 24 actions require Actions Runner 2.327.1 or newer. The jobs use
GitHub-hosted runners; validate checkout on each selected operating system
and Java/Flutter setup through the Windows test job. The application SDKs
remain Java 17 and Flutter 3.44.4 because updating an action does not require
upgrading the SDK it installs.

Release publication requires `contents: write` and continues to run only for
`v*` tags. Pull-request validation must not publish a release. Check the
release action's documented inputs and runtime during the upgrade; the actual
MSI upload is exercised by the next authorized version-tag release.

## Validation and migration

The failing setup job is
https://github.com/MrTech0/MinistryShift/actions/runs/37985701961/job/114007041032.
Validate the proposal with actionlint, the three real CodeQL jobs, and the
existing Windows Flutter test job on a pull request.

Default and advanced CodeQL uploads cannot coexist. During pre-merge
validation, keep default setup active and set repository variable
`CODEQL_UPLOAD_MODE` to `never`. The custom jobs still build their databases
and run queries; they do not replace the existing production analysis.
Each job displays a notice and summary identifying this validation-only mode.

After the pull request has been reviewed and approved:

1. Merge the workflow changes into `main`.
2. Switch CodeQL from default to advanced setup (set default setup state to
   `not-configured`).
3. Delete `CODEQL_UPLOAD_MODE` so uploads default to `always`.
4. Dispatch the CodeQL workflow on `main`; confirm successful uploaded
   analyses with nonzero rules for Actions, C/C++, and Swift.

The migration remains pending until the main-branch uploads are verified.

## Activation record

Advanced setup was activated on 2026-10-11 after
[PR #1](https://github.com/MrTech0/MinistryShift/pull/1) was merged. Default
setup reports `state: not-configured`, and `CODEQL_UPLOAD_MODE` has been deleted.

[Workflow run 38093369123](https://github.com/MrTech0/MinistryShift/actions/runs/38093369123)
completed successfully for Actions, C/C++, and Swift. GitHub received all
three analyses from `.github/workflows/codeql.yml:analyze` on
`refs/heads/main` at commit `710bae106da28b48fa57842eeb4081cc5d887531`, with
17, 58, and 27 rules respectively and no analysis errors or warnings.
