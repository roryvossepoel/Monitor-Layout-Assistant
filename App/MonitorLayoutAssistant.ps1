#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$MultiMonitorToolPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System.Runtime.InteropServices;

public static class MonitorLayoutAssistantTaskbar
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
}
'@

$ErrorActionPreference = 'Stop'

$script:ApplicationName = 'Monitor Layout Assistant'
$script:ApplicationVersion = '0.1.0'
$script:ApplicationUserModelId = 'MonitorLayoutAssistant.Application'
$script:TaskbarIdentityResult = [MonitorLayoutAssistantTaskbar]::SetCurrentProcessExplicitAppUserModelID(
    $script:ApplicationUserModelId
)
$script:PrimaryColor = [System.Drawing.Color]::FromArgb(36, 59, 83)
$script:ButtonColor = [System.Drawing.Color]::FromArgb(220, 236, 248)
$script:ButtonTextColor = [System.Drawing.Color]::FromArgb(23, 79, 122)
$script:ButtonHoverColor = [System.Drawing.Color]::FromArgb(201, 225, 243)
$script:ButtonPressedColor = [System.Drawing.Color]::FromArgb(181, 213, 236)
$script:ButtonBorderColor = [System.Drawing.Color]::FromArgb(220, 236, 248)
$script:ButtonBorderSize = 0
$script:ButtonArrowSize = 26
$script:InfoBorderColor = [System.Drawing.Color]::FromArgb(232, 190, 80)
$script:InfoBorderSize = 0
$script:WindowColor = [System.Drawing.Color]::White
$script:InfoColor = [System.Drawing.Color]::FromArgb(247, 247, 247)
$script:PrimaryTextColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$script:SecondaryTextColor = [System.Drawing.Color]::FromArgb(82, 82, 82)
$script:HeaderTextColor = [System.Drawing.Color]::White
$script:ControlBorderColor = [System.Drawing.Color]::FromArgb(190, 202, 213)
$script:ConfigurationPath = Join-Path $PSScriptRoot 'config.json'
$script:LanguageFolderPath = Join-Path $PSScriptRoot 'Languages'
$script:IconPath = Join-Path $PSScriptRoot 'Assets\MonitorLayoutAssistant.ico'
$script:LogRoot = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $env:TEMP
}
else {
    $env:LOCALAPPDATA
}
$script:LogDirectory = Join-Path $script:LogRoot 'Monitor Layout Assistant\Logs'
$script:LogPath = Join-Path $script:LogDirectory 'MonitorLayoutAssistant.log'
$script:LoggingAvailable = $false
$script:MonitorListPath = Join-Path $env:TEMP (
    'MonitorLayoutAssistant-{0}.csv' -f [guid]::NewGuid().ToString('N')
)

function Import-ApplicationConfiguration {
    if (-not (Test-Path -LiteralPath $script:ConfigurationPath -PathType Leaf)) {
        return [PSCustomObject]@{
            multiMonitorToolPath = ''
            language             = ''
        }
    }

    try {
        return Get-Content -LiteralPath $script:ConfigurationPath -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "The configuration file is invalid: $script:ConfigurationPath"
    }
}

function Initialize-Localization {
    param([Parameter(Mandatory)][object]$Configuration)

    $languageToResolve = [string]$Configuration.language
    if ([string]::IsNullOrWhiteSpace($languageToResolve)) {
        $languageToResolve = 'en-US'
    }

    $fallbackPath = Join-Path $script:LanguageFolderPath 'en-US.json'
    if (-not (Test-Path -LiteralPath $fallbackPath -PathType Leaf)) {
        throw "The English language file could not be found: $fallbackPath"
    }

    try {
        $fallbackLanguage = Get-Content -LiteralPath $fallbackPath -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "The English language file is invalid: $fallbackPath"
    }

    $languagePath = Join-Path $script:LanguageFolderPath (
        '{0}.json' -f $languageToResolve
    )

    if (Test-Path -LiteralPath $languagePath -PathType Leaf) {
        try {
            $selectedLanguage = Get-Content -LiteralPath $languagePath -Raw |
                ConvertFrom-Json
        }
        catch {
            $selectedLanguage = $fallbackLanguage
        }
    }
    else {
        $selectedLanguage = $fallbackLanguage
    }

    $script:Text = $selectedLanguage.strings
    $script:FallbackText = $fallbackLanguage.strings
    $script:SelectedLanguage = [string]$selectedLanguage.language
}

