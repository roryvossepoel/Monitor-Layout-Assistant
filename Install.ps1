#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:ProgramFiles 'Monitor Layout Assistant'),
    [string]$MultiMonitorToolPath
)

$ErrorActionPreference = 'Stop'
$applicationName = 'Monitor Layout Assistant'
$sourceScript = Join-Path $PSScriptRoot 'MonitorLayoutAssistant.ps1'
$sourceLanguages = Join-Path $PSScriptRoot 'Languages'
$sourceAssets = Join-Path $PSScriptRoot 'Assets'
$startMenuPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuPath "$applicationName.lnk"
$recommendedPowerShellW = Join-Path $env:SystemRoot (
    'System32\WindowsPowerShell\v1.0\powershellw.exe'
)
$nativePowerShell = Join-Path $env:SystemRoot (
    'System32\WindowsPowerShell\v1.0\powershell.exe'
)

if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
    throw "MonitorLayoutAssistant.ps1 was not found next to Install.ps1."
}

if (-not (Test-Path -LiteralPath $sourceLanguages -PathType Container)) {
    throw "The Languages folder was not found next to Install.ps1."
}

if (-not (Test-Path -LiteralPath $sourceAssets -PathType Container)) {
    throw "The Assets folder was not found next to Install.ps1."
}

$sourceMultiMonitorTool = $null
$configuredMultiMonitorToolPath = ''

if (-not [string]::IsNullOrWhiteSpace($MultiMonitorToolPath)) {
    $expandedPath = [Environment]::ExpandEnvironmentVariables($MultiMonitorToolPath)
    if (-not (Test-Path -LiteralPath $expandedPath -PathType Leaf)) {
        throw "MultiMonitorTool.exe was not found at: $expandedPath"
    }

    $configuredMultiMonitorToolPath = (Resolve-Path -LiteralPath $expandedPath).Path
}
else {
    $sourceMultiMonitorTool = Join-Path $PSScriptRoot 'MultiMonitorTool.exe'
    if (-not (Test-Path -LiteralPath $sourceMultiMonitorTool -PathType Leaf)) {
        throw @"
MultiMonitorTool.exe is required.

Download it from https://www.nirsoft.net/utils/multi_monitor_tool.html and place it next to Install.ps1, or run Install.ps1 with -MultiMonitorToolPath to use an existing copy.
"@
    }
}

New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination $InstallPath -Force
Copy-Item -LiteralPath $sourceLanguages -Destination $InstallPath -Recurse -Force
Copy-Item -LiteralPath $sourceAssets -Destination $InstallPath -Recurse -Force

if ($null -ne $sourceMultiMonitorTool) {
    Copy-Item -LiteralPath $sourceMultiMonitorTool -Destination $InstallPath -Force
}

$installedConfigurationPath = Join-Path $InstallPath 'config.json'
$existingConfiguration = $null
if (Test-Path -LiteralPath $installedConfigurationPath -PathType Leaf) {
    try {
        $existingConfiguration = Get-Content `
            -LiteralPath $installedConfigurationPath `
            -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning 'The existing config.json is invalid and will be replaced.'
    }
}

$theme = [ordered]@{
    primary       = '#2563A5'
    choice        = '#FFFFFF'
    choiceText    = '#2563A5'
    choiceHover   = '#EFF6FF'
    choicePressed = '#DBEAFE'
    accent        = '#93C5FD'
    window        = '#FFFFFF'
    information   = '#F4F7FA'
    primaryText   = '#202020'
    secondaryText = '#525252'
    headerText    = '#FFFFFF'
    controlBorder = '#BECAD5'
}

if ($null -ne $existingConfiguration.theme) {
    foreach ($key in @($theme.Keys)) {
        $property = $existingConfiguration.theme.PSObject.Properties[$key]
        if ($null -ne $property) {
            $theme[$key] = [string]$property.Value
        }
    }
}

$configuredLanguage = 'en-US'
if (-not [string]::IsNullOrWhiteSpace([string]$existingConfiguration.language)) {
    $configuredLanguage = [string]$existingConfiguration.language
}

$configuration = [ordered]@{
    multiMonitorToolPath = $configuredMultiMonitorToolPath
    language             = $configuredLanguage
    theme                = $theme
}

$configuration |
    ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath $installedConfigurationPath -Encoding UTF8

$hiddenPowerShellAvailable = Test-Path `
    -LiteralPath $recommendedPowerShellW `
    -PathType Leaf

$powerShellHost = if ($hiddenPowerShellAvailable) {
    $recommendedPowerShellW
}
else {
    $nativePowerShell
}

$installedScript = Join-Path $InstallPath 'MonitorLayoutAssistant.ps1'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powerShellHost
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $installedScript
$shortcut.WorkingDirectory = $InstallPath
$shortcut.Description = $applicationName
$shortcut.IconLocation = Join-Path $InstallPath 'Assets\MonitorLayoutAssistant.ico'
$shortcut.Save()

Write-Host "$applicationName was installed successfully." -ForegroundColor Green
Write-Host "Installation path: $InstallPath"
Write-Host "PowerShell host: $powerShellHost"

if (-not $hiddenPowerShellAvailable) {
    Write-Warning @"
powershellw.exe was not found at the recommended location. The shortcut uses the native powershell.exe, so a console window will remain visible while the application is running.

RunHiddenConsole is optional and must be assessed separately before use. If powershellw.exe is added later at:
$recommendedPowerShellW

run Install.ps1 again to recreate the shortcut with the hidden PowerShell host.
"@
}
