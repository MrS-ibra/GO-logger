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

    # Cutoff for rolling 24 hours
    $cutoff = (Get-Date).AddHours(-24)

    # Robust CSV parse with explicit headers, then filter & sort
    $rawLines = Get-Content $PeakLog | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2},\d+,\d+' }
    if (-not $rawLines -or $rawLines.Count -lt 2) {
        throw "Not enough data in $PeakLog"
    }

    $rows = $rawLines |
        ConvertFrom-Csv -Header Timestamp,Online,Total |
        ForEach-Object {
            # Safe parsing and trimming
            $ts = $null
            try { $ts = [datetime]($_.Timestamp) } catch { return }
            [pscustomobject]@{
                Timestamp = $ts
                Online    = ([int]("$($_.Online)".Trim()))
                Total     = ([int]("$($_.Total)".Trim()))
            }
        } |
        Where-Object { $_ -ne $null } |
        Sort-Object Timestamp

    # Apply last-24h window
    $recent = $rows | Where-Object { $_.Timestamp -ge $cutoff }
    if ($recent.Count -lt 2) {
        throw "Not enough data in the last 24 hours in $PeakLog"
    }

    # Build labels and datasets
    $labels     = @()
    $onlineData = @()
    $joinedData = @()

    for ($i = 0; $i -lt $recent.Count; $i++) {
        $labels     += $recent[$i].Timestamp.ToString('HH:mm')
        $onlineData += [int]$recent[$i].Online

        if ($i -eq 0) {
            $joinedData += 0
        } else {
            $delta = [int]$recent[$i].Total - [int]$recent[$i-1].Total
            if ($delta -lt 0) { $delta = 0 }  # defensive: Total should be non-decreasing
            $joinedData += $delta
        }
    }

    # QuickChart config: two line datasets
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
                legend = @{ display = $true }
            }
            scales = @{
                x = @{ ticks = @{ maxRotation = 90; minRotation = 90 } }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    # Download chart PNG (your original working pattern)
    $encodedConfig = [uri]::EscapeDataString($chartConfig)
    $chartUrl = "https://quickchart.io/chart?c=$encodedConfig"
    Invoke-WebRequest -Uri $chartUrl -OutFile $ChartPath -ErrorAction Stop

    if (-not (Test-Path $ChartPath)) {
        throw "Chart file was not created."
    }

    # Download logo
    Invoke-WebRequest -Uri "https://i.imgur.com/Zdufcwx.jpeg" -OutFile $LogoPath -ErrorAction Stop

    # Detect ImageMagick binary (Linux-friendly)
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
