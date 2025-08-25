#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Cumulative bar chart of new-player joins over the last available logs
  (up to 7 days back), split into a minimum of 20 slots, shows data labels,
  overlays your Imgur logo via Chart.js watermark plugin, and posts to Discord.
.PARAMETER Slots
  Number of bars to show; default is 20.
#>
param(
    [int]   $Slots       = 20,
    [string]$HistoryFile = 'StatsHistory.txt',
    [string]$ChartFile   = 'NewPlayersChart.png',
    [string]$LogoUrl     = 'https://i.imgur.com/Zdufcwx.jpeg',
    [string]$WebhookUrl  = $env:DISCORD_WEBHOOK
)

# 1. Load & sort history
if (-not (Test-Path $HistoryFile)) { throw "StatsHistory.txt not found" }
$entries = Get-Content $HistoryFile | ForEach-Object {
    $p = $_ -split ','
    [PSCustomObject]@{
        DateTime = [DateTime]::ParseExact($p[0], 'yyyy-MM-dd HH:mm', $null)
        Total    = [int]$p[2]
    }
} | Sort-Object DateTime
if ($entries.Count -eq 0) { throw "No log entries found." }

# 2. Determine window (cap at 7 days)
$latest        = $entries[-1].DateTime
$earliest      = $entries[0].DateTime
$minAllowed    = $latest.AddDays(-7)
$startTime     = if ($earliest -lt $minAllowed) { $minAllowed } else { $earliest }
$totalDuration = $latest - $startTime

# 3. Slot duration
$slotDuration = [TimeSpan]::FromTicks($totalDuration.Ticks / $Slots)

# 4. Build cumulative data + labels
$labels     = @(); $data = @(); $cumulative = 0

for ($i = 0; $i -lt $Slots; $i++) {
    $bStart = $startTime + ($slotDuration * $i)
    $bEnd   = $startTime + ($slotDuration * ($i + 1))

    $prevLog = $entries |
        Where-Object { $_.DateTime -le $bStart } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1
    if (-not $prevLog) { $prevLog = $entries[0] }

    $endLog = $entries |
        Where-Object { $_.DateTime -le $bEnd } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1

    $joined = if ($endLog) { $endLog.Total - $prevLog.Total } else { 0 }
    if ($joined -gt 0) { $cumulative += $joined }

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
                align     = 'start'
                formatter = 'function(v){return v;}'
                font      = @{ size = 12 }
            }
            watermark = @{
                image    = $LogoUrl
                position = 'topRight'
                width    = 40
                opacity  = 1.0
            }
        }
        layout = @{ padding = @{ top = 30; bottom = 10 } }
    }
} | ConvertTo-Json -Depth 6

# 6. Render chart
$enc   = [uri]::EscapeDataString($chartConfig)
$plugs = 'chartjs-plugin-datalabels,chartjs-plugin-watermark'
$uri   = "https://quickchart.io/chart?c=$enc&plugins=$plugs"
Invoke-WebRequest -Uri $uri -OutFile $ChartFile -ErrorAction Stop

# 7. Post to Discord (embed only)
$payload = @{ embeds = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } }) }
$payloadJson = $payload | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $WebhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
        payload_json = $payloadJson
        file1        = Get-Item $ChartFile
    }

Write-Host "✅ Chart posted with logo opacity 1.0 and default dimensions."
