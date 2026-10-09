# CodeQL Flutter Swift repair implementation plan

**Goal:** Restore Swift security analysis without losing Actions or C/C++ coverage.

**Spec:** `specs/07_security_scanning.md`.

**Approach:** Prepare Flutter's generated macOS dependencies, then capture a
manual ARM64 Xcode build in a dedicated CodeQL workflow. Validate the proposed
workflow while the existing default setup remains active. Activate uploaded
advanced analysis only after review and merge.

## Task: Repair and validate security workflows

- [x] Identify the failing job and verify the generated Swift package is missing.
- [x] Verify Flutter's config-only preparation and supported CodeQL build modes.
- [x] Add `.github/workflows/codeql.yml` with all three languages and manual Swift build.
- [x] Restrict release workflow permissions and pin action commits.
- [x] Add `.github/dependabot.yml` to maintain action pins.
- [ ] Run actionlint and whitespace validation.
- [ ] Open a draft pull request and run CodeQL with uploads temporarily disabled.
- [ ] Confirm actual Swift extraction, the other two scans, and Flutter tests pass.
- [ ] Obtain independent review and fix blocking findings.
- [ ] Present the validated pull request for review and migration approval.

## Verification

Use actionlint 1.7.12 for workflow validation and `git diff --check` for
whitespace. Real GitHub Actions runs must confirm that the missing Swift
package is generated, Xcode compiles successfully, and all three CodeQL
databases run their query suites. The existing Windows job must run the
complete Flutter test suite; release packaging is skipped on pull requests.

## Migration constraint

Keep production default setup active during proposal validation. The only
temporary repository change is `CODEQL_UPLOAD_MODE=never`; remove it when
switching to advanced setup after the pull request is approved.
