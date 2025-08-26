#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Builds a cumulative bar chart of new-player joins over the last available logs
  (up to 7 days back), split into a minimum of 20 slots, shows data labels,
  overlays your Imgur logo via ImageMagick in the top-left, and posts to Discord.
.PARAMETER Slots
  Number of bars to display; default is 20.
#>
param(
    [int]   $Slots       = 20,
    [string]$StatsFile   = 'StatsHistory.txt',
    [string]$ChartPath   = 'NewPlayersChart.png',
    [string]$LogoUrl     = 'https://i.imgur.com/Zdufcwx.jpeg',
    [string]$LogoPath    = 'logo.png',
    [string]$WebhookUrl  = $env:DISCORD_WEBHOOK
)

# Helper function: returns “st”, “nd”, “rd” or “th”
function Get-OrdinalSuffix($n) {
    switch ($n % 100) {
        { $_ -in 11..13 } { return 'th' }
    }
    switch ($n % 10) {
        1 { return 'st' }
        2 { return 'nd' }
        3 { return 'rd' }
        default { return 'th' }
    }
}

try {
    # 1. Load & sort history
    if (-not (Test-Path $StatsFile)) {
        throw "Stats file not found: $StatsFile"
    }
    $entries = Get-Content $StatsFile | ForEach-Object {
        $parts = $_ -split ','
        [PSCustomObject]@{
            DateTime = [DateTime]::ParseExact($parts[0], 'yyyy-MM-dd HH:mm', $null)
            Total    = [int]$parts[2]
        }
    } | Sort-Object DateTime

    if ($entries.Count -eq 0) {
        throw "No log entries found."
    }

    # 2. Determine the 7-day window
    $latestTime    = $entries[-1].DateTime
    $earliestTime  = $entries[0].DateTime
    $minStart      = $latestTime.AddDays(-7)
    $startTime     = if ($earliestTime -lt $minStart) { $minStart } else { $earliestTime }
    $totalDuration = $latestTime - $startTime

    # 3. Compute each slot’s span
    $slotSpan = [TimeSpan]::FromTicks($totalDuration.Ticks / $Slots)

    # 4. Build cumulative data series + labels
    $labels     = @()
    $data       = @()
    $cumulative = 0

    for ($i = 0; $i -lt $Slots; $i++) {
        $bucketStart = $startTime + ($slotSpan * $i)
        $bucketEnd   = $startTime + ($slotSpan * ($i + 1))

        # last log ≤ bucket start
        $prevLog = $entries |
            Where-Object { $_.DateTime -le $bucketStart } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1
        if (-not $prevLog) { $prevLog = $entries[0] }

        # last log ≤ bucket end
        $endLog = $entries |
            Where-Object { $_.DateTime -le $bucketEnd } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1

        # compute joins
        $joined = if ($endLog) { $endLog.Total - $prevLog.Total } else { 0 }
        if ($joined -gt 0) { $cumulative += $joined }

        # label formatting:
        # - multi-day: “MonthName DayOrdinal” (e.g. “August 25th”)
        # - single-day: “HHH” (e.g. “14H”, “03H”)
        if ($totalDuration.TotalDays -gt 1) {
            $month  = $bucketStart.ToString('MMMM')
            $day    = $bucketStart.Day
            $suffix = Get-OrdinalSuffix $day
            $labels += "$month $day$suffix"
        } else {
            $labels += $bucketStart.ToString('HH') + 'H'
        }

        $data += $cumulative
    }

    # 5. QuickChart JSON (title + datalabels)
    $chartConfig = @{
        type = 'bar'
        data = @{
            labels   = $labels
            datasets = @(@{
                data            = $data
                backgroundColor = 'rgba(54,162,235,0.7)'
            })
        }
        options = @{
            title = @{
                display = $true
                text    = 'New Players (up to 7 days)'
                font    = @{ size = 18 }
            }
            legend = @{ display = $false }
            scales = @{
                xAxes = @(@{
                    ticks     = @{ autoSkip = $false; maxRotation = 45; minRotation = 45 }
                    gridLines = @{ display = $false }
                })
                yAxes = @(@{
                    ticks     = @{ beginAtZero = $true }
                    gridLines = @{ color = 'rgba(200,200,200,0.2)' }
                })
            }
            plugins = @{
                datalabels = @{
                    color     = 'white'
                    anchor    = 'end'
                    align     = 'end'
                    offset    = -4
                    font      = @{ size = 12 }
                }
            }
            layout = @{ padding = @{ top = 30; bottom = 10 } }
        }
    } | ConvertTo-Json -Depth 6 -Compress

    # 6. Fetch chart PNG (with datalabels)
    $encoded = [uri]::EscapeDataString($chartConfig)
    $url     = "https://quickchart.io/chart?c=$encoded&plugins=chartjs-plugin-datalabels"
    Invoke-WebRequest -Uri $url -OutFile $ChartPath -ErrorAction Stop

    # 7. Download logo & overlay via ImageMagick (top-left)
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoPath -ErrorAction Stop
    $magick = (Get-Command magick -ErrorAction SilentlyContinue)?.Source `
           ?? (Get-Command convert -ErrorAction SilentlyContinue)?.Source
    if (-not $magick) {
        throw "ImageMagick not found on PATH."
    }
    & $magick $ChartPath $LogoPath -gravity northwest -geometry 260x260+10+10 -composite $ChartPath

    # 8. Send to Discord (embed only)
    $payload = @{
        embeds = @(@{ image = @{ url = 'attachment://' + (Split-Path $ChartPath -Leaf) } })
    }
    $payloadJson = $payload | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri $WebhookUrl `
        -Method Post `
        -ContentType 'multipart/form-data' `
        -Form @{
            payload_json = $payloadJson
            file1        = Get-Item $ChartPath
        }

    Write-Host "✅ Chart posted; cumulative max = $cumulative."
    exit 0

} catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 1
}
