#Requires -Version 5.1
<#
.SYNOPSIS
Prepares an existing MinistryShift checkout for Windows desktop development.
.DESCRIPTION
Installs missing Git/C++ tools and verified Flutter 3.44.4, restores locked
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
. (Join-Path $PSScriptRoot 'windows-dev-tools.ps1')
try {
    $projectDirectory = Split-Path $PSScriptRoot -Parent
    $null = Invoke-WindowsDevelopmentSetup -ProjectDirectory $projectDirectory @PSBoundParameters
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    if ($_.Exception.Data.Contains('ExitCode')) { exit [int]$_.Exception.Data['ExitCode'] }
    exit 1
}
