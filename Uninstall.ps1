#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InstallPath = (Join-Path $env:ProgramFiles 'Monitor Layout Assistant')
)

$ErrorActionPreference = 'Stop'
$applicationName = 'Monitor Layout Assistant'
$shortcutPath = Join-Path $env:ProgramData (
    "Microsoft\Windows\Start Menu\Programs\$applicationName.lnk"
)

if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
}

if (Test-Path -LiteralPath $InstallPath) {
    Remove-Item -LiteralPath $InstallPath -Recurse -Force
}

Write-Host "$applicationName was removed successfully." -ForegroundColor Green
