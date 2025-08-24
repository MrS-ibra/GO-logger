#!/usr/bin/env pwsh
# Reads StatsHistory.txt, generates a QuickChart PNG for the last 24 hours,
# showing Players Online (green) and Players Joined (red, cumulative from max so far),
# overlays logo (top-right) with ImageMagick, sends to Discord

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

    function Normalize-Int([string]$s) {
        $digits = ($s -replace '[^\d]', '')
        if ([string]::IsNullOrWhiteSpace($digits)) { return 0 }
        return [int]$digits
    }

    $cutoff = (Get-Date).AddHours(-24)

    # Parse file into structured rows
    $rows = Get-Content $PeakLog |
        Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2},' } |
        ForEach-Object {
            $parts = $_.Split(',', 3)
            if ($parts.Count -ne 3) { return }

            try {
                $ts = [datetime]$parts[0].Trim()
            } catch {
                return
            }

            [pscustomobject]@{
                Timestamp = $ts
                OnlineRaw = $parts[1].Trim()
                TotalRaw  = $parts[2].Trim()
            }
        } |
        Sort-Object Timestamp

    if (-not $rows -or $rows.Count -lt 2) {
        throw "Not enough data in $PeakLog"
    }

    # Filter to last 24 hours
    $recent = $rows | Where-Object { $_.Timestamp -ge $cutoff }
    if ($recent.Count -lt 2) {
        throw "Not enough data in the last 24 hours in $PeakLog"
    }

    $labels     = @()
    $onlineData = @()
    $joinedData = @()

    # Track first total and max so far
    $firstTotal = Normalize-Int $recent[0].TotalRaw
    $maxTotal   = $firstTotal

    foreach ($r in $recent) {
        $labels += $r.Timestamp.ToString('HH:mm')

        $onlineData += (Normalize-Int $r.OnlineRaw)

        $currTotal = Normalize-Int $r.TotalRaw
        if ($currTotal -gt $maxTotal) {
            $maxTotal = $currTotal
        }

        # Joined = max so far minus first total in window
        $joinedData += ($maxTotal - $firstTotal)
    }

    $dateLabel = (Get-Date).ToString('yyyy-MM-dd')

    # Chart config: Online as green bars, Joined as red bars
    $chartConfig = @{
        type = 'bar'
        data = @{
            labels   = $labels
            datasets = @(
                @{
                    label           = 'Players Online'
                    data            = $onlineData
                    borderColor     = 'rgba(0,128,0,1)'     # solid green border
                    backgroundColor = 'rgba(0,128,0,0.6)'   # semi-transparent green fill
                    yAxisID         = 'y'
                },
                @{
                    label           = 'Players Joined'
                    data            = $joinedData
                    borderColor     = 'rgba(255,0,0,1)'     # solid red border
                    backgroundColor = 'rgba(255,0,0,0.6)'   # semi-transparent red fill
                    yAxisID         = 'y1'
                }
            )
        }
        options = @{
            responsive = $true
            interaction = @{ mode = 'index'; intersect = $false }
            stacked = $false
            plugins = @{
                title = @{
                    display = $true
                    text    = "Generals Online — Last 24 Hours ($dateLabel)"
                }
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

    # Overlay logo in top-right, smaller size
    & $magickPath $ChartPath $LogoPath -gravity NorthEast -geometry 200x200+10+10 -composite $ChartPath

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
