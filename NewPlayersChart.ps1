#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Builds a cumulative bar chart of new-player joins over the last available logs
  (up to 7 days back), split into a minimum of 20 equal slots, shows data labels,
  overlays your Imgur logo via ImageMagick, and posts the final PNG to Discord.

.PARAMETER Slots
  Number of time buckets (bars) to display; default is 20.
#>
param(
    [int]   $Slots       = 20,
    [string]$HistoryFile = 'StatsHistory.txt',
    [string]$ChartFile   = 'NewPlayersChart.png',
    [string]$LogoUrl     = 'https://i.imgur.com/Zdufcwx.jpeg',
    [string]$LogoFile    = 'logo.png',
    [string]$WebhookUrl  = $env:DISCORD_WEBHOOK
)

try {

    # 1. Load & sort logs
    if (-not (Test-Path $HistoryFile)) { throw "StatsHistory.txt not found: $HistoryFile" }
    $entries = Get-Content $HistoryFile | ForEach-Object {
        $p = $_ -split ','
        [PSCustomObject]@{
            DateTime = [DateTime]::ParseExact($p[0],'yyyy-MM-dd HH:mm',$null)
            Total    = [int]$p[2]
        }
    } | Sort-Object DateTime

    if ($entries.Count -eq 0) { throw "No log entries found." }

    # 2. Determine time window (cap at 7 days back)
    $latest        = $entries[-1].DateTime
    $earliest      = $entries[0].DateTime
    $minAllowed    = $latest.AddDays(-7)
    $startTime     = if ($earliest -lt $minAllowed) { $minAllowed } else { $earliest }
    $totalDuration = $latest - $startTime

    # 3. Compute slot duration
    $slotDuration = [TimeSpan]::FromTicks($totalDuration.Ticks / $Slots)

    # 4. Build cumulative data + labels
    $labels     = @()
    $data       = @()
    $cumulative = 0

    for ($i = 0; $i -lt $Slots; $i++) {
        $bStart = $startTime + ($slotDuration * $i)
        $bEnd   = $startTime + ($slotDuration * ($i + 1))

        # Find the last log at or before bucket start
        $prevLog = $entries |
            Where-Object { $_.DateTime -le $bStart } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1
        if (-not $prevLog) { $prevLog = $entries[0] }

        # Find the last log at or before bucket end
        $endLog = $entries |
            Where-Object { $_.DateTime -le $bEnd } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1

        $joined = if ($endLog) { $endLog.Total - $prevLog.Total } else { 0 }
        if ($joined -gt 0) { $cumulative += $joined }

        # Smart labels: multi-day = date+time; single-day = time only
        if ($totalDuration.TotalDays -gt 1) {
            $labels += $bStart.ToString('MM-dd HH:mm')
        } else {
            $labels += $bStart.ToString('HH:mm')
        }

        $data += $cumulative
    }

    # 5. Build QuickChart JSON with title, datalabels & watermark plugin
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
                font    = @{ size = 20 }
                padding = @{ top = 10; bottom = 30 }
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
                    align     = 'start'
                    formatter = 'function(v){return v;}'
                    font      = @{ size = 12 }
                }
                watermark = @{
                    image    = $LogoUrl
                    position = 'topRight'
                    width    = 40
                    opacity  = 0.5
                }
            }
            layout = @{
                padding = @{ top = 40; bottom = 10 }
            }
        }
    } | ConvertTo-Json -Depth 6

    # 6. Download chart with both plugins enabled at higher resolution
    $encoded = [System.Net.WebUtility]::UrlEncode($chartConfig)
    $plugins = 'chartjs-plugin-datalabels,chartjs-plugin-watermark'
    $uri     = "https://quickchart.io/chart?c=$encoded&width=1200&height=600&format=png&plugins=$plugins"
    Invoke-WebRequest -Uri $uri -OutFile $ChartFile -ErrorAction Stop

    # 7. Overlay logo via ImageMagick (fallback if watermark plugin doesn’t work)
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoFile -ErrorAction Stop
    $magick = (Get-Command magick -ErrorAction SilentlyContinue)?.Source `
           ?? (Get-Command convert -ErrorAction SilentlyContinue)?.Source
    if (-not $magick) { throw "ImageMagick not found on PATH." }

    & $magick $ChartFile $LogoFile -geometry 100x100+10+10 -composite $ChartFile

    # 8. Post to Discord (embed only, keep Spy Drone identity)
    $payload = @{ embeds = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } }) }
    $payloadJson = $payload | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $WebhookUrl `
        -Method Post `
        -ContentType 'multipart/form-data' `
        -Form @{
            payload_json = $payloadJson
            file1        = Get-Item $ChartFile
        }

    Write-Host "✅ Chart posted with title, data labels, watermark logo and $Slots slots!"
    exit 0

} catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 1
}
