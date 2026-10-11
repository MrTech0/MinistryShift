#Requires -Version 5.1
# Shared provisioning functions. Loading this file performs no provisioning.
$script:DevelopmentSettings = @{
    FlutterVersion = '3.44.4'
    DartVersion = '3.12.2'
    FlutterRevision = 'ad70ec4617166f1c38e5d2bfd388af71fda14f06'
    FlutterSha256 = '8f2d6224fc6872d2f7f180de86cde989fcea3776efe0edf48a9aac2cd9be2b1b'
    FlutterUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.44.4-stable.zip'
    BuildToolsVersion = '18.10.2'
}

function Assert-SdkDestination {
    param([Parameter(Mandatory)][string]$Directory)
    if ($Directory -notmatch '^[a-zA-Z]:[\\/]') { throw 'FlutterDirectory must be an absolute local drive path.' }
    if ($Directory -match '\s') { throw 'FlutterDirectory must not contain whitespace.' }
    if ($Directory.Contains(';')) { throw 'FlutterDirectory must not contain a semicolon because it is added to PATH.' }
    $fullPath = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    if ($fullPath -eq [IO.Path]::GetPathRoot($fullPath).TrimEnd('\', '/')) { throw 'A filesystem root cannot be an SDK directory.' }
    $ancestor = $fullPath
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if (-not $item.PSIsContainer) { throw "SDK path is occupied by a file: $ancestor" }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "SDK path contains a reparse point: $ancestor" }
        }
        $ancestor = Split-Path -Path $ancestor -Parent
    }
    return $fullPath
}

