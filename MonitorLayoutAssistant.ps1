#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$MultiMonitorToolPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$script:ApplicationName = 'Monitor Layout Assistant'
$script:PrimaryColor = [System.Drawing.Color]::FromArgb(36, 59, 83)
$script:ButtonColor = [System.Drawing.Color]::FromArgb(44, 82, 130)
$script:ButtonHoverColor = [System.Drawing.Color]::FromArgb(54, 101, 160)
$script:ButtonPressedColor = [System.Drawing.Color]::FromArgb(29, 61, 99)
$script:AccentColor = [System.Drawing.Color]::FromArgb(111, 168, 220)
$script:ConfigurationPath = Join-Path $PSScriptRoot 'config.json'
$script:MonitorListPath = Join-Path $env:TEMP (
    'MonitorLayoutAssistant-{0}.csv' -f [guid]::NewGuid().ToString('N')
)

function Write-ApplicationLog {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message)
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
    param([string]$ExplicitPath)

    $candidates = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates.Add([Environment]::ExpandEnvironmentVariables($ExplicitPath))
    }

    if (Test-Path -LiteralPath $script:ConfigurationPath) {
        try {
            $configuration = Get-Content -LiteralPath $script:ConfigurationPath -Raw |
                ConvertFrom-Json

            if (-not [string]::IsNullOrWhiteSpace(
                    [string]$configuration.multiMonitorToolPath
                )) {
                $candidates.Add(
                    [Environment]::ExpandEnvironmentVariables(
                        [string]$configuration.multiMonitorToolPath
                    )
                )
            }
        }
        catch {
            throw "The configuration file is invalid: $script:ConfigurationPath"
        }
    }

    $candidates.Add((Join-Path $PSScriptRoot 'MultiMonitorTool.exe'))

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @"
MultiMonitorTool.exe is required but could not be found.

Download it from the official NirSoft website and place it next to MonitorLayoutAssistant.ps1, or specify its location in config.json.
"@
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
        throw 'Connected display information could not be retrieved.'
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
    $Form.Icon = [System.Drawing.SystemIcons]::Application
    $Form.TopMost = $true
    $Form.BackColor = [System.Drawing.Color]::White
    $Form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
}

