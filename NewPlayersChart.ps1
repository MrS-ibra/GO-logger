<#
.SYNOPSIS
  Builds a cumulative bar chart of new-player joins over the last available logs
  (up to 7 days back), split into a minimum of 20 equal slots, shows data labels,
  applies your Imgur logo as a watermark, and posts it to Discord.
.PARAMETER Slots
  Number of time buckets (bars) to display; default is 20.
#>
param(
    [int]$Slots = 20
)

# Paths & Settings
$historyFile = Join-Path $PSScriptRoot 'StatsHistory.txt'
$outputImage = Join-Path $PSScriptRoot 'NewPlayersChart.png'
$webhookUrl  = $env:DISCORD_WEBHOOK
$logoUrl     = 'https://i.imgur.com/Zdufcwx.jpeg'

if (-not (Test-Path $historyFile)) {
    Write-Error "StatsHistory.txt not found"
    exit 1
}

# 1. Load & sort logs
$entries = Get-Content $historyFile | ForEach-Object {
    $p = $_ -split ','
    [PSCustomObject]@{
        DateTime = [DateTime]::ParseExact($p[0], 'yyyy-MM-dd HH:mm', $null)
        Total    = [int]$p[2]
    }
} | Sort-Object DateTime

if ($entries.Count -eq 0) {
    Write-Error "No log entries"
    exit 1
}

# 2. Determine time window (cap at 7 days back)
$latestTime    = $entries[-1].DateTime
$earliestTime  = $entries[0].DateTime
$minStart      = $latestTime.AddDays(-7)
$startTime     = if ($earliestTime -lt $minStart) { $minStart } else { $earliestTime }
$totalDuration = $latestTime - $startTime

# 3. Compute slot duration (always Slots buckets)
$slotDuration = [TimeSpan]::FromTicks($totalDuration.Ticks / $Slots)

# 4. Build cumulative data + labels
$labels     = @()
$data       = @()
$cumulative = 0

for ($i = 0; $i -lt $Slots; $i++) {
    $bStart = $startTime + ($slotDuration * $i)
    $bEnd   = $startTime + ($slotDuration * ($i + 1))

    # Last log ≤ bucket start
    $prevLog = $entries |
        Where-Object { $_.DateTime -le $bStart } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1
    if (-not $prevLog) { $prevLog = $entries[0] }

    # Last log ≤ bucket end
    $endLog = $entries |
        Where-Object { $_.DateTime -le $bEnd } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1

    # Raw joins in this slot
    $joined = if ($endLog) { $endLog.Total - $prevLog.Total } else { 0 }
    if ($joined -gt 0) { $cumulative += $joined }

    # Smart label: if >1 day range then show date + time; else just time
    if ($totalDuration.TotalDays -gt 1) {
        $labels += $bStart.ToString('MM-dd HH:mm')
    } else {
        $labels += $bStart.ToString('HH:mm')
    }

    $data += $cumulative
}

# 5. Build QuickChart JSON with datalabels & watermark plugin
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
            watermark = @{
                image    = $logoUrl
                position = 'topRight'
                width    = 40
                opacity  = 0.5
            }
        }
        layout = @{ padding = @{ top = 20; bottom = 10 } }
    }
} | ConvertTo-Json -Depth 6

# 6. Render chart (with both plugins) at 1200x600
$encoded = [System.Net.WebUtility]::UrlEncode($chartConfig)
$plugins = 'chartjs-plugin-datalabels,chartjs-plugin-watermark'
$uri     = "https://quickchart.io/chart?c=$encoded&width=1200&height=600&format=png&plugins=$plugins"

Invoke-WebRequest -Uri $uri -OutFile $outputImage

# 7. Post to Discord (embed only, preserve Spy Drone name)
$payload = @{
    embeds = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } })
}
$payloadJson = $payload | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $webhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
        payload_json = $payloadJson
        file1        = Get-Item $outputImage
    }

Write-Host "Posted $Slots slots over $([math]::Round($totalDuration.TotalDays,2)) days; cumulative=$cumulative."
