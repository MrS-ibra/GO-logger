#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG, overlays logo with ImageMagick, sends to Discord

param(
    [string]$WebhookUrl = $env:DISCORD_WEBHOOK,
    [string]$PeakLog    = "StatsHistory.txt",
    [string]$ChartPath  = "TodayTrend.png",
    [string]$LogoPath   = "logo.png"
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

    # QuickChart config
    $chartConfig = @{
        type = 'bar'
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

    # Download chart PNG
    $encodedConfig = [uri]::EscapeDataString($chartConfig)
    $chartUrl = "https://quickchart.io/chart?c=$encodedConfig"
    Invoke-WebRequest -Uri $chartUrl -OutFile $ChartPath -ErrorAction Stop

    if (-not (Test-Path $ChartPath)) {
        throw "Chart file was not created."
    }

    # Download logo 
    Invoke-WebRequest -Uri "https://i.imgur.com/Zdufcwx.jpeg" -OutFile $LogoPath -ErrorAction Stop

    # Detect ImageMagick binary
    $magickPath = (Get-Command magick -ErrorAction SilentlyContinue)?.Source
    if (-not $magickPath) {
        $magickPath = (Get-Command convert -ErrorAction SilentlyContinue)?.Source
    }
    if (-not $magickPath) {
        throw "ImageMagick not found on this system."
    }

    # Overlay logo on chart
    & $magickPath $ChartPath $LogoPath -geometry 260x260+10+10 -composite $ChartPath

    # Send to Discord
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Form @{
        payload_json = (@{ content = "" } | ConvertTo-Json -Compress)
        file         = Get-Item $ChartPath
    }

}
catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 8
}
