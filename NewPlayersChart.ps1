<#
.SYNOPSIS
  Builds a cumulative bar chart of new‐player joins over the last available logs
  (up to 7 days), splits that range into a fixed number of slots, shows counts on
  each bar, applies your Imgur logo via QuickChart’s watermark API, and posts to Discord.
.PARAMETER Slots
  Number of time buckets (bars) to display; default is 18.
#>
param(
    [int]$Slots = 18
)

# Paths & Settings
$historyFile = Join-Path $PSScriptRoot 'StatsHistory.txt'
$outputImage = Join-Path $PSScriptRoot 'NewPlayersChart.png'
$webhookUrl  = $env:DISCORD_WEBHOOK
$logoUrl     = 'https://i.imgur.com/Zdufcwx.jpeg'

if (-not (Test-Path $historyFile)) {
    Write-Error "StatsHistory.txt not found at $historyFile"
    exit 1
}

# 1. Load & sort all logs
$entries = Get-Content $historyFile | ForEach-Object {
    $p = $_ -split ','
    [PSCustomObject]@{
        DateTime = [DateTime]::ParseExact($p[0], 'yyyy-MM-dd HH:mm', $null)
        Total    = [int]$p[2]
    }
} | Sort-Object DateTime

if ($entries.Count -eq 0) {
    Write-Error "No log entries found."
    exit 1
}

# 2. Determine dynamic window (max 7 days back)
$latestTime   = $entries[-1].DateTime
$earliestTime = $entries[0].DateTime
$minStart     = $latestTime.AddDays(-7)

$startTime = if ($earliestTime -lt $minStart) { $minStart } else { $earliestTime }
$endTime   = $latestTime

# 3. Slot sizing
$totalDuration = $endTime - $startTime
$slotDuration  = [TimeSpan]::FromTicks($totalDuration.Ticks / $Slots)

# 4. Build cumulative dataset & labels
$labels     = @()
$data       = @()
$cumulative = 0

for ($i = 0; $i -lt $Slots; $i++) {
    $bStart = $startTime + ($slotDuration * $i)
    $bEnd   = $startTime + ($slotDuration * ($i + 1))

    # log at or before bucket start
    $prevLog = $entries |
        Where-Object { $_.DateTime -le $bStart } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1
    if (-not $prevLog) { $prevLog = $entries | Select-Object -First 1 }

    # log at or before bucket end
    $endLog = $entries |
        Where-Object { $_.DateTime -le $bEnd } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1

    $joined = 0
    if ($endLog) { $joined = $endLog.Total - $prevLog.Total }

    # accumulate only positives
    if ($joined -gt 0) { $cumulative += $joined }

    # choose label format
    if ($totalDuration.TotalDays -gt 1) {
        $labels += $bStart.ToString('MM-dd HH:mm')
    } else {
        $labels += $bStart.ToString('HH:mm')
    }

    $data += $cumulative
}

# 5. QuickChart config (blue bars, datalabels)
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
                formatter = 'function(val){return val;}'
                font      = @{ size = 12 }
            }
        }
        layout = @{ padding = @{ top = 20; bottom = 10 } }
    }
} | ConvertTo-Json -Depth 6

# 6. Generate chart & apply watermark
$encoded  = [System.Net.WebUtility]::UrlEncode($chartConfig)
$chartUrl = "https://quickchart.io/chart?c=$encoded&width=900&height=400&format=png&plugins=chartjs-plugin-datalabels"
$wmUrl    = "https://quickchart.io/watermark?mainImageUrl=$([uri]::EscapeDataString($chartUrl))&markImageUrl=$([uri]::EscapeDataString($logoUrl))&position=topRight&opacity=0.5&imageWidth=40&margin=0"

Invoke-WebRequest -Uri $wmUrl -OutFile $outputImage

# 7. Post to Discord (embed only, keeps “Spy Drone”)
$payload = @{ embeds = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } }) }
$payloadJson = $payload | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $webhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
        payload_json = $payloadJson
        file1        = Get-Item $outputImage
    }

Write-Host "✅ Chart posted: $Slots slots over $([math]::Round($totalDuration.TotalDays,2)) days (cumulative = $cumulative)."