function Add-PathEntry {
    param([AllowNull()][AllowEmptyString()][string]$PathValue, [string]$Entry)
    $normalized = $Entry.TrimEnd('\', '/')
    foreach ($part in ($PathValue -split ';')) {
        if ([Environment]::ExpandEnvironmentVariables($part.Trim('"')).TrimEnd('\', '/') -ieq $normalized) { return $PathValue }
    }
    if ([string]::IsNullOrEmpty($PathValue)) { return $Entry }
    return $PathValue.TrimEnd(';') + ';' + $Entry
}

function Invoke-NativeProcess {
    param([string]$FilePath, [string[]]$Arguments = @(), [switch]$Capture)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Unable to execute $FilePath; the executable is missing." }
    # Native applications update the global automatic variable in PowerShell 5.1.
    $global:LASTEXITCODE = $null
    $previousErrorAction = $ErrorActionPreference
    try {
        # PowerShell 5.1 treats native stderr as error records, even on exit 0.
        $ErrorActionPreference = 'Continue'
        if ($Capture) { $lines = & $FilePath @Arguments 2>&1 }
        else { & $FilePath @Arguments | Out-Host }
        $code = $global:LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    if ($null -eq $code) { throw "Unable to execute $FilePath." }
    $output = if ($Capture) { ($lines | ForEach-Object { $_.ToString() }) -join "`n" } else { '' }
    return [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function Invoke-CheckedCommand {
    param([string]$FilePath, [string[]]$Arguments = @(), [switch]$Capture)
    $result = Invoke-NativeProcess -FilePath $FilePath -Arguments $Arguments -Capture:$Capture
    if ($result.ExitCode -ne 0) { throw "$([IO.Path]::GetFileName($FilePath)) failed with exit code $($result.ExitCode). $($result.Output)" }
    if ($Capture) { return $result.Output }
}

function Assert-InstallerExitCode {
    param([int]$ExitCode)
    # WinGet maps installer reboot results to its own signed HRESULT values.
    if ($ExitCode -in @(3010, 1641, -1978334967, -1978334966, -1978334965)) {
        $errorInfo = New-Object System.Exception 'The installer requires a reboot. Restart Windows and rerun setup.'
        $errorInfo.Data['ExitCode'] = 3010
        throw $errorInfo
    }
    if ($ExitCode -ne 0) { throw "Installer failed with exit code $ExitCode. Check its installation log and rerun setup." }
}

function Get-DevelopmentHost {
    $os = Get-CimInstance Win32_OperatingSystem
    $architecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITEW6432')
    if (-not $architecture) { $architecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE') }
    return [pscustomobject]@{
        Build = [int]$os.BuildNumber
        Architecture = $architecture
        Is64BitProcess = [Environment]::Is64BitProcess
        IsWindows11 = ($os.Caption -match 'Windows 11' -and $os.ProductType -eq 1)
    }
}

function Assert-DevelopmentHost {
    param($HostInfo)
    if (-not $HostInfo.IsWindows11 -or $HostInfo.Build -lt 22000) { throw 'Windows 11 (build 22000 or newer) is required.' }
    if ($HostInfo.Architecture -ne 'AMD64') { throw 'This setup supports Windows x64 only; Windows on ARM is unsupported.' }
    if (-not $HostInfo.Is64BitProcess) { throw 'Use 64-bit PowerShell to provision this project.' }
}

function Find-DevelopmentCommand {
    param([string]$Name)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    if ($Name -eq 'git.exe') {
        foreach ($candidate in @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
}

function Assert-ProjectToolchain {
    param([string]$ProjectDirectory)
    foreach ($relative in @('pubspec.yaml', 'pubspec.lock', 'windows/CMakeLists.txt', 'assets/fonts/Arial-Regular.ttf', 'assets/fonts/Arial-Bold.ttf')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectDirectory $relative) -PathType Leaf)) { throw "Missing project file: $relative. Run setup from a complete MinistryShift checkout." }
    }
    $pubspec = Get-Content -LiteralPath (Join-Path $ProjectDirectory 'pubspec.yaml') -Raw
    if ($pubspec -notmatch '(?m)^\s+sdk:\s*[''"]?\^3\.12\.2[''"]?\s*$') { throw 'The project Dart constraint changed; review the provisioning toolchain before continuing.' }
    foreach ($workflow in @('release.yml', 'codeql.yml')) {
        $versions = [regex]::Matches((Get-Content -LiteralPath (Join-Path $ProjectDirectory ".github/workflows/$workflow") -Raw), '(?m)^\s+flutter-version:\s*[''"]?([^''"\s]+)')
        if ($versions.Count -eq 0) { throw "Flutter version is missing in $workflow; review the provisioning toolchain." }
        foreach ($version in $versions) {
            if ($version.Groups[1].Value -ne $script:DevelopmentSettings.FlutterVersion) { throw "Flutter version changed in $workflow; update setup intentionally." }
        }
    }
}

function Get-FlutterSdkState {
    param([string]$Directory)
    $directoryPath = Assert-SdkDestination $Directory
    if (-not (Test-Path -LiteralPath $directoryPath)) { return [pscustomobject]@{ Directory=$directoryPath; Ready=$false } }
    if (@(Get-ChildItem -LiteralPath $directoryPath -Force).Count -eq 0) { return [pscustomobject]@{ Directory=$directoryPath; Ready=$false } }
    foreach ($relative in @('bin/flutter.bat', 'bin/dart.bat', '.git/HEAD')) {
        if (-not (Test-Path -LiteralPath (Join-Path $directoryPath $relative) -PathType Leaf)) { throw "SDK destination is occupied by an unrecognized installation: $directoryPath. Choose a different FlutterDirectory." }
    }
    # Reading Git metadata avoids initializing Flutter caches in inspection modes.
    $revision = (Get-Content -LiteralPath (Join-Path $directoryPath '.git/HEAD') -Raw).Trim()
    if ($revision -match '^ref: (refs/[^\s]+)$') {
        $reference = $Matches[1]
        $referencePath = Join-Path $directoryPath ".git/$reference"
        if (Test-Path -LiteralPath $referencePath -PathType Leaf) { $revision = (Get-Content -LiteralPath $referencePath -Raw).Trim() }
        else {
            $packedPath = Join-Path $directoryPath '.git/packed-refs'
            $revision = ''
            if (Test-Path -LiteralPath $packedPath) {
                foreach ($line in Get-Content -LiteralPath $packedPath) {
                    if ($line -match ('^([0-9a-f]{40}) ' + [regex]::Escape($reference) + '$')) { $revision = $Matches[1]; break }
                }
            }
        }
    }
    if ($revision -ne $script:DevelopmentSettings.FlutterRevision) { throw "SDK at $directoryPath is not the reviewed Flutter 3.44.4 revision. Existing SDKs are never overwritten." }
    return [pscustomobject]@{ Directory=$directoryPath; Ready=$true }
}

function Get-WindowsSdkDirectory {
    foreach ($registryPath in @('HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots')) {
        $roots = Get-ItemProperty $registryPath -ErrorAction SilentlyContinue
        if (-not $roots -or -not $roots.KitsRoot10) { continue }
        $includePath = Join-Path $roots.KitsRoot10 'Include'
        if (-not (Test-Path -LiteralPath $includePath)) { continue }
        foreach ($version in (Get-ChildItem -LiteralPath $includePath -Directory | Sort-Object Name -Descending)) {
            if ((Test-Path -LiteralPath (Join-Path $version.FullName 'um/Windows.h')) -and
                (Test-Path -LiteralPath (Join-Path $roots.KitsRoot10 "Lib/$($version.Name)/um/x64/kernel32.lib")) -and
                (Test-Path -LiteralPath (Join-Path $roots.KitsRoot10 "bin/$($version.Name)/x64/rc.exe"))) { return $roots.KitsRoot10 }
        }
    }
    return $null
}

function Get-VisualStudioState {
    $locator = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $empty = [pscustomobject]@{ Ready=$false; Directory=$null; RepairDirectory=$null; RebootRequired=$false }
    if (-not (Test-Path -LiteralPath $locator -PathType Leaf)) { return $empty }
    $common = @('-products', '*', '-version', '[16.0,19.0)', '-format', 'json')
    # Assign JSON before enumerating: PS 5.1 emits a top-level JSON array as one object.
    $instances = Invoke-CheckedCommand $locator ($common + @('-all')) -Capture | ConvertFrom-Json
    foreach ($instance in @($instances)) {
        if ($instance.isRebootRequired) { $empty.RebootRequired = $true }
        if ($instance.productId -eq 'Microsoft.VisualStudio.Product.BuildTools' -and -not $instance.isPrerelease) { $empty.RepairDirectory = $instance.installationPath }
    }
    foreach ($workload in @('Microsoft.VisualStudio.Workload.NativeDesktop', 'Microsoft.VisualStudio.Workload.VCTools')) {
        $requirements = @('-requires', $workload, 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', 'Microsoft.VisualStudio.Component.VC.CMake.Project')
        $candidateInstances = Invoke-CheckedCommand $locator ($common + $requirements) -Capture | ConvertFrom-Json
        foreach ($instance in ($candidateInstances | Sort-Object installationVersion -Descending)) {
            if (-not $instance -or $instance.isPrerelease -or -not $instance.isComplete -or -not $instance.isLaunchable) { continue }
            $cmake = Join-Path $instance.installationPath 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
            $compilerRoot = Join-Path $instance.installationPath 'VC/Tools/MSVC'
            $compilers = @(Get-ChildItem -LiteralPath $compilerRoot -Filter cl.exe -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\Hostx64\\x64\\cl\.exe$' })
            if ((Test-Path -LiteralPath $cmake -PathType Leaf) -and $compilers.Count -gt 0 -and (Get-WindowsSdkDirectory)) {
                return [pscustomobject]@{ Ready=$true; Directory=$instance.installationPath; RepairDirectory=$empty.RepairDirectory; RebootRequired=($empty.RebootRequired -or $instance.isRebootRequired) }
            }
        }
    }
    return $empty
}

function Get-DevelopmentState {
    param([string]$ProjectDirectory, [string]$FlutterDirectory)
    Assert-DevelopmentHost (Get-DevelopmentHost)
    Assert-ProjectToolchain $ProjectDirectory
    $sdk = Get-FlutterSdkState $FlutterDirectory
    return [pscustomobject]@{
        ProjectDirectory = [IO.Path]::GetFullPath($ProjectDirectory)
        Sdk = $sdk
        Git = Find-DevelopmentCommand 'git.exe'
        Winget = Find-DevelopmentCommand 'winget.exe'
        Compiler = Get-VisualStudioState
    }
}

function Get-ProvisioningPlan {
    param($State)
    if ($State.Compiler.RebootRequired) { Assert-InstallerExitCode 3010 }
    if (-not $State.Git) { 'Install Git for Windows (Git.Git).' }
    if (-not $State.Compiler.Ready) {
        if ($State.Compiler.RepairDirectory) { 'Add C++ workload and recommended components to existing Build Tools.' }
        else { 'Install Visual Studio 2026 Build Tools 18.10.2 with C++, CMake, and Windows SDK.' }
    }
    if (-not $State.Sdk.Ready) { "Download, verify, and extract Flutter 3.44.4 to $($State.Sdk.Directory)." }
    'Add Flutter bin to user PATH if needed; prepare Windows caches and locked project dependencies.'
    'Generate Drift code and verify the Windows device.'
}

function Assert-FlutterArchive {
    param([string]$Archive, [string]$ExtractionDirectory)
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ine $script:DevelopmentSettings.FlutterSha256) { throw 'Flutter archive SHA-256 verification failed. Nothing was extracted or executed.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $prefix = [IO.Path]::GetFullPath($ExtractionDirectory).TrimEnd('\') + '\'
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -notmatch '^flutter[/\\]' -or $entry.FullName.Contains(':') -or
                -not [IO.Path]::GetFullPath((Join-Path $ExtractionDirectory $entry.FullName)).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Flutter archive contains an unsafe extraction path.'
            }
        }
    } finally { $zip.Dispose() }
}

function Save-FlutterArchive {
    param([string]$Destination)
    $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
    $oldProgress = $ProgressPreference
    try {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
        # PowerShell 5.1's per-chunk progress rendering is very slow for this archive.
        $ProgressPreference = 'SilentlyContinue'
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Write-Host "Downloading the official Flutter archive (attempt $attempt/3)..."
                Invoke-WebRequest -Uri $script:DevelopmentSettings.FlutterUrl -OutFile $Destination -UseBasicParsing -TimeoutSec 1800 -ErrorAction Stop
                return
            } catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds 2 }
        }
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
        $ProgressPreference = $oldProgress
    }
}

function Install-FlutterSdk {
    param([string]$Directory)
    $sdk = Get-FlutterSdkState $Directory
    if ($sdk.Ready) { return $sdk.Directory }
    $parent = Split-Path $sdk.Directory -Parent
    $null = New-Item -ItemType Directory -Path $parent -Force
    $staging = Join-Path $parent ('.ministryshift-flutter-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $staging
    try {
        $archive = Join-Path $staging 'flutter.zip'
        $extraction = Join-Path $staging 'unpacked'
        Save-FlutterArchive $archive
        Assert-FlutterArchive $archive $extraction
        Write-Host 'Extracting the verified Flutter SDK...'
        Expand-Archive -LiteralPath $archive -DestinationPath $extraction
        $extractedSdk = Get-FlutterSdkState (Join-Path $extraction 'flutter')
        if (-not $extractedSdk.Ready) { throw 'Verified archive is missing the Flutter SDK.' }
        $null = Assert-SdkDestination $sdk.Directory
        if (Test-Path -LiteralPath $sdk.Directory) {
            # Non-recursive deletion fails if another process added content.
            [IO.Directory]::Delete($sdk.Directory, $false)
        }
        # Staging shares the destination volume. Directory.Move refuses overwrite.
        [IO.Directory]::Move($extractedSdk.Directory, $sdk.Directory)
        return $sdk.Directory
    } finally {
        $resolvedStaging = [IO.Path]::GetFullPath($staging)
        $expectedParent = [IO.Path]::GetFullPath($parent).TrimEnd('\') + '\'
        if ($resolvedStaging.StartsWith($expectedParent, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedStaging) -match '^\.ministryshift-flutter-[0-9a-f]{32}$') {
            $reparsePoints = @(Get-ChildItem -LiteralPath $resolvedStaging -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
            if ($reparsePoints.Count -eq 0 -and -not ((Get-Item -LiteralPath $resolvedStaging -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
            } else { Write-Warning "Staging directory contains reparse points; inspect it manually: $resolvedStaging" }
        }
    }
}

function Update-DevelopmentProcessPath {
    foreach ($scope in @('Machine', 'User')) {
        foreach ($entry in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
            if ($entry) { $env:Path = Add-PathEntry $env:Path ([Environment]::ExpandEnvironmentVariables($entry)) }
        }
    }
}

function Set-FlutterPath {
    param([string]$Directory, [string]$GitPath)
    $bin = Join-Path $Directory 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $updated = Add-PathEntry $userPath $bin
    if ($updated -cne $userPath) { [Environment]::SetEnvironmentVariable('Path', $updated, 'User') }
    $env:Path = Add-PathEntry $env:Path (Split-Path $GitPath -Parent)
    $remaining = @($env:Path -split ';' | Where-Object { [Environment]::ExpandEnvironmentVariables($_.Trim('"')).TrimEnd('\', '/') -ine $bin.TrimEnd('\') })
    $env:Path = $bin + ';' + ($remaining -join ';')
}

function Install-DevelopmentPrerequisites {
    param($State)
    $needsWinget = (-not $State.Git) -or (-not $State.Compiler.Ready -and -not $State.Compiler.RepairDirectory)
    if ($needsWinget -and -not $State.Winget) { throw 'WinGet is missing. Install or update Microsoft App Installer from https://aka.ms/getwinget, reopen PowerShell, and rerun setup.' }
    $wingetArguments = @('install', '--exact', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if (-not $State.Git) {
        Write-Host 'Installing Git for Windows using WinGet...'
        $result = Invoke-NativeProcess $State.Winget ($wingetArguments + @('--id', 'Git.Git'))
        Assert-InstallerExitCode $result.ExitCode
    }
    if (-not $State.Compiler.Ready) {
        Write-Host 'Preparing C++ Build Tools, CMake, and Windows SDK. An installer may request UAC elevation...'
        if ($State.Compiler.RepairDirectory) {
            $installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/setup.exe'
            $signature = Get-AuthenticodeSignature -LiteralPath $installer
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') { throw 'Visual Studio Installer does not have a valid Microsoft signature.' }
            $installerArguments = @('modify', '--installPath', ('"' + $State.Compiler.RepairDirectory + '"'), '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended', '--passive', '--norestart')
            $process = Start-Process -FilePath $installer -ArgumentList $installerArguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            Assert-InstallerExitCode $process.ExitCode
        } else {
            $override = '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
            $result = Invoke-NativeProcess $State.Winget ($wingetArguments + @('--id', 'Microsoft.VisualStudio.BuildTools', '--version', $script:DevelopmentSettings.BuildToolsVersion, '--override', $override))
            if ($result.ExitCode -ne 0 -and (Get-VisualStudioState).RebootRequired) { Assert-InstallerExitCode 3010 }
            Assert-InstallerExitCode $result.ExitCode
        }
    }
    Update-DevelopmentProcessPath
}

function Assert-GeneratedSourcesClean {
    param([string]$GitPath, [string]$ProjectDirectory)
    $status = Invoke-CheckedCommand $GitPath @('-C', $ProjectDirectory, 'status', '--porcelain', '--untracked-files=all', '--', '*.g.dart') -Capture
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw "There are uncommitted generated Dart files. Commit or back up these edits before code generation:`n$status" }
}

function Initialize-FlutterProject {
    param([string]$Directory, [string]$ProjectDirectory, [switch]$SkipValidation)
    $flutter = Join-Path $Directory 'bin/flutter.bat'
    $dart = Join-Path $Directory 'bin/dart.bat'
    Push-Location -LiteralPath $ProjectDirectory
    try {
        Invoke-CheckedCommand $flutter @('config', '--enable-windows-desktop')
        Invoke-CheckedCommand $flutter @('precache', '--windows')
        Invoke-CheckedCommand $flutter @('pub', 'get', '--enforce-lockfile')
        Invoke-CheckedCommand $dart @('run', 'build_runner', 'build', '--delete-conflicting-outputs')
        Invoke-CheckedCommand $flutter @('doctor', '-v')
        $devices = Invoke-CheckedCommand $flutter @('devices', '--machine') -Capture | ConvertFrom-Json
        if (@($devices | Where-Object { $_.id -eq 'windows' -and $_.isSupported -and $_.targetPlatform -eq 'windows-x64' }).Count -eq 0) { throw 'Flutter did not report a supported Windows x64 device. Resolve the Windows and Visual Studio sections of flutter doctor.' }
        if (-not $SkipValidation) {
            Write-Host 'Validating a Windows debug build and the application tests...'
            Invoke-CheckedCommand $flutter @('build', 'windows', '--debug')
            Invoke-CheckedCommand $flutter @('test')
        }
    } finally { Pop-Location }
}

function Test-DevelopmentElevation {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-FlutterLaunchCommand {
    param([string]$FilePath)
    return "& '" + $FilePath.Replace("'", "''") + "' run -d windows"
}

function Invoke-WindowsDevelopmentSetup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [string]$FlutterDirectory,
        [switch]$CheckOnly,
        [switch]$SkipValidation
    )
    if (-not $FlutterDirectory) {
        $FlutterDirectory = Join-Path $env:USERPROFILE 'develop/flutter-3.44.4'
        $existing = Find-DevelopmentCommand 'flutter.bat'
        if ($existing) {
            try {
                $existingSdk = Get-FlutterSdkState (Split-Path (Split-Path $existing -Parent) -Parent)
                if ($existingSdk.Ready) { $FlutterDirectory = $existingSdk.Directory }
            } catch { Write-Host 'A different Flutter SDK is on PATH; setup will use a separate pinned SDK.' }
        }
    }
    $state = Get-DevelopmentState $ProjectDirectory $FlutterDirectory
    $plan = @(Get-ProvisioningPlan $state)
    foreach ($step in $plan) { Write-Host $step }
    if ($CheckOnly) {
        if (-not $state.Git -or -not $state.Compiler.Ready -or -not $state.Sdk.Ready) { throw 'Missing requirements. Run setup without CheckOnly to provision them.' }
        Write-Host 'Prerequisites are present. CheckOnly does not compile, test, or initialize Flutter caches.'
        return [pscustomobject]@{Mode='CheckOnly'; Sdk=$state.Sdk.Directory; Validated=$false}
    }
    if (-not $PSCmdlet.ShouldProcess($state.ProjectDirectory, 'Provision Windows development prerequisites and prepare Flutter project')) {
        return [pscustomobject]@{Mode='WhatIf'; Sdk=$state.Sdk.Directory; Validated=$false}
    }
    if (Test-DevelopmentElevation) { throw 'Run setup from a non-elevated developer PowerShell. Only prerequisite installers may request UAC elevation.' }
    if ($state.Git) { Assert-GeneratedSourcesClean $state.Git $state.ProjectDirectory }
    Install-DevelopmentPrerequisites $state
    $state = Get-DevelopmentState $state.ProjectDirectory $state.Sdk.Directory
    if ($state.Compiler.RebootRequired) { Assert-InstallerExitCode 3010 }
    if (-not $state.Git -or -not $state.Compiler.Ready) { throw 'Native prerequisites are incomplete. Check Visual Studio Installer for the C++ workload, CMake, Windows SDK, and pending reboot, then rerun setup.' }
    Assert-GeneratedSourcesClean $state.Git $state.ProjectDirectory
    $directory = Install-FlutterSdk $state.Sdk.Directory
    # The selected SDK must find Git even before its persistent PATH is added.
    $env:Path = Add-PathEntry $env:Path (Split-Path $state.Git -Parent)
    $flutter = Join-Path $directory 'bin/flutter.bat'
    $version = Invoke-CheckedCommand $flutter @('--version', '--machine') -Capture | ConvertFrom-Json
    if ($version.frameworkVersion -ne '3.44.4' -or $version.channel -ne 'stable' -or $version.dartSdkVersion -notmatch '^3\.12\.2(?:\s|$)') { throw 'The selected SDK runtime does not match Flutter 3.44.4 stable / Dart 3.12.2.' }
    $existingFlutter = Find-DevelopmentCommand 'flutter.bat'
    if ($existingFlutter -and $existingFlutter -ine $flutter) { Write-Warning 'Another Flutter SDK is on PATH. Use the absolute launch command below in new terminals to select this project SDK.' }
    Set-FlutterPath $directory $state.Git
    Initialize-FlutterProject $directory $state.ProjectDirectory -SkipValidation:$SkipValidation
    Write-Host "SDK: $directory"
    Write-Host "Compiler: $($state.Compiler.Directory)"
    if ($SkipValidation) { Write-Host 'Project prepared. Compilation and tests were skipped and remain unverified.' }
    else { Write-Host 'Project prepared; Windows debug compilation and flutter test passed.' }
    Write-Host ('From the project directory, run: ' + (Format-FlutterLaunchCommand $flutter))
    Write-Host 'When this SDK is selected on PATH: flutter run -d windows. Press r for hot reload, R for hot restart, q to stop.'
    return [pscustomobject]@{Mode='Provision'; Sdk=$directory; Validated=(-not $SkipValidation)}
}
