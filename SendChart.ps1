#!/usr/bin/env pwsh
param(
    [string]$WebhookUrl = $env:DISCORD_WEBHOOK,
    [string]$PeakLog    = "StatsHistory.txt",
    [string]$ChartPath  = "Last24hTrend.png",
    [string]$LogoPath   = "logo.png"
)

try {
    if (-not (Test-Path $PeakLog)) { throw "Stats history file not found: $PeakLog" }

    $cutoff = (Get-Date).AddHours(-24)

    $recentLines = Get-Content $PeakLog | Where-Object {
        $parts = $_ -split ','
        if ($parts.Count -ne 3) { return $false }
        try { $ts = [datetime]$parts[0] } catch { return $false }
        $ts -ge $cutoff
    }

    if ($recentLines.Count -lt 2) { throw "Not enough data in the last 24 hours" }

    $labels, $onlineData, $joinedData = @(), @(), @()

    for ($i=0; $i -lt $recentLines.Count; $i++) {
        $parts = $recentLines[$i] -split ','
        $ts    = [datetime]$parts[0]
        $online = [int]$parts[1]
        $total  = [int]$parts[2]

        $labels += $ts.ToString('HH:mm')
        $onlineData += $online
        $joinedData += if ($i -eq 0) { 0 } else { $total - [int]($recentLines[$i-1] -split ',')[2] }
    }

    $chartConfig = @{
        type = 'bar'
        data = @{
            labels   = $labels
            datasets = @(
                @{
                    type = 'line'; label = 'Players Online'; data = $onlineData
                    borderColor = 'green'; backgroundColor = 'rgba(0,128,0,0.2)'
                    fill = $false; yAxisID = 'y'
                },
                @{
                    type = 'bar'; label = 'Players Joined'; data = $joinedData
                    backgroundColor = 'rgba(54, 162, 235, 0.5)'
                    borderColor = 'rgba(54, 162, 235, 1)'; yAxisID = 'y1'
                }
            )
        }
        options = @{
            responsive = $true
            interaction = @{ mode = 'index'; intersect = $false }
            stacked = $false
            plugins = @{ title = @{ display = $true; text = "Generals Online — Last 24 Hours" } }
            scales = @{
                y  = @{ type = 'linear'; position = 'left';  title = @{ display = $true; text = 'Online Players' } }
                y1 = @{ type = 'linear'; position = 'right'; grid = @{ drawOnChartArea = $false }; title = @{ display = $true; text = 'Players Joined' } }
                x  = @{ ticks = @{ maxRotation = 90; minRotation = 90 } }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    # POST to QuickChart to avoid URL length issues
    Invoke-WebRequest -Uri "https://quickchart.io/chart" `
        -Method Post `
        -ContentType "application/json" `
        -Body $chartConfig `
        -OutFile $ChartPath `
        -ErrorAction Stop

    if (-not (Test-Path $ChartPath)) { throw "Chart file was not created." }

    Invoke-WebRequest -Uri "https://i.imgur.com/Zdufcwx.jpeg" -OutFile $LogoPath -ErrorAction Stop

    $magickPath = (Get-Command magick -ErrorAction SilentlyContinue)?.Source
    if (-not $magickPath) { $magickPath = (Get-Command convert -ErrorAction SilentlyContinue)?.Source }
    if (-not $magickPath) { throw "ImageMagick not found on this system." }

    & $magickPath $ChartPath $LogoPath -geometry 260x260+10+10 -composite $ChartPath

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
