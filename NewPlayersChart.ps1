#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Builds a cumulative bar chart of new-player joins over the last available logs
  (up to 7 days back), split into a minimum of 20 slots, shows data labels,
  overlays your Imgur logo via ImageMagick, and posts the final PNG to Discord.
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

try {
    # 1. Load & sort history
    if (-not (Test-Path $StatsFile)) {
        throw "Stats file not found: $StatsFile"
    }
    $entries = Get-Content $StatsFile | ForEach-Object {
        $p = $_ -split ','
        [PSCustomObject]@{
            DateTime = [DateTime]::ParseExact($p[0], 'yyyy-MM-dd HH:mm', $null)
            Total    = [int]$p[2]
        }
    } | Sort-Object DateTime

    if ($entries.Count -eq 0) {
        throw "No log entries found."
    }

    # 2. Determine time window (cap at 7 days back)
    $latestTime    = $entries[-1].DateTime
    $earliestTime  = $entries[0].DateTime
    $minStart      = $latestTime.AddDays(-7)
    $startTime     = if ($earliestTime -lt $minStart) { $minStart } else { $earliestTime }
    $totalDuration = $latestTime - $startTime

    # 3. Compute slot duration
    $slotDuration = [TimeSpan]::FromTicks($totalDuration.Ticks / $Slots)

    # 4. Build cumulative dataset + labels
    $labels     = @()
    $data       = @()
    $cumulative = 0

    for ($i = 0; $i -lt $Slots; $i++) {
        $bStart = $startTime + ($slotDuration * $i)
        $bEnd   = $startTime + ($slotDuration * ($i + 1))

        # Last log at or before bucket start
        $prevLog = $entries |
            Where-Object { $_.DateTime -le $bStart } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1
        if (-not $prevLog) { $prevLog = $entries[0] }

        # Last log at or before bucket end
        $endLog = $entries |
            Where-Object { $_.DateTime -le $bEnd } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1

        # Compute joins and accumulate
        $joined = if ($endLog) { $endLog.Total - $prevLog.Total } else { 0 }
        if ($joined -gt 0) { $cumulative += $joined }

        # Label formatting
        if ($totalDuration.TotalDays -gt 1) {
            $labels += $bStart.ToString('MM-dd HH:mm')
        } else {
            $labels += $bStart.ToString('HH:mm')
        }

        $data += $cumulative
    }

    # 5. QuickChart JSON (bar + datalabels + title)
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

    # 6. Download chart PNG (with datalabels)
    $encConfig = [uri]::EscapeDataString($chartConfig)
    $chartUrl  = "https://quickchart.io/chart?c=$encConfig&plugins=chartjs-plugin-datalabels"
    Invoke-WebRequest -Uri $chartUrl -OutFile $ChartPath -ErrorAction Stop

    # 7. Download logo and overlay via ImageMagick
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoPath -ErrorAction Stop

    $magick = (Get-Command magick -ErrorAction SilentlyContinue)?.Source `
           ?? (Get-Command convert -ErrorAction SilentlyContinue)?.Source
    if (-not $magick) {
        throw "ImageMagick not found on PATH."
    }

    & $magick $ChartPath $LogoPath -gravity northeast -geometry 260x260+10+10 -composite $ChartPath

    # 8. Send to Discord (embed only)
    $payload = @{
        embeds = @(@{ image = @{ url = 'attachment://'+(Split-Path $ChartPath -Leaf) } })
    }
    $payloadJson = $payload | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $WebhookUrl `
        -Method Post `
        -ContentType 'multipart/form-data' `
        -Form @{
            payload_json = $payloadJson
            file1        = Get-Item $ChartPath
        }

    Write-Host "✅ Chart posted successfully (cumulative = $cumulative)."
    exit 0

} catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 1
}