function Get-LocalizedText {
    param(
        [Parameter(Mandatory)][string]$Key,
        [object[]]$ArgumentList
    )

    $property = $script:Text.PSObject.Properties[$Key]
    if ($null -eq $property) {
        $property = $script:FallbackText.PSObject.Properties[$Key]
    }
    if ($null -eq $property) {
        throw "Missing localization key: $Key"
    }

    $value = [string]$property.Value
    if ($null -ne $ArgumentList -and $ArgumentList.Count -gt 0) {
        return ($value -f $ArgumentList)
    }

    return $value
}

function Initialize-ApplicationTheme {
    param([Parameter(Mandatory)][object]$Configuration)

    if ($null -eq $Configuration.theme) {
        return
    }

    $colorMappings = [ordered]@{
        'primary'                = 'PrimaryColor'
        'window'                 = 'WindowColor'
        'headerText'             = 'HeaderTextColor'
        'text.primary'           = 'PrimaryTextColor'
        'text.secondary'         = 'SecondaryTextColor'
        'choice.background'      = 'ButtonColor'
        'choice.foreground'      = 'ButtonTextColor'
        'choice.hover'           = 'ButtonHoverColor'
        'choice.pressed'         = 'ButtonPressedColor'
        'choice.border'          = 'ButtonBorderColor'
        'information.background' = 'InfoColor'
        'information.border'     = 'InfoBorderColor'
        'controls.border'        = 'ControlBorderColor'
    }

    foreach ($entry in $colorMappings.GetEnumerator()) {
        $setting = $Configuration.theme
        foreach ($segment in $entry.Key.Split('.')) {
            if ($null -eq $setting) {
                break
            }
            $property = $setting.PSObject.Properties[$segment]
            $setting = if ($null -eq $property) { $null } else { $property.Value }
        }

        if ($null -eq $setting -or [string]::IsNullOrWhiteSpace([string]$setting)) {
            continue
        }

        $value = [string]$setting
        if ($value -notmatch '^#[0-9A-Fa-f]{6}$') {
            Write-ApplicationLog (
                'Invalid theme color ignored. Setting={0} Value={1}' -f
                $entry.Key,
                $value
            ) -Level WARN
            continue
        }

        Set-Variable `
            -Name $entry.Value `
            -Value ([System.Drawing.ColorTranslator]::FromHtml($value)) `
            -Scope Script
    }

    $borderSize = $Configuration.theme.choice.borderSize
    if ($null -ne $borderSize) {
        $parsedBorderSize = 0
        if ([int]::TryParse([string]$borderSize, [ref]$parsedBorderSize) -and
            $parsedBorderSize -ge 0 -and $parsedBorderSize -le 5) {
            $script:ButtonBorderSize = $parsedBorderSize
        }
        else {
            Write-ApplicationLog (
                'Invalid theme setting ignored. Setting=choice.borderSize Value={0}' -f
                $borderSize
            ) -Level WARN
        }
    }

    $arrowSize = $Configuration.theme.choice.arrowSize
    if ($null -ne $arrowSize) {
        $parsedArrowSize = 0
        if ([int]::TryParse([string]$arrowSize, [ref]$parsedArrowSize) -and
            $parsedArrowSize -ge 16 -and $parsedArrowSize -le 40) {
            $script:ButtonArrowSize = $parsedArrowSize
        }
        else {
            Write-ApplicationLog (
                'Invalid theme setting ignored. Setting=choice.arrowSize Value={0}' -f
                $arrowSize
            ) -Level WARN
        }
    }

    $informationBorderSize = $Configuration.theme.information.borderSize
    if ($null -ne $informationBorderSize) {
        $parsedInformationBorderSize = 0
        if ([int]::TryParse(
                [string]$informationBorderSize,
                [ref]$parsedInformationBorderSize
            ) -and $parsedInformationBorderSize -ge 0 -and
            $parsedInformationBorderSize -le 5) {
            $script:InfoBorderSize = $parsedInformationBorderSize
        }
        else {
            Write-ApplicationLog (
                'Invalid theme setting ignored. Setting=information.borderSize Value={0}' -f
                $informationBorderSize
            ) -Level WARN
        }
    }

}

function Initialize-ApplicationLogging {
    try {
        New-Item -ItemType Directory -Path $script:LogDirectory -Force |
            Out-Null

        if (Test-Path -LiteralPath $script:LogPath -PathType Leaf) {
            $logFile = Get-Item -LiteralPath $script:LogPath
            if ($logFile.Length -ge 2MB) {
                $archivePath = "$script:LogPath.1"
                Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $script:LogPath -Destination $archivePath -Force
            }
        }

        $script:LoggingAvailable = $true
    }
    catch {
        $script:LoggingAvailable = $false
        Write-Warning "File logging could not be initialized: $($_.Exception.Message)"
    }
}

function Write-ApplicationLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $normalizedMessage = $Message -replace '[\r\n]+', ' '
    $logLine = '{0} [{1}] {2}' -f
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),
        $Level,
        $normalizedMessage

    $foregroundColor = switch ($Level) {
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Gray' }
    }

    Write-Host $logLine -ForegroundColor $foregroundColor

    if ($script:LoggingAvailable) {
        try {
            Add-Content -LiteralPath $script:LogPath -Value $logLine -Encoding UTF8
        }
        catch {
            $script:LoggingAvailable = $false
            Write-Warning "File logging was disabled: $($_.Exception.Message)"
        }
    }
}

function Show-ApplicationMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = $script:ApplicationName,
        [System.Windows.Forms.MessageBoxIcon]$Icon =
            [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    )
}

function Resolve-MultiMonitorToolPath {
    param(
        [string]$ExplicitPath,
        [Parameter(Mandatory)][object]$Configuration
    )

    $candidates = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates.Add([Environment]::ExpandEnvironmentVariables($ExplicitPath))
    }

    if (-not [string]::IsNullOrWhiteSpace(
            [string]$Configuration.multiMonitorToolPath
        )) {
        $candidates.Add(
            [Environment]::ExpandEnvironmentVariables(
                [string]$Configuration.multiMonitorToolPath
            )
        )
    }

    $candidates.Add((Join-Path $PSScriptRoot 'MultiMonitorTool.exe'))

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw (Get-LocalizedText -Key 'multiMonitorToolMissing')
}

function Export-MonitorData {
    param(
        [Parameter(Mandatory)][string]$ToolPath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
    & $ToolPath /scomma $OutputPath | Out-Null
    Start-Sleep -Milliseconds 750

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw (Get-LocalizedText -Key 'monitorInformationUnavailable')
    }

    return @(Import-Csv -LiteralPath $OutputPath)
}

function Test-ExternalMonitorConnected {
    param([Parameter(Mandatory)][string]$ToolPath)

    $preCheckPath = Join-Path $env:TEMP (
        'MonitorLayoutAssistant-PreCheck-{0}.csv' -f
        [guid]::NewGuid().ToString('N')
    )

    try {
        $monitorData = Export-MonitorData `
            -ToolPath $ToolPath `
            -OutputPath $preCheckPath

        # MultiMonitorTool reads this value from EDID. In the supported setup,
        # the built-in laptop display has no Monitor Name and external displays do.
        $externalMonitors = @(
            $monitorData | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.'Monitor Name')
            }
        )

        return ($externalMonitors.Count -gt 0)
    }
    finally {
        Remove-Item -LiteralPath $preCheckPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-FormDefaults {
    param([Parameter(Mandatory)][System.Windows.Forms.Form]$Form)

    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false
    $Form.ShowIcon = $true
    if (Test-Path -LiteralPath $script:IconPath -PathType Leaf) {
        try {
            $Form.Icon = New-Object System.Drawing.Icon($script:IconPath)
        }
        catch {
            $Form.Icon = [System.Drawing.SystemIcons]::Application
        }
    }
    else {
        $Form.Icon = [System.Drawing.SystemIcons]::Application
    }
    $Form.TopMost = $true
    $Form.BackColor = $script:WindowColor
    $Form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
}

function New-HeaderPanel {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][int]$Width,
        [int]$Height = 80
    )

    $header = New-Object System.Windows.Forms.Panel
    $header.Size = New-Object System.Drawing.Size($Width, $Height)
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.BackColor = $script:PrimaryColor

    $label = New-Object System.Windows.Forms.Label
    $label.Name = 'HeaderTitle'
    $label.Text = $Title
    $label.Size = New-Object System.Drawing.Size(($Width - 60), 44)
    $label.Location = New-Object System.Drawing.Point(30, 18)
    $label.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        17,
        [System.Drawing.FontStyle]::Bold
    )
    $label.ForeColor = $script:HeaderTextColor
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $header.Controls.Add($label)

    $Form.Controls.Add($header)
    return $header
}

function New-ChoiceCard {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][ValidateSet('left', 'right')][string]$Value
    )

    $card = New-Object System.Windows.Forms.Button
    $card.Size = New-Object System.Drawing.Size(292, 132)
    $card.Text = ''
    $card.BackColor = $script:ButtonColor
    $card.ForeColor = $script:ButtonTextColor
    $card.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $card.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $card.FlatAppearance.BorderColor = $script:ButtonBorderColor
    $card.FlatAppearance.BorderSize = $script:ButtonBorderSize
    $card.FlatAppearance.MouseOverBackColor = $script:ButtonHoverColor
    $card.FlatAppearance.MouseDownBackColor = $script:ButtonPressedColor
    $card.UseVisualStyleBackColor = $false
    $card.Cursor = [System.Windows.Forms.Cursors]::Hand
    $card.Tag = $Value
    $card | Add-Member -NotePropertyName ChoiceTitle -NotePropertyValue $Title
    $card | Add-Member -NotePropertyName ChoiceValue -NotePropertyValue $Value
    $card.Add_Paint({
        param($sender, $eventArgs)

        $arrowPen = New-Object System.Drawing.Pen($sender.ForeColor, 2)
        try {
            $eventArgs.Graphics.SmoothingMode =
                [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $arrowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $arrowPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

            $centerX = if ($sender.ChoiceValue -eq 'left') { 61 } else { 231 }
            $centerY = [int][math]::Floor($sender.Height / 2)
            $halfLength = [int][math]::Floor($script:ButtonArrowSize / 2)
            $headSize = [int][math]::Max(6, [math]::Floor($script:ButtonArrowSize / 4))
            $startX = $centerX - $halfLength
            $endX = $centerX + $halfLength

            $eventArgs.Graphics.DrawLine($arrowPen, $startX, $centerY, $endX, $centerY)
            if ($sender.ChoiceValue -eq 'left') {
                $eventArgs.Graphics.DrawLine(
                    $arrowPen,
                    $startX,
                    $centerY,
                    ($startX + $headSize),
                    ($centerY - $headSize)
                )
                $eventArgs.Graphics.DrawLine(
                    $arrowPen,
                    $startX,
                    $centerY,
                    ($startX + $headSize),
                    ($centerY + $headSize)
                )
            }
            else {
                $eventArgs.Graphics.DrawLine(
                    $arrowPen,
                    $endX,
                    $centerY,
                    ($endX - $headSize),
                    ($centerY - $headSize)
                )
                $eventArgs.Graphics.DrawLine(
                    $arrowPen,
                    $endX,
                    $centerY,
                    ($endX - $headSize),
                    ($centerY + $headSize)
                )
            }
        }
        finally {
            $arrowPen.Dispose()
        }

        $textBounds = if ($sender.ChoiceValue -eq 'left') {
            New-Object System.Drawing.Rectangle(96, 0, 180, $sender.Height)
        }
        else {
            New-Object System.Drawing.Rectangle(16, 0, 180, $sender.Height)
        }
        $horizontalAlignment = if ($sender.ChoiceValue -eq 'left') {
            [System.Windows.Forms.TextFormatFlags]::Left
        }
        else {
            [System.Windows.Forms.TextFormatFlags]::Right
        }
        [System.Windows.Forms.TextRenderer]::DrawText(
            $eventArgs.Graphics,
            [string]$sender.ChoiceTitle,
            $sender.Font,
            $textBounds,
            $sender.ForeColor,
            ($horizontalAlignment -bor
                [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                [System.Windows.Forms.TextFormatFlags]::SingleLine -bor
                [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
                [System.Windows.Forms.TextFormatFlags]::NoPrefix)
        )
    })
    $card.Add_Click({
        param($sender, $eventArgs)
        $form = $sender.FindForm()
        $form.Tag = [string]$sender.Tag
        $form.Close()
    })

    return $card
}

function Show-MonitorPositionDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $script:ApplicationName
    $form.ClientSize = New-Object System.Drawing.Size(760, 512)
    $form.Tag = $null
    Set-FormDefaults -Form $form
    [void](New-HeaderPanel -Form $form -Title $script:ApplicationName -Width 760)

    $question = New-Object System.Windows.Forms.Label
    $question.Text = Get-LocalizedText -Key 'positionQuestion'
    $question.Size = New-Object System.Drawing.Size(680, 34)
    $question.Location = New-Object System.Drawing.Point(40, 122)
    $question.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
    $question.ForeColor = $script:PrimaryTextColor
    $question.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($question)

    $leftCard = New-ChoiceCard -Title (Get-LocalizedText -Key 'laptopOnLeft') -Value 'left'
    $leftCard.Location = New-Object System.Drawing.Point(64, 184)
    $form.Controls.Add($leftCard)

    $rightCard = New-ChoiceCard -Title (Get-LocalizedText -Key 'laptopOnRight') -Value 'right'
    $rightCard.Location = New-Object System.Drawing.Point(404, 184)
    $form.Controls.Add($rightCard)

    $infoPanel = New-Object System.Windows.Forms.Panel
    $infoPanel.Size = New-Object System.Drawing.Size(632, 110)
    $infoPanel.Location = New-Object System.Drawing.Point(64, 344)
    $infoPanel.BackColor = $script:InfoColor

    $infoPanel.Add_Paint({
        param($sender, $eventArgs)
        if ($script:InfoBorderSize -le 0) {
            return
        }

        $pen = New-Object System.Drawing.Pen(
            $script:InfoBorderColor,
            $script:InfoBorderSize
        )
        try {
            $inset = [int][math]::Floor($script:InfoBorderSize / 2)
            $eventArgs.Graphics.DrawRectangle(
                $pen,
                $inset,
                $inset,
                ($sender.Width - $script:InfoBorderSize),
                ($sender.Height - $script:InfoBorderSize)
            )
        }
        finally {
            $pen.Dispose()
        }
    })

    $infoTitle = New-Object System.Windows.Forms.Label
    $infoTitle.Text = Get-LocalizedText -Key 'beforeContinue'
    $infoTitle.Size = New-Object System.Drawing.Size(575, 23)
    $infoTitle.Location = New-Object System.Drawing.Point(24, 13)
    $infoTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
    $infoTitle.ForeColor = $script:PrimaryTextColor

    $infoText = New-Object System.Windows.Forms.Label
    $infoText.Text = Get-LocalizedText -Key 'physicalOrderInformation'
    $infoText.Size = New-Object System.Drawing.Size(575, 58)
    $infoText.Location = New-Object System.Drawing.Point(24, 43)
    $infoText.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $infoText.ForeColor = $script:SecondaryTextColor

    $infoPanel.Controls.AddRange(@($infoTitle, $infoText))
    $form.Controls.Add($infoPanel)

    [void]$form.ShowDialog()
    return $form.Tag
}

function Show-ProgressDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $script:ApplicationName
    $form.ClientSize = New-Object System.Drawing.Size(560, 260)
    $form.ControlBox = $false
    Set-FormDefaults -Form $form
    [void](New-HeaderPanel -Form $form -Title (Get-LocalizedText -Key 'applyingLayout') -Width 560 -Height 84)

    $statusTitle = New-Object System.Windows.Forms.Label
    $statusTitle.Name = 'StatusTitle'
    $statusTitle.Text = Get-LocalizedText -Key 'pleaseWait'
    $statusTitle.Size = New-Object System.Drawing.Size(480, 30)
    $statusTitle.Location = New-Object System.Drawing.Point(40, 112)
    $statusTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $statusTitle.ForeColor = $script:PrimaryTextColor
    $statusTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $statusText = New-Object System.Windows.Forms.Label
    $statusText.Name = 'StatusText'
    $statusText.Text = Get-LocalizedText -Key 'preparingDisplays'
    $statusText.Size = New-Object System.Drawing.Size(480, 28)
    $statusText.Location = New-Object System.Drawing.Point(40, 148)
    $statusText.ForeColor = $script:SecondaryTextColor
    $statusText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Name = 'ProgressBar'
    $progress.Size = New-Object System.Drawing.Size(440, 10)
    $progress.Location = New-Object System.Drawing.Point(60, 200)
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $progress.MarqueeAnimationSpeed = 28

    $form.Controls.AddRange(@($statusTitle, $statusText, $progress))
    $form.Show()
    $form.Activate()
    [System.Windows.Forms.Application]::DoEvents()
    return $form
}

function Update-ProgressStatus {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory)][string]$Text
    )

    $Form.Controls['StatusText'].Text = $Text
    $Form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-ProgressCompleted {
    param([Parameter(Mandatory)][System.Windows.Forms.Form]$Form)

    $headerTitle = $Form.Controls |
        ForEach-Object { $_.Controls['HeaderTitle'] } |
        Where-Object { $null -ne $_ } |
        Select-Object -First 1

    $headerTitle.Text = Get-LocalizedText -Key 'layoutApplied'
    $Form.Controls['StatusTitle'].Text = [char]0x2714
    $Form.Controls['StatusTitle'].Font = New-Object System.Drawing.Font(
        'Segoe UI Symbol', 24
    )
    $Form.Controls['StatusTitle'].ForeColor = $script:PrimaryColor
    $Form.Controls['StatusText'].Text = Get-LocalizedText -Key 'configurationSuccessful'
    $Form.Controls['ProgressBar'].Visible = $false

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = Get-LocalizedText -Key 'done'
    $closeButton.Size = New-Object System.Drawing.Size(120, 34)
    $closeButton.Location = New-Object System.Drawing.Point(220, 198)
    $closeButton.BackColor = $script:ButtonColor
    $closeButton.ForeColor = $script:SecondaryTextColor
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderColor = $script:ControlBorderColor
    $closeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeButton.Add_Click({ $Form.Close() })
    $Form.Controls.Add($closeButton)

    $Form.ControlBox = $true
    $Form.Refresh()
    $Form.Activate()

    while ($Form.Visible -and -not $Form.IsDisposed) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }

    if (-not $Form.IsDisposed) {
        $Form.Dispose()
    }
}

function Close-ProgressDialog {
    param([System.Windows.Forms.Form]$Form)

    if ($null -ne $Form -and -not $Form.IsDisposed) {
        $Form.Close()
        $Form.Dispose()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function ConvertTo-MonitorObjects {
    param([Parameter(Mandatory)][array]$RawMonitors)

    $result = foreach ($monitor in $RawMonitors) {
        if ([string]$monitor.Name -notmatch '^\\\\\.\\DISPLAY(\d+)$') {
            continue
        }

        $monitorName = [string]$monitor.'Monitor Name'
        $monitorSerial = [string]$monitor.'Monitor Serial Number'
        $isLaptop = [string]::IsNullOrWhiteSpace($monitorName)

        $displayName = if ($isLaptop) {
            Get-LocalizedText -Key 'builtInDisplay'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($monitorSerial)) {
            '{0} ({1})' -f $monitorName, $monitorSerial
        }
        else {
            $monitorName
        }

        $item = [PSCustomObject]@{
            Name          = [string]$monitor.Name
            DisplayName   = $displayName
            Resolution    = [string]$monitor.Resolution
            MaxResolution = [string]$monitor.'Maximum Resolution'
            DisplayNumber = [int]$Matches[1]
            Width         = 0
            MaxWidth      = 0
            IsLaptop      = $isLaptop
        }

        if ($item.Resolution -match '(\d+)\s*[Xx]\s*(\d+)') {
            $item.Width = [int]$Matches[1]
        }

        if ($item.MaxResolution -match '(\d+)\s*[Xx]\s*(\d+)') {
            $item.MaxWidth = [int]$Matches[1]
        }

        $item
    }

    return @($result)
}

$progressForm = $null
Initialize-ApplicationLogging

try {
    $configuration = Import-ApplicationConfiguration
    Initialize-Localization -Configuration $configuration
    Initialize-ApplicationTheme -Configuration $configuration

    Write-ApplicationLog (
        'Application started. Version={0} Computer={1} User={2} ProcessId={3}' -f
        $script:ApplicationVersion,
        $env:COMPUTERNAME,
        $env:USERNAME,
        $PID
    )
    Write-ApplicationLog "LogPath=$script:LogPath"
    Write-ApplicationLog (
        'Taskbar identity initialized. AppUserModelId={0} Result={1}' -f
        $script:ApplicationUserModelId,
        $script:TaskbarIdentityResult
    )
    Write-ApplicationLog "Language selected. Language=$script:SelectedLanguage"
    $toolPath = Resolve-MultiMonitorToolPath -ExplicitPath $MultiMonitorToolPath -Configuration $configuration
    Write-ApplicationLog "MultiMonitorTool found. Path=$toolPath"

    if (-not (Test-ExternalMonitorConnected -ToolPath $toolPath)) {
        Write-ApplicationLog 'No external monitors were detected. Application exiting.' -Level WARN
        Show-ApplicationMessage `
            -Title (Get-LocalizedText -Key 'noExternalTitle') `
            -Message (Get-LocalizedText -Key 'noExternalMessage')
        exit 0
    }

    $shell = New-Object -ComObject Shell.Application
    $shell.MinimizeAll()

    $side = Show-MonitorPositionDialog
    if ([string]::IsNullOrWhiteSpace($side)) {
        Write-ApplicationLog 'No laptop position was selected. Application cancelled by user.' -Level WARN
        exit 0
    }

    Write-ApplicationLog "Laptop position selected. Position=$side"
    $progressForm = Show-ProgressDialog
    Update-ProgressStatus -Form $progressForm -Text (Get-LocalizedText -Key 'switchingToExtended')

    & "$env:WINDIR\System32\DisplaySwitch.exe" /extend
    Start-Sleep -Seconds 3

    Update-ProgressStatus -Form $progressForm -Text (Get-LocalizedText -Key 'detectingMonitors')
    $rawMonitors = Export-MonitorData `
        -ToolPath $toolPath `
        -OutputPath $script:MonitorListPath

    $monitors = ConvertTo-MonitorObjects -RawMonitors $rawMonitors
    if ($monitors.Count -eq 0) {
        throw (Get-LocalizedText -Key 'noActiveMonitors')
    }

    $laptopMonitor = $monitors |
        Where-Object IsLaptop |
        Select-Object -First 1

    $externalMonitors = @(
        $monitors |
            Where-Object { -not $_.IsLaptop } |
            Sort-Object DisplayNumber
    )

    if ($externalMonitors.Count -eq 0) {
        throw (Get-LocalizedText -Key 'noExternalMonitors')
    }

    Write-ApplicationLog (
        'Displays detected. Total={0} External={1} BuiltIn={2}' -f
        $monitors.Count,
        $externalMonitors.Count,
        [int]($null -ne $laptopMonitor)
    )

    if ($side -eq 'left') {
        $sortedMonitors = @($laptopMonitor) + $externalMonitors
    }
    else {
        $sortedMonitors = $externalMonitors + @($laptopMonitor)
    }

    $sortedMonitors = @($sortedMonitors | Where-Object { $null -ne $_ })

    for ($index = 0; $index -lt $sortedMonitors.Count; $index++) {
        $monitor = $sortedMonitors[$index]
        Write-ApplicationLog (
            'Display order. Index={0} Name={1} DisplayName={2} CurrentResolution={3} MaximumResolution={4} BuiltIn={5}' -f
            $index,
            $monitor.Name,
            $monitor.DisplayName,
            $monitor.Resolution,
            $monitor.MaxResolution,
            $monitor.IsLaptop
        )
    }

    Update-ProgressStatus -Form $progressForm -Text (Get-LocalizedText -Key 'applyingResolutions')
    foreach ($monitor in $sortedMonitors) {
        Write-ApplicationLog "Applying maximum resolution. Display=$($monitor.Name)"
        & $toolPath /SetMax $monitor.Name
    }

    Start-Sleep -Seconds 2
    $monitorArguments = @('/SetMonitors')
    $positionX = 0

    foreach ($monitor in $sortedMonitors) {
        $monitorArguments += 'Name={0} PositionX={1} PositionY=0' -f
            $monitor.Name, $positionX

        if ($monitor.MaxWidth -gt 0) {
            $positionX += $monitor.MaxWidth
        }
        elseif ($monitor.Width -gt 0) {
            $positionX += $monitor.Width
        }
        else {
            $positionX += 1920
        }
    }

    Update-ProgressStatus -Form $progressForm -Text (Get-LocalizedText -Key 'arrangingMonitors')
    Write-ApplicationLog "Applying display positions. DisplayCount=$($sortedMonitors.Count)"
    & $toolPath @monitorArguments
    Start-Sleep -Seconds 3

    # Select the center external monitor. With an even number, select the
    # left monitor of the two center displays.
    $primaryIndex = [math]::Floor(($externalMonitors.Count - 1) / 2)
    $primaryMonitor = $externalMonitors[$primaryIndex]

    Update-ProgressStatus -Form $progressForm -Text (Get-LocalizedText -Key 'settingPrimary')
    Write-ApplicationLog (
        'Setting primary display. Name={0} DisplayName={1}' -f
        $primaryMonitor.Name,
        $primaryMonitor.DisplayName
    )
    & $toolPath /SetPrimary $primaryMonitor.Name
    & "$env:WINDIR\System32\DisplaySwitch.exe" /extend
    Start-Sleep -Seconds 2

    Write-ApplicationLog 'Configuration completed successfully.'
    Show-ProgressCompleted -Form $progressForm
    $progressForm = $null
}
catch {
    Close-ProgressDialog -Form $progressForm
    $progressForm = $null
    Write-ApplicationLog (
        'Configuration failed. Message={0} Category={1} Stack={2}' -f
        $_.Exception.Message,
        $_.CategoryInfo.Category,
        $_.ScriptStackTrace
    ) -Level ERROR

    $errorTitle = if ($null -ne $script:Text) {
        Get-LocalizedText -Key 'configurationFailed'
    }
    else {
        'Monitor configuration failed'
    }

    Show-ApplicationMessage `
        -Title $errorTitle `
        -Message $_.Exception.Message `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)

    exit 1
}
finally {
    Remove-Item `
        -LiteralPath $script:MonitorListPath `
        -Force `
        -ErrorAction SilentlyContinue
}