function New-HeaderPanel {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][int]$Width,
        [int]$Height = 92
    )

    $header = New-Object System.Windows.Forms.Panel
    $header.Size = New-Object System.Drawing.Size($Width, $Height)
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.BackColor = $script:PrimaryColor

    $label = New-Object System.Windows.Forms.Label
    $label.Name = 'HeaderTitle'
    $label.Text = $Title
    $label.Size = New-Object System.Drawing.Size(($Width - 60), 44)
    $label.Location = New-Object System.Drawing.Point(30, 23)
    $label.Font = New-Object System.Drawing.Font(
        'Segoe UI Semibold',
        19,
        [System.Drawing.FontStyle]::Bold
    )
    $label.ForeColor = [System.Drawing.Color]::White
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

    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(292, 132)
    $card.BackColor = $script:ButtonColor
    $card.Cursor = [System.Windows.Forms.Cursors]::Hand
    $card.Tag = $Value

    $arrow = New-Object System.Windows.Forms.Label
    $arrow.Text = if ($Value -eq 'left') { [char]0x2190 } else { [char]0x2192 }
    $arrow.Size = New-Object System.Drawing.Size(82, 132)
    $arrow.Location = New-Object System.Drawing.Point(0, 0)
    $arrow.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 30)
    $arrow.ForeColor = [System.Drawing.Color]::White
    $arrow.BackColor = [System.Drawing.Color]::Transparent
    $arrow.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $separator = New-Object System.Windows.Forms.Panel
    $separator.Size = New-Object System.Drawing.Size(1, 84)
    $separator.Location = New-Object System.Drawing.Point(92, 24)
    $separator.BackColor = $script:AccentColor

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.Size = New-Object System.Drawing.Size(178, 132)
    $titleLabel.Location = New-Object System.Drawing.Point(108, 0)
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $card.Controls.AddRange(@($arrow, $separator, $titleLabel))

    foreach ($control in @($card, $arrow, $separator, $titleLabel)) {
        $control.Cursor = [System.Windows.Forms.Cursors]::Hand
        $control | Add-Member -NotePropertyName ChoiceCard -NotePropertyValue $card -Force

        $control.Add_MouseEnter({
            param($sender, $eventArgs)
            $sender.ChoiceCard.BackColor = $script:ButtonHoverColor
        })

        $control.Add_MouseLeave({
            param($sender, $eventArgs)
            $target = $sender.ChoiceCard
            $position = $target.PointToClient([System.Windows.Forms.Cursor]::Position)
            if (-not $target.ClientRectangle.Contains($position)) {
                $target.BackColor = $script:ButtonColor
            }
        })

        $control.Add_MouseDown({
            param($sender, $eventArgs)
            $sender.ChoiceCard.BackColor = $script:ButtonPressedColor
        })

        $control.Add_MouseUp({
            param($sender, $eventArgs)
            $sender.ChoiceCard.BackColor = $script:ButtonHoverColor
        })

        $control.Add_Click({
            param($sender, $eventArgs)
            $target = $sender.ChoiceCard
            $form = $target.FindForm()
            $form.Tag = [string]$target.Tag
            $form.Close()
        })
    }

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
    $question.Text = 'Where is the laptop positioned relative to the external monitors?'
    $question.Size = New-Object System.Drawing.Size(680, 34)
    $question.Location = New-Object System.Drawing.Point(40, 122)
    $question.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
    $question.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $question.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $form.Controls.Add($question)

    $leftCard = New-ChoiceCard -Title 'Laptop on the left' -Value 'left'
    $leftCard.Location = New-Object System.Drawing.Point(64, 184)
    $form.Controls.Add($leftCard)

    $rightCard = New-ChoiceCard -Title 'Laptop on the right' -Value 'right'
    $rightCard.Location = New-Object System.Drawing.Point(404, 184)
    $form.Controls.Add($rightCard)

    $infoPanel = New-Object System.Windows.Forms.Panel
    $infoPanel.Size = New-Object System.Drawing.Size(632, 132)
    $infoPanel.Location = New-Object System.Drawing.Point(64, 344)
    $infoPanel.BackColor = [System.Drawing.Color]::FromArgb(244, 247, 250)

    $accentBar = New-Object System.Windows.Forms.Panel
    $accentBar.Size = New-Object System.Drawing.Size(5, 132)
    $accentBar.Location = New-Object System.Drawing.Point(0, 0)
    $accentBar.BackColor = $script:PrimaryColor

    $infoTitle = New-Object System.Windows.Forms.Label
    $infoTitle.Text = 'Before you continue'
    $infoTitle.Size = New-Object System.Drawing.Size(575, 23)
    $infoTitle.Location = New-Object System.Drawing.Point(24, 13)
    $infoTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
    $infoTitle.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)

    $infoText = New-Object System.Windows.Forms.Label
    $infoText.Text = 'External monitors are arranged in the order reported by Windows. Ensure this order matches their physical left-to-right position. Docking station port labels do not necessarily match Windows display numbers.'
    $infoText.Size = New-Object System.Drawing.Size(575, 78)
    $infoText.Location = New-Object System.Drawing.Point(24, 43)
    $infoText.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $infoText.ForeColor = [System.Drawing.Color]::FromArgb(82, 82, 82)

    $infoPanel.Controls.AddRange(@($accentBar, $infoTitle, $infoText))
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
    [void](New-HeaderPanel -Form $form -Title 'Applying monitor layout' -Width 560 -Height 84)

    $statusTitle = New-Object System.Windows.Forms.Label
    $statusTitle.Name = 'StatusTitle'
    $statusTitle.Text = 'Please wait...'
    $statusTitle.Size = New-Object System.Drawing.Size(480, 30)
    $statusTitle.Location = New-Object System.Drawing.Point(40, 112)
    $statusTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
    $statusTitle.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $statusTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    $statusText = New-Object System.Windows.Forms.Label
    $statusText.Name = 'StatusText'
    $statusText.Text = 'Preparing the connected displays.'
    $statusText.Size = New-Object System.Drawing.Size(480, 28)
    $statusText.Location = New-Object System.Drawing.Point(40, 148)
    $statusText.ForeColor = [System.Drawing.Color]::FromArgb(82, 82, 82)
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

    $headerTitle.Text = 'Monitor layout applied'
    $Form.Controls['StatusTitle'].Text = [char]0x2714
    $Form.Controls['StatusTitle'].Font = New-Object System.Drawing.Font(
        'Segoe UI Symbol', 24
    )
    $Form.Controls['StatusTitle'].ForeColor = $script:PrimaryColor
    $Form.Controls['StatusText'].Text = 'The monitors were configured successfully.'
    $Form.Controls['ProgressBar'].Visible = $false

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = 'Done'
    $closeButton.Size = New-Object System.Drawing.Size(120, 34)
    $closeButton.Location = New-Object System.Drawing.Point(220, 198)
    $closeButton.BackColor = [System.Drawing.Color]::White
    $closeButton.ForeColor = [System.Drawing.Color]::FromArgb(72, 72, 72)
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderColor =
        [System.Drawing.Color]::FromArgb(190, 202, 213)
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
            'Built-in laptop display'
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

