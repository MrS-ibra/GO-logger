#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG for the last 24 hours,
# showing Players Online (line) and Players Joined per interval (bars),
# overlays logo with ImageMagick, sends to Discord (Linux-safe)

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

    # Last 24 hours cutoff
    $cutoff = (Get-Date).AddHours(-24)

    # Read and filter lines within window, ensure CSV format, robust timestamp parse
    $recentLines = Get-Content $PeakLog | Where-Object {
        $parts = $_ -split ','
        if ($parts.Count -ne 3) { return $false }
        try { $ts = [datetime]$parts[0] } catch { return $false }
        $ts -ge $cutoff
    }

    if ($recentLines.Count -lt 2) {
        throw "Not enough data in the last 24 hours in $PeakLog"
    }

    # Build labels (HH:mm), online data, and joined-per-interval from TOTAL column (index 2)
    $labels = @()
    $onlineData = @()
    $joinedData = @()

    for ($i = 0; $i -lt $recentLines.Count; $i++) {
        $parts = $recentLines[$i] -split ','
        $ts     = [datetime]$parts[0]
        $online = [int]$parts[1]
        $total  = [int]$parts[2]

        $labels     += $ts.ToString('HH:mm')
        $onlineData += $online

        if ($i -eq 0) {
            $joinedData += 0
        } else {
            $prevTotal = [int]($recentLines[$i-1] -split ',')[2]
            $delta     = $total - $prevTotal
            if ($delta -lt 0) { $delta = 0 }  # defensive clamp; total should be non-decreasing
            $joinedData += $delta
        }
    }

    # QuickChart config: Online (line, left axis) + Joined (bars, right axis)
    $chartConfig = @{
        type = 'bar'
        data = @{
            labels   = $labels
            datasets = @(
                @{
                    type            = 'line'
                    label           = 'Players Online'
                    data            = $onlineData
                    borderColor     = 'green'
                    backgroundColor = 'rgba(0,128,0,0.2)'
                    fill            = $false
                    tension         = 0.1
                    yAxisID         = 'y'
                },
                @{
                    type            = 'bar'
                    label           = 'Players Joined'
                    data            = $joinedData
                    backgroundColor = 'rgba(54,162,235,0.6)'
                    borderColor     = 'rgba(54,162,235,1)'
                    yAxisID         = 'y1'
                }
            )
        }
        options = @{
            responsive = $true
            interaction = @{ mode = 'index'; intersect = $false }
            stacked = $false
            plugins = @{
                title = @{ display = $true; text = "Generals Online — Last 24 Hours" }
                legend = @{ display = $true }
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
                x = @{ ticks = @{ maxRotation = 90; minRotation = 90 } }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    # Get chart PNG via GET (matches your working pattern)
    $encodedConfig = [uri]::EscapeDataString($chartConfig)
    $chartUrl = "https://quickchart.io/chart?c=$encodedConfig"
    Invoke-WebRequest -Uri $chartUrl -OutFile $ChartPath -ErrorAction Stop

    if (-not (Test-Path $ChartPath)) {
        throw "Chart file was not created."
    }

    # Minimal PNG sanity check (magic header) before overlay/upload
    $bytes = [System.IO.File]::ReadAllBytes($ChartPath)
    if ($bytes.Length -lt 4 -or $bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50 -or $bytes[2] -ne 0x4E -or $bytes[3] -ne 0x47) {
        throw "Chart file is not a PNG — QuickChart likely returned an error page."
    }

    # Download logo
    Invoke-WebRequest -Uri "https://i.imgur.com/Zdufcwx.jpeg" -OutFile $LogoPath -ErrorAction Stop

    # Prefer ImageMagick 'composite' on Linux (IM6), fall back to magick/convert
    $compositePath = (Get-Command composite -ErrorAction SilentlyContinue)?.Source
    if ($compositePath) {
        $tempChart = [System.IO.Path]::GetTempFileName()
        & $compositePath -geometry 260x260+10+10 $LogoPath $ChartPath $tempChart
        Move-Item -Force $tempChart $ChartPath
    } else {
        $magickPath = (Get-Command magick -ErrorAction SilentlyContinue)?.Source
        if (-not $magickPath) {
            $magickPath = (Get-Command convert -ErrorAction SilentlyContinue)?.Source
        }
        if (-not $magickPath) {
            throw "ImageMagick not found on this system."
        }
        & $magickPath $ChartPath $LogoPath -geometry 260x260+10+10 -composite $ChartPath
    }

    # Send to Discord (your original working method)
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Form @{
        payload_json = (@{ content = "" } | ConvertTo-Json -Compress)
        file         = Get-Item $ChartPath
    }

}
catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 8
}
