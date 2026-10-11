#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$toolsPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-windows-dev.ps1'
$tests = [ordered]@{}
function Assert-Equal($Actual, $Expected) {
    if ($Actual -cne $Expected) { throw "Expected [$Expected], got [$Actual]." }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    try { & $Action } catch {
        if ($_.Exception -is [Management.Automation.CommandNotFoundException]) { throw }
        if ($_.Exception.Message -notmatch $Pattern) { throw "Unexpected error: $($_.Exception.Message)" }
        return
    }
    throw 'Expected the operation to fail.'
}
$tests['SDK path rejects filesystem roots and whitespace'] = {
    Assert-Throws { Assert-SdkDestination 'C:\' } 'root'
    Assert-Throws { Assert-SdkDestination 'C:\dev tools\flutter' } 'whitespace'
    Assert-Throws { Assert-SdkDestination '.\flutter' } 'absolute'
}
$tests['PATH addition preserves existing entries and avoids equivalent duplicates'] = {
    Assert-Equal (Add-PathEntry 'C:\Windows;C:\Tools' 'C:\Flutter\bin') 'C:\Windows;C:\Tools;C:\Flutter\bin'
    Assert-Equal (Add-PathEntry 'C:\Windows;C:\Flutter\bin\' 'c:\flutter\bin') 'C:\Windows;C:\Flutter\bin\'
    Assert-Equal (Add-PathEntry '' 'C:\Flutter\bin') 'C:\Flutter\bin'
}
$tests['Native command failure is not reported as success'] = {
    Assert-Throws { Invoke-CheckedCommand $env:ComSpec @('/d', '/c', 'exit', '7') } 'exit code 7'
    $null = Invoke-CheckedCommand $env:ComSpec @('/d', '/c', 'exit', '0')
}
$tests['Compiler reboot outcome stops dependent operations'] = {
    Assert-Throws { Assert-InstallerExitCode 3010 } 'reboot'
    Assert-Throws { Assert-InstallerExitCode 1602 } '1602'
    Assert-InstallerExitCode 0
}
$tests['WinGet reboot HRESULTs propagate as reboot-required outcomes'] = {
    foreach ($code in @(-1978334967, -1978334966, -1978334965)) {
        Assert-Throws { Assert-InstallerExitCode $code } 'reboot'
    }
}
$tests['Unsupported Windows and ARM hosts fail before provisioning'] = {
    Assert-Throws { Assert-DevelopmentHost ([pscustomobject]@{Build=19045;Architecture='AMD64';Is64BitProcess=$true;IsWindows11=$false}) } 'Windows 11'
    Assert-Throws { Assert-DevelopmentHost ([pscustomobject]@{Build=22000;Architecture='ARM64';Is64BitProcess=$true;IsWindows11=$true}) } 'x64'
    Assert-Throws { Assert-DevelopmentHost ([pscustomobject]@{Build=22000;Architecture='AMD64';Is64BitProcess=$false;IsWindows11=$true}) } '64-bit PowerShell'
}

$fixtureRoot = Join-Path $env:TEMP ('ministryshift-setup-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
function New-TestSettings {
    return @{
        FlutterVersion='3.44.4';FlutterChannel='stable';DartConstraint='^3.12.2';DartVersion='3.12.2'
        FlutterRevision='ad70ec4617166f1c38e5d2bfd388af71fda14f06'
        FlutterSha256='8f2d6224fc6872d2f7f180de86cde989fcea3776efe0edf48a9aac2cd9be2b1b'
        FlutterUrl='https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.4-stable.zip'
    }
}
function New-TestSdk([string]$Name, [string]$Revision = 'ad70ec4617166f1c38e5d2bfd388af71fda14f06', [string]$Version = '3.44.4') {
    $path = Join-Path $fixtureRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $path 'bin'), (Join-Path $path '.git') -Force | Out-Null
    Set-Content (Join-Path $path 'bin/flutter.bat') '@echo off'
    Set-Content (Join-Path $path 'bin/dart.bat') '@echo off'
    Set-Content (Join-Path $path '.git/HEAD') $Revision
    New-Item -ItemType Directory (Join-Path $path 'bin/cache') | Out-Null
    @{frameworkVersion=$Version;channel='stable';frameworkRevision=$Revision;dartSdkVersion='3.12.2'} | ConvertTo-Json | Set-Content (Join-Path $path 'bin/cache/flutter.version.json')
    return $path
}
function New-TestState {
    return [pscustomobject]@{
        ProjectDirectory = $fixtureRoot
        Git = 'C:\tools\git.exe'; Winget = 'C:\tools\winget.exe'
        Sdk = [pscustomobject]@{Ready=$true; Directory='C:\tools\flutter'}
        Compiler = [pscustomobject]@{Ready=$true; Directory='C:\tools\compiler'; RepairDirectory=$null; RebootRequired=$false}
    }
}
function New-TestProject([string]$Name, [string]$Version = '4.2.0', [string]$DartConstraint = '^4.1.0') {
    $project = Join-Path $fixtureRoot $Name
    foreach ($directory in @('windows', 'assets/fonts', '.github/workflows', 'scripts')) { New-Item -ItemType Directory (Join-Path $project $directory) -Force | Out-Null }
    foreach ($file in @('pubspec.lock','windows/CMakeLists.txt','assets/fonts/Arial-Regular.ttf','assets/fonts/Arial-Bold.ttf')) { Set-Content (Join-Path $project $file) 'fixture' }
    Set-Content (Join-Path $project 'pubspec.yaml') "environment:`n  sdk: '$DartConstraint'"
    foreach ($workflow in @('release.yml','codeql.yml')) {
        Set-Content (Join-Path $project ".github/workflows/$workflow") "jobs:`n  test:`n    steps:`n      - name: Flutter`n        uses: subosito/flutter-action@v2`n        with:`n          flutter-version: '$Version' # project version`n          channel: stable"
    }
    return $project
}
function New-TestManifest {
    return [pscustomobject]@{
        base_url='https://storage.googleapis.com/flutter_infra_release/releases'
        releases=@(
            [pscustomobject]@{version='4.2.0';channel='stable';dart_sdk_version='4.1.0';dart_sdk_arch='x64';hash=('b' * 40);sha256=('c' * 64);archive='stable/windows/flutter_windows_4.2.0-stable.zip'},
            [pscustomobject]@{version='4.2.0';channel='stable';dart_sdk_version='4.1.0';dart_sdk_arch='arm64';hash=('d' * 40);sha256=('e' * 64);archive='stable/windows/flutter_windows_4.2.0-arm64-stable.zip'},
            [pscustomobject]@{version='4.2.0';channel='beta';dart_sdk_version='4.1.0';dart_sdk_arch='x64';hash=('f' * 40);sha256=('a' * 64);archive='beta/windows/flutter_windows_4.2.0-beta.zip'}
        )
    }
}
$tests['SDK reuse verifies revision without executing Flutter'] = {
    $sdk = New-TestSdk 'valid-sdk'
    Assert-Equal (Get-FlutterSdkState $sdk).Ready $true
    $otherSdk = New-TestSdk 'other-sdk' ('a' * 40)
    Assert-Throws { Get-FlutterSdkState $otherSdk } 'never overwritten'
    $occupied = Join-Path $fixtureRoot 'occupied'
    New-Item -ItemType Directory $occupied | Out-Null
    Set-Content (Join-Path $occupied 'user-file.txt') 'keep'
    Assert-Throws { Get-FlutterSdkState $occupied } 'occupied'
    Assert-Equal (Get-Content (Join-Path $occupied 'user-file.txt')) 'keep'
}
$tests['SDK directories cannot traverse junctions'] = {
    $target = Join-Path $fixtureRoot 'junction-target'
    $link = Join-Path $fixtureRoot 'junction-link'
    New-Item -ItemType Directory $target | Out-Null
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Assert-Throws { Assert-SdkDestination (Join-Path $link 'flutter') } 'reparse point'
    # Delete the junction itself; never recursively traverse it.
    [IO.Directory]::Delete($link)
}
$tests['Project upgrades determine Flutter and Dart without editing provisioning'] = {
    $project = New-TestProject 'project with spaces'
    $settings = Get-ProjectToolchain $project
    Assert-Equal $settings.FlutterVersion '4.2.0'
    Assert-Equal $settings.FlutterChannel 'stable'
    Assert-Equal $settings.DartConstraint '^4.1.0'
}
$tests['Conflicting workflow versions stop before choosing an SDK'] = {
    $project = New-TestProject 'conflicting-workflows'
    $workflow = Join-Path $project '.github/workflows/codeql.yml'
    (Get-Content $workflow -Raw).Replace('4.2.0','4.3.0') | Set-Content $workflow
    Assert-Throws { Get-ProjectToolchain $project } 'conflicting'
}
$tests['Project declarations support Windows CRLF and ignore unrelated step inputs'] = {
    $project = New-TestProject 'crlf-workflows'
    foreach ($workflow in Get-ChildItem (Join-Path $project '.github/workflows') -File) {
        $yaml = Get-Content $workflow.FullName -Raw
        $yaml += "`n      - run: echo other`n        with:`n          flutter-version: 9.9.9`n"
        [IO.File]::WriteAllText($workflow.FullName, ($yaml -replace '\r?\n', "`r`n"))
    }
    Assert-Equal (Get-ProjectToolchain $project).FlutterVersion '4.2.0'
}
$tests['Offline SDK inspection follows project updates and rejects stale metadata'] = {
    $script:DevelopmentSettings = @{FlutterVersion='4.2.0';FlutterChannel='stable'}
    $sdk = New-TestSdk 'future-sdk' ('b' * 40) '4.2.0'
    Assert-Equal (Get-FlutterSdkState $sdk).Ready $true
    Set-Content (Join-Path $sdk '.git/HEAD') ('d' * 40)
    Assert-Throws { Get-FlutterSdkState $sdk } 'never overwritten'
}
$tests['Unresolved workflow expressions cannot be silently used as versions'] = {
    $project = New-TestProject 'expression-workflows' '${{ env.FLUTTER_VERSION }}'
    Assert-Throws { Get-ProjectToolchain $project } 'literal|expression'
}
$tests['Flutter steps beginning with if still participate in conflict detection'] = {
    $project = New-TestProject 'conditional-step-workflows'
    Add-Content (Join-Path $project '.github/workflows/codeql.yml') "      - if: runner.os == 'Windows'`n        uses: subosito/flutter-action@v2`n        with:`n          flutter-version: '4.3.0'`n          channel: stable"
    Assert-Throws { Get-ProjectToolchain $project } 'conflicting'
}
$tests['Unsupported inline Flutter steps are rejected instead of ignored'] = {
    $project = New-TestProject 'inline-workflows'
    Add-Content (Join-Path $project '.github/workflows/release.yml') "      - { uses: subosito/flutter-action@v2, with: {flutter-version: '4.3.0', channel: stable} }"
    Assert-Throws { Get-ProjectToolchain $project } 'unsupported|literal'
}
$tests['Unsupported folded and spaced action declarations cannot be skipped'] = {
    $inputs = @{
        folded="        uses: >-`n          subosito/flutter-action@v2"
        spaced='        uses : subosito/flutter-action@v2'
    }
    foreach ($name in $inputs.Keys) {
        $project = New-TestProject ($name + '-action-workflows')
        Add-Content (Join-Path $project '.github/workflows/codeql.yml') ("      - name: Flutter B`n" + $inputs[$name] + "`n        with:`n          flutter-version: '4.3.0'`n          channel: stable")
        Assert-Throws { Get-ProjectToolchain $project } 'unsupported|literal'
    }
}
$tests['Version-file inputs are explicitly rejected even beside a literal version'] = {
    $project = New-TestProject 'version-file-workflows'
    Add-Content (Join-Path $project '.github/workflows/release.yml') '          flutter-version-file: pubspec.yaml'
    Assert-Throws { Get-ProjectToolchain $project } 'flutter-version-file|unsupported'
}
$tests['Unsupported quoted or merged action input keys cannot default silently'] = {
    $inputs = @{
        quotedChannel="          'channel': beta"
        quotedFile="          'flutter-version-file': pubspec.yaml"
        merged='          <<: *defaults'
    }
    foreach ($name in $inputs.Keys) {
        $project = New-TestProject ($name + '-input-workflows')
        foreach ($workflow in Get-ChildItem (Join-Path $project '.github/workflows') -File) {
            $yaml = Get-Content $workflow.FullName -Raw
            if ($name -eq 'quotedChannel') { $yaml = $yaml.Replace('          channel: stable', $inputs[$name]) }
            else { $yaml += "`n" + $inputs[$name] + "`n" }
            Set-Content $workflow.FullName $yaml
        }
        Assert-Throws { Get-ProjectToolchain $project } 'unsupported'
    }
}
$tests['Channel spelling must match the case-sensitive CI declaration'] = {
    $project = New-TestProject 'channel-case-workflows'
    foreach ($workflow in Get-ChildItem (Join-Path $project '.github/workflows') -File) {
        (Get-Content $workflow.FullName -Raw).Replace('channel: stable','channel: STABLE') | Set-Content $workflow.FullName
    }
    Assert-Throws { Get-ProjectToolchain $project } 'channel'
}
$tests['Prerelease names must match the official manifest exactly'] = {
    function script:Get-FlutterReleaseManifest { $manifest=New-TestManifest; $manifest.releases[0].version='4.2.0-0.1.pre'; return $manifest }
    Assert-Throws { Resolve-FlutterRelease @{FlutterVersion='4.2.0-0.1.PRE';FlutterChannel='stable'} } 'not found'
}
$tests['Manifest resolves the project release and architecture with its published hash'] = {
    function script:Get-FlutterReleaseManifest { New-TestManifest }
    $release = Resolve-FlutterRelease @{FlutterVersion='4.2.0';FlutterChannel='stable';DartConstraint='^4.1.0'}
    Assert-Equal $release.FlutterVersion '4.2.0'
    Assert-Equal $release.DartVersion '4.1.0'
    Assert-Equal $release.FlutterRevision ('b' * 40)
    Assert-Equal $release.FlutterSha256 ('c' * 64)
    Assert-Equal $release.FlutterUrl 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_4.2.0-stable.zip'
}
$tests['Missing or malformed releases never fall back to another Flutter version'] = {
    function script:Get-FlutterReleaseManifest { New-TestManifest }
    Assert-Throws { Resolve-FlutterRelease @{FlutterVersion='4.9.0';FlutterChannel='stable'} } 'not found'
    function script:Get-FlutterReleaseManifest { $manifest=New-TestManifest; $manifest.releases[0].sha256='invalid'; return $manifest }
    Assert-Throws { Resolve-FlutterRelease @{FlutterVersion='4.2.0';FlutterChannel='stable'} } 'invalid|malformed'
}
$tests['Release archive URL stays within the official Flutter download location'] = {
    function script:Get-FlutterReleaseManifest { $manifest=New-TestManifest; $manifest.releases[0].archive='../elsewhere.zip'; return $manifest }
    Assert-Throws { Resolve-FlutterRelease @{FlutterVersion='4.2.0';FlutterChannel='stable'} } 'unsafe|invalid'
}
$tests['One copied provisioning script can preview another project version'] = {
    $project = New-TestProject 'standalone-project'
    $entry = Join-Path $project 'scripts/setup-windows-dev.ps1'
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-windows-dev.ps1') -Destination $entry
    $shell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $result = Invoke-NativeProcess $shell @('-NoProfile','-ExecutionPolicy','Bypass','-File',$entry,'-WhatIf','-FlutterDirectory',(Join-Path $project 'sdk')) -Capture
    Assert-Equal $result.ExitCode 0
    if ($result.Output -notmatch '4\.2\.0') { throw 'Preview did not select the new project version.' }
}
$tests['Hash mismatch rejects the archive before extraction'] = {
    $archive = Join-Path $fixtureRoot 'bad.zip'
    Set-Content $archive 'invalid archive'
    Assert-Throws { Assert-FlutterArchive $archive (Join-Path $fixtureRoot 'extract') } 'SHA-256'
    Assert-Equal (Test-Path (Join-Path $fixtureRoot 'extract')) $false
}
$tests['CheckOnly succeeds with installed tools without side effects'] = {
    function script:Get-ProjectToolchain { New-TestSettings }
    function script:Get-FlutterReleaseManifest { throw 'Unexpected network request.' }
    function script:Get-DevelopmentState { New-TestState }
    function script:Invoke-NativeProcess { throw 'Unexpected native process.' }
    function script:Set-FlutterPath { throw 'Unexpected PATH persistence.' }
    function script:Install-FlutterSdk { throw 'Unexpected SDK install.' }
    function script:Install-DevelopmentPrerequisites { throw 'Unexpected installer.' }
    Assert-Equal (Invoke-WindowsDevelopmentSetup -ProjectDirectory $fixtureRoot -FlutterDirectory 'C:\tools\flutter' -CheckOnly).Mode 'CheckOnly'
}
$tests['CheckOnly reports missing tools without attempting installation'] = {
    function script:Get-ProjectToolchain { New-TestSettings }
    function script:Get-FlutterReleaseManifest { throw 'Unexpected network request.' }
    function script:Get-DevelopmentState { $state = New-TestState; $state.Git=$null; $state.Sdk.Ready=$false; return $state }
    function script:Install-DevelopmentPrerequisites { throw 'Unexpected installer.' }
    function script:Install-FlutterSdk { throw 'Unexpected SDK install.' }
    Assert-Throws { Invoke-WindowsDevelopmentSetup -ProjectDirectory $fixtureRoot -FlutterDirectory 'C:\tools\flutter' -CheckOnly } 'Missing requirements'
}
$tests['WhatIf stops before installer, download, PATH, and Flutter commands'] = {
    function script:Get-ProjectToolchain { New-TestSettings }
    function script:Get-FlutterReleaseManifest { throw 'Unexpected network request.' }
    function script:Get-DevelopmentState { $state = New-TestState; $state.Git=$null; $state.Compiler.Ready=$false; $state.Sdk.Ready=$false; return $state }
    function script:Invoke-NativeProcess { throw 'Unexpected native process.' }
    function script:Install-DevelopmentPrerequisites { throw 'Unexpected installer.' }
    function script:Install-FlutterSdk { throw 'Unexpected SDK install.' }
    function script:Set-FlutterPath { throw 'Unexpected PATH persistence.' }
    Assert-Equal (Invoke-WindowsDevelopmentSetup -ProjectDirectory $fixtureRoot -FlutterDirectory 'C:\tools\flutter' -WhatIf).Mode 'WhatIf'
}
$tests['Modified generated source is protected before generation'] = {
    function script:Invoke-NativeProcess { return [pscustomobject]@{ExitCode=0; Output=' M lib/data/database/app_database.g.dart'} }
    Assert-Throws { Assert-GeneratedSourcesClean 'C:\tools\git.exe' $fixtureRoot } 'generated'
}
$tests['Project validation uses selected SDK and stops on command failure'] = {
    $script:observedCommands = New-Object 'System.Collections.Generic.List[string]'
    function script:Invoke-NativeProcess {
        param($FilePath, $Arguments, [switch]$Capture)
        $script:observedCommands.Add(($Arguments -join ' '))
        if ($FilePath -notlike 'C:\tools\flutter\bin\*') { throw 'Unexpected SDK path.' }
        if (($Arguments -join ' ') -eq 'pub get --enforce-lockfile') { return [pscustomobject]@{ExitCode=42;Output='restore failed'} }
        return [pscustomobject]@{ExitCode=0;Output=''}
    }
    Assert-Throws { Initialize-FlutterProject 'C:\tools\flutter' $fixtureRoot -SkipValidation } 'exit code 42'
    Assert-Equal ($script:observedCommands -contains 'run build_runner build --delete-conflicting-outputs') $false
}
$tests['An executable that cannot start never inherits a previous success code'] = {
    $null = Invoke-CheckedCommand $env:ComSpec @('/d', '/c', 'exit', '0')
    Assert-Throws { Invoke-CheckedCommand (Join-Path $fixtureRoot 'missing.exe') } 'Unable to execute'
}
$tests['SDK path cannot inject extra PATH entries'] = {
    Assert-Throws { Assert-SdkDestination 'C:\flutter;other' } 'semicolon'
}
$tests['Native prerequisite plan requests only exact reviewed WinGet packages'] = {
    $script:installerRequests = New-Object 'System.Collections.Generic.List[object]'
    function script:Invoke-NativeProcess {
        param($FilePath, $Arguments)
        $script:installerRequests.Add([pscustomobject]@{Executable=$FilePath; Arguments=$Arguments})
        return [pscustomobject]@{ExitCode=0;Output=''}
    }
    function script:Update-DevelopmentProcessPath { }
    $state = New-TestState; $state.Git=$null; $state.Compiler.Ready=$false
    Install-DevelopmentPrerequisites $state
    Assert-Equal $script:installerRequests.Count 2
    Assert-Equal $script:installerRequests[0].Executable 'C:\tools\winget.exe'
    Assert-Equal ($script:installerRequests[0].Arguments -join '|') 'install|--exact|--source|winget|--accept-source-agreements|--accept-package-agreements|--disable-interactivity|--id|Git.Git'
    Assert-Equal ($script:installerRequests[1].Arguments -join '|') 'install|--exact|--source|winget|--accept-source-agreements|--accept-package-agreements|--disable-interactivity|--id|Microsoft.VisualStudio.BuildTools|--override|--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
}
$tests['Missing Windows device prevents build and test execution'] = {
    $script:observedCommands = New-Object 'System.Collections.Generic.List[string]'
    function script:Invoke-NativeProcess {
        param($FilePath, $Arguments)
        $commandText = $Arguments -join ' '
        $script:observedCommands.Add($commandText)
        $output = if ($commandText -eq 'devices --machine') { '[{"id":"chrome","isSupported":true,"targetPlatform":"web-javascript"}]' } else { '' }
        return [pscustomobject]@{ExitCode=0;Output=$output}
    }
    $before = (Get-Location).Path
    Assert-Throws { Initialize-FlutterProject 'C:\tools\flutter' $fixtureRoot } 'Windows x64 device'
    Assert-Equal (Get-Location).Path $before
    Assert-Equal ($script:observedCommands -contains 'build windows --debug') $false
    Assert-Equal ($script:observedCommands -contains 'test') $false
}
$tests['Provisioned SDK is reused and complete validation follows dependency restoration'] = {
    $script:readySdk = New-TestSdk 'ready-runtime'
    $script:observedCommands = New-Object 'System.Collections.Generic.List[string]'
    function script:Get-DevelopmentState { $state=New-TestState; $state.Sdk.Directory=$script:readySdk; return $state }
    function script:Get-ProjectToolchain { New-TestSettings }
    function script:Resolve-FlutterRelease { param($Toolchain); return $Toolchain }
    function script:Update-DevelopmentProcessPath { }
    function script:Test-DevelopmentElevation { return $false }
    function script:Set-FlutterPath { }
    function script:Save-FlutterArchive { throw 'Unexpected SDK download.' }
    function script:Invoke-NativeProcess {
        param($FilePath, $Arguments)
        $commandText = $Arguments -join ' '
        $script:observedCommands.Add($commandText)
        $output = switch ($commandText) {
            '--version --machine' { '{"frameworkVersion":"3.44.4","frameworkRevision":"ad70ec4617166f1c38e5d2bfd388af71fda14f06","channel":"stable","dartSdkVersion":"3.12.2"}' }
            'devices --machine' { '[{"id":"windows","isSupported":true,"targetPlatform":"windows-x64"}]' }
            default { '' }
        }
        return [pscustomobject]@{ExitCode=0;Output=$output}
    }
    $result = Invoke-WindowsDevelopmentSetup -ProjectDirectory $fixtureRoot -FlutterDirectory $script:readySdk
    Assert-Equal $result.Validated $true
    Assert-Equal (($script:observedCommands | Select-Object -Last 6) -join '|') 'pub get --enforce-lockfile|run build_runner build --delete-conflicting-outputs|doctor -v|devices --machine|build windows --debug|test'
}
$tests['Elevated developer shell is rejected before installation'] = {
    function script:Get-ProjectToolchain { New-TestSettings }
    function script:Get-DevelopmentState { New-TestState }
    function script:Test-DevelopmentElevation { return $true }
    function script:Invoke-NativeProcess { return [pscustomobject]@{ExitCode=0;Output=''} }
    function script:Install-DevelopmentPrerequisites { throw 'Unexpected installer.' }
    Assert-Throws { Invoke-WindowsDevelopmentSetup -ProjectDirectory $fixtureRoot -FlutterDirectory 'C:\tools\flutter' } 'non-elevated'
}
function New-TestArchive([string]$Name, [hashtable]$Entries) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $path = Join-Path $fixtureRoot $Name
    $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries.Keys) {
            $entry = $zip.CreateEntry($name)
            $writer = New-Object IO.StreamWriter($entry.Open())
            try { $writer.Write($Entries[$name]) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
    return $path
}
$tests['SDK extraction publishes verified files and reuses them on rerun'] = {
    $script:testArchive = New-TestArchive 'sdk.zip' @{
        'flutter/bin/flutter.bat'='@echo off'; 'flutter/bin/dart.bat'='@echo off'
        'flutter/.git/HEAD'='ad70ec4617166f1c38e5d2bfd388af71fda14f06'
    }
    $script:DevelopmentSettings.FlutterSha256 = (Get-FileHash $script:testArchive -Algorithm SHA256).Hash
    function script:Save-FlutterArchive { param($Destination); Copy-Item -LiteralPath $script:testArchive -Destination $Destination }
    $destination = Join-Path $fixtureRoot 'installed-sdk'
    Assert-Equal (Install-FlutterSdk $destination) $destination
    Assert-Equal (Get-Content (Join-Path $destination '.git/HEAD')) 'ad70ec4617166f1c38e5d2bfd388af71fda14f06'
    Assert-Equal @(Get-ChildItem $fixtureRoot -Filter '.ministryshift-flutter-*' -Force).Count 0
    function script:Save-FlutterArchive { throw 'Unexpected SDK download.' }
    Assert-Equal (Install-FlutterSdk $destination) $destination
}
$tests['Verified archive traversal cannot write outside staging'] = {
    $archive = New-TestArchive 'traversal.zip' @{'flutter/../../escaped.txt'='do not extract'}
    $script:DevelopmentSettings.FlutterSha256 = (Get-FileHash $archive -Algorithm SHA256).Hash
    Assert-Throws { Assert-FlutterArchive $archive (Join-Path $fixtureRoot 'extract') } 'unsafe extraction'
    Assert-Equal (Test-Path (Join-Path $fixtureRoot 'escaped.txt')) $false
}
$tests['Multiple healthy Visual Studio instances do not cause a false reboot'] = {
    $oldProgramFiles = ${env:ProgramFiles(x86)}
    try {
        ${env:ProgramFiles(x86)} = Join-Path $fixtureRoot 'locator-root'
        $locatorDirectory = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer'
        New-Item -ItemType Directory $locatorDirectory -Force | Out-Null
        Set-Content (Join-Path $locatorDirectory 'vswhere.exe') 'fixture'
        $script:fixtureVsDirectory = Join-Path $fixtureRoot 'compiler-fixture'
        foreach ($file in @('Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe', 'VC/Tools/MSVC/14.50/bin/Hostx64/x64/cl.exe')) {
            $path = Join-Path $script:fixtureVsDirectory $file
            New-Item -ItemType Directory (Split-Path $path -Parent) -Force | Out-Null
            Set-Content $path 'fixture'
        }
        function script:Invoke-NativeProcess {
            $entry = [ordered]@{installationPath=$script:fixtureVsDirectory; installationVersion='18.10.2'; productId='Microsoft.VisualStudio.Product.BuildTools'; isRebootRequired=$false; isComplete=$true; isLaunchable=$true; isPrerelease=$false}
            return [pscustomobject]@{ExitCode=0;Output=(ConvertTo-Json -InputObject @($entry,$entry) -Compress)}
        }
        function script:Get-WindowsSdkDirectory { return 'C:\fixture-sdk' }
        $state = Get-VisualStudioState
        Assert-Equal $state.Ready $true
        Assert-Equal $state.RebootRequired $false
    } finally { ${env:ProgramFiles(x86)} = $oldProgramFiles }
}
$tests['SDK detection accepts registration only in the 32-bit registry view'] = {
    $script:fixtureKitsRoot = Join-Path $fixtureRoot 'windows-sdk'
    foreach ($file in @('Include/10.0.26100.0/um/Windows.h','Lib/10.0.26100.0/um/x64/kernel32.lib','bin/10.0.26100.0/x64/rc.exe')) {
        $path = Join-Path $script:fixtureKitsRoot $file
        New-Item -ItemType Directory (Split-Path $path -Parent) -Force | Out-Null
        Set-Content $path 'fixture'
    }
    function script:Get-ItemProperty {
        param($Path, $ErrorAction)
        if ($Path -like '*WOW6432Node*') { return [pscustomobject]@{KitsRoot10=$script:fixtureKitsRoot} }
        return $null
    }
    Assert-Equal (Get-WindowsSdkDirectory) $script:fixtureKitsRoot
}
$tests['Multi-device JSON cannot treat unsupported Windows as usable'] = {
    function script:Invoke-NativeProcess {
        param($FilePath,$Arguments)
        $output = if (($Arguments -join ' ') -eq 'devices --machine') { '[{"id":"windows","isSupported":false,"targetPlatform":"windows-x64"},{"id":"chrome","isSupported":true,"targetPlatform":"web-javascript"}]' } else { '' }
        return [pscustomobject]@{ExitCode=0;Output=$output}
    }
    Assert-Throws { Initialize-FlutterProject 'C:\tools\flutter' $fixtureRoot -SkipValidation } 'Windows x64 device'
}
$tests['Absolute launch command quotes an apostrophe in the SDK directory'] = {
    Assert-Equal (Format-FlutterLaunchCommand "C:\dev\O'Connor\flutter.bat") "& 'C:\dev\O''Connor\flutter.bat' run -d windows"
}

if (-not (Test-Path -LiteralPath $toolsPath)) {
    Write-Output 'FAIL: provisioning helpers do not exist yet.'
    exit 1
}
. $toolsPath
$script:DevelopmentSettings = New-TestSettings
$failed = 0
$originalFunctions = @{}
$originalPropertyCommand = Get-Command Get-ItemProperty
$originalSettings = $script:DevelopmentSettings.Clone()
Get-ChildItem Function: | Where-Object { $_.Name -notmatch '^Assert-(Equal|Throws)$' } | ForEach-Object { $originalFunctions[$_.Name] = $_.ScriptBlock }
foreach ($name in $tests.Keys) {
    try { & $tests[$name]; Write-Output "PASS: $name" }
    catch { $failed++; Write-Output "FAIL: $name -- $($_.Exception.Message)" }
    finally {
        foreach ($functionName in $originalFunctions.Keys) { Set-Item -Path "Function:$functionName" -Value $originalFunctions[$functionName] }
        $script:DevelopmentSettings = $originalSettings.Clone()
        if ($originalPropertyCommand.CommandType -eq 'Cmdlet') { Remove-Item Function:Get-ItemProperty -ErrorAction SilentlyContinue }
    }
}
if ([IO.Path]::GetFullPath($fixtureRoot).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
Write-Output ("Tests: {0}; failures: {1}" -f $tests.Count, $failed)
if ($failed -gt 0) { exit 1 }
