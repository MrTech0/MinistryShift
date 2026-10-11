#Requires -Version 5.1
<#
.SYNOPSIS
Prepares an existing MinistryShift checkout for Windows desktop development.
.DESCRIPTION
Installs missing Git/C++ tools and the project-selected Flutter SDK, restores locked
dependencies, generates Drift code, and validates a debug build and tests.
Run from a non-elevated 64-bit Windows 11 PowerShell. Installers may request UAC.
The script accepts WinGet source/package agreements when installing prerequisites.
.PARAMETER CheckOnly
Checks existing prerequisites without downloads, installation, or Flutter execution.
.PARAMETER FlutterDirectory
Absolute SDK location without whitespace. Existing incompatible directories are protected.
.PARAMETER SkipValidation
Skips the debug build and flutter test; setup will report them as unverified.
.EXAMPLE
.\scripts\setup-windows-dev.ps1 -WhatIf
.EXAMPLE
.\scripts\setup-windows-dev.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$CheckOnly, [string]$FlutterDirectory, [switch]$SkipValidation)
$ErrorActionPreference = 'Stop'
$script:DevelopmentSettings = @{}

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

function ConvertFrom-YamlLiteral {
    param([string]$Value, [string]$Source)
    if ($Value -notmatch '^\s*(?:''(?<single>(?:[^'']|'''')*)''|"(?<double>[^"\\]*)"|(?<plain>[^#]*?))\s*(?:#.*)?$') { throw "Expected a simple YAML literal in $Source." }
    if ($Value.TrimStart().StartsWith("'")) { return $Matches.single.Replace("''", "'") }
    if ($Value.TrimStart().StartsWith('"')) { return $Matches.double }
    return $Matches.plain.Trim()
}

function Get-ProjectToolchain {
    param([string]$ProjectDirectory)
    foreach ($relative in @('pubspec.yaml', 'pubspec.lock', 'windows/CMakeLists.txt', 'assets/fonts/Arial-Regular.ttf', 'assets/fonts/Arial-Bold.ttf')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectDirectory $relative) -PathType Leaf)) { throw "Missing project file: $relative. Run setup from a complete MinistryShift checkout." }
    }
    $pubspec = Get-Content -LiteralPath (Join-Path $ProjectDirectory 'pubspec.yaml') -Raw
    $environment = [regex]::Match($pubspec, '(?m)^environment:[ \t]*(?:#[^\r\n]*)?\r?\n(?<body>(?:[ \t]+[^\r\n]*(?:\r?\n|$)|\r?\n)*)')
    $sdk = [regex]::Match($environment.Groups['body'].Value, '(?m)^[ \t]+sdk:[ \t]*(?<value>[^\r\n]+)')
    if (-not $sdk.Success) { throw 'Missing environment.sdk constraint in pubspec.yaml.' }
    $dartConstraint = ConvertFrom-YamlLiteral $sdk.Groups['value'].Value 'pubspec.yaml environment.sdk'
    if (-not $dartConstraint) { throw 'The Dart SDK constraint must not be empty.' }
    $declarations = @()
    $workflowDirectory = Join-Path $ProjectDirectory '.github/workflows'
    foreach ($workflow in (Get-ChildItem -LiteralPath $workflowDirectory -File | Where-Object { $_.Extension -in @('.yml', '.yaml') })) {
        $yaml = Get-Content -LiteralPath $workflow.FullName -Raw
        $previousCount = $declarations.Count
        # Count identifiers independently of supported layout, so unusual YAML cannot be skipped.
        $references = [regex]::Matches($yaml, '(?im)^(?![ \t]*#)[^\r\n]*subosito/flutter-action@').Count
        $steps = [regex]::Split($yaml, '(?m)(?=^[ \t]*-[ \t]+[a-zA-Z][a-zA-Z0-9_-]*:)')
        foreach ($step in $steps) {
            if ($step -notmatch '(?m)^[ \t]*(?:-[ \t]+)?uses:[ \t]*[''"]?subosito/flutter-action@') { continue }
            $with = [regex]::Match($step, '(?m)^(?<indent>[ \t]+)with:[ \t]*(?:#[^\r\n]*)?\r?$')
            $inputs = @{}
            if ($with.Success) {
                foreach ($line in ($step.Substring($with.Index + $with.Length) -split '\r?\n')) {
                    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
                    $indent = [regex]::Match($line, '^[ \t]*').Length
                    if ($indent -le $with.Groups['indent'].Length) { break }
                    if ($line -match '^[ \t]+(?<key>[a-z-]+):[ \t]*(?<value>.+)$') {
                        $key = $Matches.key; $value = $Matches.value
                        $inputs[$key] = ConvertFrom-YamlLiteral $value $workflow.Name
                    } else { throw "Unsupported Flutter action input YAML in $($workflow.Name). Use unquoted input keys and simple literal values." }
                }
            }
            if ($inputs.ContainsKey('flutter-version-file')) { throw "Unsupported flutter-version-file in $($workflow.Name). Declare the project version directly in the Flutter action inputs." }
            $version = $inputs['flutter-version']
            $channel = if ($inputs['channel']) { $inputs['channel'] } else { 'stable' }
            if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "Declare an exact literal flutter-version for subosito/flutter-action in $($workflow.Name). Expressions, ranges, and flutter-version-file need an explicit project configuration review." }
            if ($channel -cnotin @('stable','beta')) { throw "Unsupported Flutter channel '$channel' in $($workflow.Name); an official stable or beta Windows archive is required." }
            $declarations += [pscustomobject]@{Version=$version;Channel=$channel;Source=$workflow.Name}
        }
        if (($declarations.Count - $previousCount) -ne $references) { throw "Unsupported Flutter action YAML structure in $($workflow.Name). Use separate literal uses/with lines so all version declarations can be verified." }
    }
    if ($declarations.Count -eq 0) { throw 'No exact Flutter version is declared in the project workflows.' }
    $unique = @($declarations | ForEach-Object { $_.Version + '/' + $_.Channel } | Sort-Object -Unique -CaseSensitive)
    if ($unique.Count -ne 1) { throw ('Conflicting Flutter versions/channels in project workflows: ' + ($unique -join ', ') + '. Align project configuration before provisioning.') }
    return @{FlutterVersion=$declarations[0].Version;FlutterChannel=$declarations[0].Channel;DartConstraint=$dartConstraint}
}

function Get-FlutterReleaseManifest {
    $oldProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try { return Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' -TimeoutSec 60 -ErrorAction Stop }
            catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds 2 }
        }
    } finally { [Net.ServicePointManager]::SecurityProtocol = $oldProtocol }
}

function Resolve-FlutterRelease {
    param([hashtable]$Toolchain)
    $manifest = Get-FlutterReleaseManifest
    $baseUrl = 'https://storage.googleapis.com/flutter_infra_release/releases'
    if ($manifest.base_url -cne $baseUrl) { throw 'Flutter manifest contains an invalid download base URL.' }
    $candidates = @($manifest.releases | Where-Object {
        $_.version -ceq $Toolchain.FlutterVersion -and $_.channel -ceq $Toolchain.FlutterChannel -and
        ($_.dart_sdk_arch -eq 'x64' -or (-not $_.dart_sdk_arch -and $_.archive -notmatch 'arm64'))
    })
    if ($candidates.Count -ne 1) { throw "Flutter $($Toolchain.FlutterVersion) $($Toolchain.FlutterChannel) Windows x64 release not found uniquely in the official manifest. Project configuration was not changed." }
    $release = $candidates[0]
    if ($release.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or $release.hash -notmatch '^[0-9a-fA-F]{40}$' -or -not $release.dart_sdk_version) { throw 'Flutter release manifest contains invalid integrity/version metadata.' }
    if ($release.archive -notmatch '^(stable|beta)/windows/flutter_windows_[0-9A-Za-z._+-]+-(stable|beta)\.zip$') { throw 'Flutter release manifest contains an unsafe archive path.' }
    $resolved = $Toolchain.Clone()
    $resolved.DartVersion = $release.dart_sdk_version
    $resolved.FlutterRevision = $release.hash
    $resolved.FlutterSha256 = $release.sha256
    $resolved.FlutterUrl = $baseUrl + '/' + $release.archive
    return $resolved
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
    $matchesProject = $false
    if ($script:DevelopmentSettings.FlutterRevision) {
        $matchesProject = $revision -eq $script:DevelopmentSettings.FlutterRevision
    } else {
        $versionFile = Join-Path $directoryPath 'bin/cache/flutter.version.json'
        if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
            $metadata = Get-Content -LiteralPath $versionFile -Raw | ConvertFrom-Json
            $matchesProject = ($metadata.frameworkVersion -ceq $script:DevelopmentSettings.FlutterVersion -and
                $metadata.channel -ceq $script:DevelopmentSettings.FlutterChannel -and $metadata.frameworkRevision -eq $revision)
        }
    }
    if (-not $matchesProject -or $revision -notmatch '^[0-9a-fA-F]{40}$') { throw "SDK at $directoryPath cannot be verified as project Flutter $($script:DevelopmentSettings.FlutterVersion) $($script:DevelopmentSettings.FlutterChannel). Existing SDKs are never overwritten. Choose a different FlutterDirectory if necessary." }
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
    $common = @('-products', '*', '-format', 'json')
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
        else { 'Install current Visual Studio Build Tools from WinGet with C++, CMake, and Windows SDK.' }
    }
    if (-not $State.Sdk.Ready) { "Download, verify, and extract project Flutter $($script:DevelopmentSettings.FlutterVersion) $($script:DevelopmentSettings.FlutterChannel) to $($State.Sdk.Directory)." }
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
            $result = Invoke-NativeProcess $State.Winget ($wingetArguments + @('--id', 'Microsoft.VisualStudio.BuildTools', '--override', $override))
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
    $script:DevelopmentSettings = Get-ProjectToolchain $ProjectDirectory
    Write-Host "Project toolchain: Flutter $($script:DevelopmentSettings.FlutterVersion) $($script:DevelopmentSettings.FlutterChannel); Dart constraint $($script:DevelopmentSettings.DartConstraint)."
    if (-not $FlutterDirectory) {
        $FlutterDirectory = Join-Path $env:USERPROFILE ("develop/flutter-" + $script:DevelopmentSettings.FlutterVersion)
        $existing = Find-DevelopmentCommand 'flutter.bat'
        if ($existing) {
            try {
                $existingSdk = Get-FlutterSdkState (Split-Path (Split-Path $existing -Parent) -Parent)
                if ($existingSdk.Ready) { $FlutterDirectory = $existingSdk.Directory }
            } catch { Write-Host 'A different Flutter SDK is on PATH; setup will use a separate SDK matching the project.' }
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
    Write-Host 'Resolving the project SDK from the official Flutter release manifest...'
    $script:DevelopmentSettings = Resolve-FlutterRelease $script:DevelopmentSettings
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
    if ($version.frameworkVersion -cne $script:DevelopmentSettings.FlutterVersion -or $version.channel -cne $script:DevelopmentSettings.FlutterChannel -or
        $version.frameworkRevision -ne $script:DevelopmentSettings.FlutterRevision -or $version.dartSdkVersion -cne $script:DevelopmentSettings.DartVersion) { throw 'The selected SDK runtime does not match the project release and its bundled Dart SDK.' }
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

# Dot-sourcing exposes functions for the isolated test harness without provisioning.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $projectDirectory = Split-Path $PSScriptRoot -Parent
        $null = Invoke-WindowsDevelopmentSetup -ProjectDirectory $projectDirectory @PSBoundParameters
        exit 0
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        if ($_.Exception.Data.Contains('ExitCode')) { exit [int]$_.Exception.Data['ExitCode'] }
        exit 1
    }
}
