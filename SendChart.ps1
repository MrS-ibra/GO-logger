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

    # Helper: robust int parse (strips any non-digits)
    function Normalize-Int([string]$s) {
        $digits = ($s -replace '[^\d]', '')
        if ([string]::IsNullOrWhiteSpace($digits)) { return 0 }
        return [int]$digits
    }

    # Rolling 24h cutoff
    $cutoff = (Get-Date).AddHours(-24)

    # Parse file into structured rows (timestamp, online, total)
    $rows = foreach ($line in Get-Content $PeakLog) {
        if (-not ($line -match '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2},')) { continue }
        $parts = $line.Split(',', 3)
        if ($parts.Count -ne 3) { continue }

        $ts = $null
        try { $ts = [datetime]$parts[0].Trim() } catch { continue }

        [pscustomobject]@{
            Timestamp = $ts
            OnlineRaw = $parts[1].Trim()
            TotalRaw  = $parts[2].Trim()
        }
    } | Sort-Object Timestamp

    if (-not $rows -or $rows.Count -lt 2) {
        throw "Not enough data in $PeakLog"
    }

    # Filter to last 24 hours
    $recent = $rows | Where-Object { $_.Timestamp -ge $cutoff }
    if ($recent.Count -lt 2) {
        throw "Not enough data in the last 24 hours in $PeakLog"
    }

    # Build labels and datasets
    $labels     = @()
    $onlineData = @()
    $joinedData = @()

    $prevTotal = $null
    $maxPlausibleJump = 50   # ignore larger jumps as scrape glitches (e.g., "024440")

    foreach ($r in $recent) {
        $labels += $r.Timestamp.ToString('HH:mm')

        $online = Normalize-Int $r.OnlineRaw
        $onlineData += $online

        $currTotal = Normalize-Int $r.TotalRaw

        if ($prevTotal -ne $null) {
            # Enforce non-decreasing total; drop obvious glitches
            if ($currTotal -lt $prevTotal) { $currTotal = $prevTotal }
            if (($currTotal - $prevTotal) -gt $maxPlausibleJump) {
                # Treat as glitch; hold previous total
                $currTotal = $prevTotal
            }

            $delta = $currTotal - $prevTotal
            if ($delta -lt 0) { $delta = 0 }  # defensive
            $joinedData += $delta
        } else {
            $joinedData += 0
        }

        $prevTotal = $currTotal
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
                legend = @{ display = $true }
            }
            scales = @{
                x = @{ ticks = @{ maxRotation = 90; minRotation = 90 } }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    # Download chart PNG (keep your original working pattern)
    $encodedConfig = [uri]::EscapeDataString($chartConfig)
    $chartUrl = "https://quickchart.io/chart?c=$encodedConfig"
    Invoke-WebRequest -Uri $chartUrl -OutFile $ChartPath -ErrorAction Stop

    if (-not (Test-Path $ChartPath)) {
        throw "Chart file was not created."
    }

    # Download logo
    Invoke-WebRequest -Uri "https://i.imgur.com/Zdufcwx.jpeg" -OutFile $LogoPath -ErrorAction Stop

    # Detect ImageMagick binary (Linux IM6 uses 'convert')
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
