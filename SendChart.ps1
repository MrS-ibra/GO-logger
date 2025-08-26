#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG for the last 24 hours,
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
        try {
            $ts = [datetime]$parts[0]
        }
        catch {
            return $false
        }
        return $ts -ge $cutoff
    }

    if ($recentLines.Count -eq 0) {
        throw "No data in the last 24 hours in $PeakLog"
    }

    # Build labels (HH:mm) and data arrays
    $labels = $recentLines | ForEach-Object {
        ([datetime]($_.Split(',')[0])).ToString('HH:mm')
    }
    $data   = $recentLines | ForEach-Object { [int]($_.Split(',')[1]) }

# QuickChart config
$chartConfig = @{
    type = 'bar'
    data = @{
        labels   = $labels
        datasets = @(@{
            label       = 'Players Online'
            data        = $data
            fontColor   = 'white'
            borderColor = 'green'
            fill        = $false
        })
    }
    options = @{
        title = @{
            display     = $true
            text        = "Players Online — Last 24 Hours"
            fontColor   = 'red'
        }
        scales = @{
            x = @{
                ticks = @{
                    maxRotation = 90
                    minRotation = 90
                }
            }
        }
    }
} | ConvertTo-Json -Depth 10 -Compress

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
