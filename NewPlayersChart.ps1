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
    if (-not (Test-Path $HistoryFile)) { throw "Stats history file not found: $HistoryFile" }
    $entries = Get-Content $HistoryFile | ForEach-Object {
        $parts = $_ -split ','
        [PSCustomObject]@{
            DateTime = [DateTime]::ParseExact($parts[0],'yyyy-MM-dd HH:mm',$null)
            Total    = [int]$parts[2]
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
        $bucketStart = $startTime + ($slotDuration * $i)
        $bucketEnd   = $startTime + ($slotDuration * ($i + 1))

        $prevLog = $entries |
            Where-Object { $_.DateTime -le $bucketStart } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1
        if (-not $prevLog) { $prevLog = $entries[0] }

        $endLog = $entries |
            Where-Object { $_.DateTime -le $bucketEnd } |
            Sort-Object DateTime -Descending |
            Select-Object -First 1

        $joined = if ($endLog) { $endLog.Total - $prevLog.Total } else { 0 }
        if ($joined -gt 0) { $cumulative += $joined }

        # smart label: date+time if multi-day, else time only
        if ($totalDuration.TotalDays -gt 1) {
            $labels += $bucketStart.ToString('MM-dd HH:mm')
        } else {
            $labels += $bucketStart.ToString('HH:mm')
        }

        $data += $cumulative
    }

    # 5. QuickChart JSON (bar + datalabels)
    $chartConfig = @{
        type    = 'bar'
        data    = @{
            labels   = $labels
            datasets = @(@{
                data            = $data
                backgroundColor = 'rgba(54,162,235,0.7)'
            })
        }
        options = @{
            title  = @{ display = $false }
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
            }
            layout = @{ padding = @{ top = 20; bottom = 10 } }
        }
    } | ConvertTo-Json -Depth 6

    # 6. Download chart PNG (no watermark plugin, just datalabels)
    $encoded   = [uri]::EscapeDataString($chartConfig)
    $chartUrl  = "https://quickchart.io/chart?c=$encoded&width=1200&height=600&format=png&plugins=chartjs-plugin-datalabels"
    Invoke-WebRequest -Uri $chartUrl -OutFile $ChartFile -ErrorAction Stop

    # 7. Download logo and overlay via ImageMagick
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoFile -ErrorAction Stop

    $magick = (Get-Command magick -ErrorAction SilentlyContinue)?.Source `
           ?? (Get-Command convert -ErrorAction SilentlyContinue)?.Source
    if (-not $magick) { throw "ImageMagick not found on PATH." }

    & $magick $ChartFile $LogoFile -geometry 100x100+10+10 -composite $ChartFile

    # 8. Send to Discord (embed only, Spy Drone default)
    $payload = @{
        embeds = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } })
    }
    $payloadJson = $payload | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $WebhookUrl `
      -Method Post `
      -ContentType 'multipart/form-data' `
      -Form @{
        payload_json = $payloadJson
        file1        = Get-Item $ChartFile
      }

    Write-Host "✅ Chart posted with $Slots slots; cumulative max = $cumulative."
    exit 0

} catch {
    Write-Error "❌ Failed: $($_.Exception.Message)"
    exit 1
}
