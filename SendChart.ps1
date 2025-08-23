#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG with background image, sends it to Discord

param(
    [string]$WebhookUrl = $env:DISCORD_WEBHOOK,
    [string]$PeakLog    = "StatsHistory.txt",
    [string]$ChartPath  = "TodayTrend.png"
)

try {
    if (-not (Test-Path $PeakLog)) {
        throw "Stats history file not found: $PeakLog"
    }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $todayLines = Get-Content $PeakLog | Where-Object {
        ($_ -match "^$today") -and (($_ -split ',').Count -eq 3)
    }

    if ($todayLines.Count -eq 0) {
        throw "No data for $today in $PeakLog"
    }

    # Build labels and data arrays
    $labels = $todayLines | ForEach-Object { ($_.Split(',')[0]).Split(' ')[1] }
    $data   = $todayLines | ForEach-Object { [int]($_.Split(',')[1]) }

    # QuickChart config (no logo here, background will be added via query param)
    $chartConfig = @{
        type = 'line'
        data = @{
            labels   = $labels
            datasets = @(@{
                label       = 'Players Online'
                data        = $data
                borderColor = 'green'
                fill        = $false
            })
        }
        options = @{
            title = @{
                display = $true
                text    = "Generals Online — $today"
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    # Build QuickChart URL with background image
    $encodedConfig = [uri]::EscapeDataString($chartConfig)
    $backgroundUrl = [uri]::EscapeDataString("https://i.imgur.com/MMleWsX.png")
    $chartUrl = "https://quickchart.io/chart?backgroundImage=$backgroundUrl&c=$encodedConfig"

    # Download chart PNG
    Invoke-WebRequest -Uri $chartUrl -OutFile $ChartPath -ErrorAction Stop

    if (-not (Test-Path $ChartPath)) {
        throw "Chart file was not created."
    }

    # Send to Discord (image only)
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Form @{
        payload_json = (@{ content = "" } | ConvertTo-Json -Compress)
        file         = Get-Item $ChartPath
    }

}
catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 8
}
