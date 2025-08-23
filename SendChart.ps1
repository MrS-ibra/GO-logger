#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG with embedded logo, sends it to Discord

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

    # Download logo and convert to Base64 data URI
    $logoBytes = (Invoke-WebRequest "https://i.imgur.com/MMleWsX.png" -UseBasicParsing).Content
    $logoBase64 = [System.Convert]::ToBase64String($logoBytes)
    $logoDataUri = "data:image/png;base64,$logoBase64"

    # QuickChart config with embedded logo drawn in top-left corner
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
        plugins = @(
            @"
            {
              id: 'customLogo',
              afterDraw: chart => {
                const ctx = chart.ctx;
                const image = new Image();
                image.src = '$logoDataUri';
                ctx.drawImage(image, 10, 10, 50, 50);
              }
            }
"@
        )
    } | ConvertTo-Json -Depth 10 -Compress

    # Download chart PNG
    Invoke-WebRequest -Uri "https://quickchart.io/chart?c=$([uri]::EscapeDataString($chartConfig))" `
                      -OutFile $ChartPath -ErrorAction Stop

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
