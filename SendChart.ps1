#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG for the last 24 hours,
# showing Players Online and Players Joined per interval as lines,
# overlays logo with ImageMagick, sends to Discord

param(
    [string]$WebhookUrl = $env:DISCORD_WEBHOOK,
    [string]$PeakLog    = "StatsHistory.txt",
    [string]$ChartPath  = "Last24hTrend.png",
    [string]$LogoPath   = "logo.png"
)

try {
    if (-not (Test-Path $PeakLog)) {
        throw "Stats history file not found: $PeakLog"
    }

    # Calculate cutoff time for last 24 hours
    $cutoff = (Get-Date).AddHours(-24)

    # Read and filter lines newer than cutoff, ensuring valid CSV format
    $recentLines = Get-Content $PeakLog | Where-Object {
        $parts = $_ -split ','
        if ($parts.Count -ne 3) { return $false }
        try { $ts = [datetime]$parts[0] } catch { return $false }
        return $ts -ge $cutoff
    }

    if ($recentLines.Count -lt 2) {
        throw "Not enough data in the last 24 hours in $PeakLog"
    }

    # Build labels, online data, and joined-per-interval data
    $labels = @()
    $onlineData = @()
    $joinedData = @()

    for ($i = 0; $i -lt $recentLines.Count; $i++) {
        $parts  = $recentLines[$i] -split ','
        $ts     = [datetime]$parts[0]
        $online = [int]$parts[1]
        $total  = [int]$parts[2]

        $labels     += $ts.ToString('HH:mm')
        $onlineData += $online

        if ($i -eq 0) {
            $joinedData += 0
        }
        else {
            $prevTotal = [int]($recentLines[$i-1] -split ',')[2]
            $delta     = $total - $prevTotal
            if ($delta -lt 0) { $delta = 0 }  # clamp negatives
            $joinedData += $delta
        }
    }

    # QuickChart config with two line datasets
    $chartConfig = @{
        type = 'line'
        data = @{
            labels   = $labels
            datasets = @(
                @{
                    label           = 'Players Online'
                    data            = $onlineData
                    borderColor     = 'green'
                    backgroundColor = 'rgba(0,128,0,0.2)'
                    fill            = $false
                    tension         = 0.1
                },
                @{
                    label           = 'Players Joined'
                    data            = $joinedData
                    borderColor     = 'blue'
                    backgroundColor = 'rgba(54,162,235,0.2)'
                    fill            = $false
                    tension         = 0.1
                }
            )
        }
        options = @{
            responsive = $true
            plugins = @{
                title = @{
                    display = $true
                    text    = "Generals Online — Last 24 Hours"
                }
            }
            scales = @{
                x = @{ ticks = @{ maxRotation = 90; minRotation = 90 } }
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

    # Send to Discord (original working method)
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Form @{
        payload_json = (@{ content = "" } | ConvertTo-Json -Compress)
        file         = Get-Item $ChartPath
    }

}
catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 8
}
