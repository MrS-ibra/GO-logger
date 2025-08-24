#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG for the last 24 hours,
# showing both Online Players and Players Joined per interval,
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

    # Build labels (HH:mm), online data, and joined-per-interval data
    $labels = @()
    $onlineData = @()
    $joinedData = @()

    for ($i = 0; $i -lt $recentLines.Count; $i++) {
        $parts = $recentLines[$i] -split ','
        $ts    = [datetime]$parts[0]
        $online = [int]$parts[1]
        $total  = [int]$parts[2]

        $labels += $ts.ToString('HH:mm')
        $onlineData += $online

        if ($i -eq 0) {
            $joinedData += 0
        }
        else {
            $prevTotal = [int]($recentLines[$i-1] -split ',')[2]
            $joinedData += ($total - $prevTotal)
        }
    }

    # QuickChart config with two datasets
    $chartConfig = @{
        type = 'bar'
        data = @{
            labels   = $labels
            datasets = @(
                @{
                    type        = 'line'
                    label       = 'Players Online'
                    data        = $onlineData
                    borderColor = 'green'
                    backgroundColor = 'rgba(0,128,0,0.2)'
                    fill        = $false
                    yAxisID     = 'y'
                },
                @{
                    type        = 'bar'
                    label       = 'Players Joined'
                    data        = $joinedData
                    backgroundColor = 'rgba(54, 162, 235, 0.5)'
                    borderColor = 'rgba(54, 162, 235, 1)'
                    yAxisID     = 'y1'
                }
            )
        }
        options = @{
            responsive = $true
            interaction = @{
                mode = 'index'
                intersect = $false
            }
            stacked = $false
            plugins = @{
                title = @{
                    display = $true
                    text    = "Generals Online — Last 24 Hours"
                }
            }
            scales = @{
                y = @{
                    type = 'linear'
                    position = 'left'
                    title = @{ display = $true; text = 'Online Players' }
                }
                y1 = @{
                    type = 'linear'
                    position = 'right'
                    grid = @{ drawOnChartArea = $false }
                    title = @{ display = $true; text = 'Players Joined' }
                }
                x = @{
                    ticks = @{ maxRotation = 90; minRotation = 90 }
                }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    # Download chart PNG via POST to avoid URL length issues
    Invoke-WebRequest -Uri "https://quickchart.io/chart" `
        -Method Post `
        -ContentType "application/json" `
        -Body $chartConfig `
        -OutFile $ChartPath `
        -ErrorAction Stop

    if (-not (Test-Path $ChartPath)) {
        throw "Chart file was not created."
    }

    # Validate PNG magic bytes before sending
    $bytes = [System.IO.File]::ReadAllBytes($ChartPath)
    if ($bytes.Length -lt 4 -or $bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50 -or $bytes[2] -ne 0x4E -or $bytes[3] -ne 0x47) {
        throw "Chart file is not a valid PNG — QuickChart may have returned an error page."
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
