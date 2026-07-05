# SPEC-02: Version Control, Packaging, and CI/CD Pipeline

## Metadata
- **Status**: Draft
- **Author**: Spec Author (The Architect)
- **Created Date**: 2026-06-30
- **Last Updated**: 2026-06-30

---

## 1. Objectives & Scope

### 1.1 Summary
This specification outlines the version control practices and the Automated Continuous Integration & Continuous Delivery (CI/CD) pipeline for MinistryShift. It defines the packaging configuration for compiling the application into a Windows `.msi` (or `.msix` installer) and the GitHub Actions automation to build and publish releases.

### 1.2 Out of Scope
- Multi-platform packaging other than Windows x86_64 initially (macOS ARM64 target will be detailed in a future revision).
- Signing installers with paid commercial certificates (we will use self-signed certificates or unsigned packages for distribution).

---

## 2. Functional Requirements

### 2.1 Developer & Release Use Cases
- **Release Automation**: As a developer, when I push a git tag (e.g. `v1.0.0`), I want GitHub Actions to compile the release binary, package it as a Windows installer, and upload it to a new GitHub Release draft/publish.
- **Installer Execution**: As a user, I want to download a `.msi` or `.msix` file, run it on my Windows machine, and have the application install with desktop/start menu shortcuts.

### 2.2 Functional Specifications
- **CI/CD Triggers**: 
  - On every pull request to `main`: compile the Flutter app, run unit and integration tests (`flutter test`).
  - On pushing a tag matching `v*`: run tests, build the release, generate the installer, and publish it to GitHub Releases.
- **Packaging Mechanism**:
  - We will use the `msix` package in Dart (`dev_dependencies`). It compiles the app and generates a Windows installer package directly.
  - Configurations for packaging (identity name, publisher, display name, icons, and file associations) must be embedded in `pubspec.yaml`.

---

## 3. Configuration & Scripts

### 3.1 Pubspec Configuration for MSIX Installer
We add the configuration block to `pubspec.yaml` under `msix_config`:

```yaml
msix_config:
  display_name: MinistryShift
  publisher_display_name: MinistryShift Authors
  identity_name: com.ministryshift.app
  publisher: "CN=MinistryShift, O=MinistryShift, C=ES"
  logo_path: windows/runner/resources/app_icon.ico
  capabilities: "internetClient"
  install_on_launch: true
```

### 3.2 GitHub Actions CI/CD Workflow (`.github/workflows/release.yml`)
The workflow utilizes a Windows runner (`windows-latest`) which comes preloaded with Visual Studio, MSBuild, and the Windows SDK required for packaging.

```yaml
name: Build and Release Windows MSIX

on:
  push:
    tags:
      - 'v*'
  pull_request:
    branches:
      - main

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.4'
          channel: 'stable'
      - name: Install dependencies
        run: flutter pub get
      - name: Run tests
        run: flutter test

  release:
    needs: test
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Java & Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.4'
      - name: Install dependencies
        run: flutter pub get
      - name: Generate Code
        run: flutter pub run build_runner build --delete-conflicting-outputs
      - name: Build Windows Executable
        run: flutter build windows --release
      - name: Package MSIX
        run: flutter pub run msix:create
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            build/windows/x64/runner/Release/ministry_shift.msix
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## 4. Test / Harness Plan

### 4.1 Verification of CI Pipeline
* Verify the pipeline runs and successfully compiles code by pushing a test branch.
* Check that tests execute successfully in the GitHub VM.

---

## 5. Security & System Constraints
- **Unsigned Packages**: Since we use a self-signed identity certificate (`msix` handles certificate creation internally if none is provided), Windows SmartScreen might show a warning on first install. The spec details that users must click "Run anyway" until we integrate a trusted certificate.
- **Isolate Tokens**: Ensure `GITHUB_TOKEN` is scoped only with `contents: write` permissions.