try {
    Write-ApplicationLog 'Starting Monitor Layout Assistant.'
    $toolPath = Resolve-MultiMonitorToolPath -ExplicitPath $MultiMonitorToolPath
    Write-ApplicationLog "Using MultiMonitorTool: $toolPath"

    if (-not (Test-ExternalMonitorConnected -ToolPath $toolPath)) {
        Show-ApplicationMessage `
            -Title 'No external monitors found' `
            -Message 'Connect at least one external monitor and start Monitor Layout Assistant again.'
        exit 0
    }

    $shell = New-Object -ComObject Shell.Application
    $shell.MinimizeAll()

    $side = Show-MonitorPositionDialog
    if ([string]::IsNullOrWhiteSpace($side)) {
        Write-ApplicationLog 'No position selected. Exiting.'
        exit 0
    }

    Write-ApplicationLog "Selected laptop position: $side."
    $progressForm = Show-ProgressDialog
    Update-ProgressStatus -Form $progressForm -Text 'Switching to extended desktop mode...'

    & "$env:WINDIR\System32\DisplaySwitch.exe" /extend
    Start-Sleep -Seconds 3

    Update-ProgressStatus -Form $progressForm -Text 'Detecting connected monitors...'
    $rawMonitors = Export-MonitorData `
        -ToolPath $toolPath `
        -OutputPath $script:MonitorListPath

    $monitors = ConvertTo-MonitorObjects -RawMonitors $rawMonitors
    if ($monitors.Count -eq 0) {
        throw 'No active monitors were found.'
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
        throw 'No external monitors were found.'
    }

    if ($side -eq 'left') {
        $sortedMonitors = @($laptopMonitor) + $externalMonitors
    }
    else {
        $sortedMonitors = $externalMonitors + @($laptopMonitor)
    }

    $sortedMonitors = @($sortedMonitors | Where-Object { $null -ne $_ })

    Write-ApplicationLog 'Display order reported by Windows:'
    foreach ($monitor in $sortedMonitors) {
        Write-Host (' - {0}: {1}' -f $monitor.Name, $monitor.DisplayName)
    }

    Update-ProgressStatus -Form $progressForm -Text 'Applying the maximum available resolutions...'
    foreach ($monitor in $sortedMonitors) {
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

    Update-ProgressStatus -Form $progressForm -Text 'Arranging the monitors...'
    & $toolPath @monitorArguments
    Start-Sleep -Seconds 3

    # Select the center external monitor. With an even number, select the
    # left monitor of the two center displays.
    $primaryIndex = [math]::Floor(($externalMonitors.Count - 1) / 2)
    $primaryMonitor = $externalMonitors[$primaryIndex]

    Update-ProgressStatus -Form $progressForm -Text 'Setting the primary display...'
    Write-ApplicationLog "Setting primary display to $($primaryMonitor.DisplayName)."
    & $toolPath /SetPrimary $primaryMonitor.Name
    & "$env:WINDIR\System32\DisplaySwitch.exe" /extend
    Start-Sleep -Seconds 2

    Write-ApplicationLog 'Monitor configuration completed.'
    Show-ProgressCompleted -Form $progressForm
    $progressForm = $null
}
catch {
    Close-ProgressDialog -Form $progressForm
    $progressForm = $null
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

    Show-ApplicationMessage `
        -Title 'Monitor configuration failed' `
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
