<#
.SYNOPSIS
  Builds a bar chart of new-player joins over the last available logs (max 7 days),
  dividing the range into a fixed number of slots, and posts it to Discord.
.PARAMETER Slots
  Number of time buckets (bars) to display.
#>
param(
    [int]$Slots = 12
)

# Paths & Settings
$historyFile = Join-Path $PSScriptRoot 'StatsHistory.txt'
$outputImage = Join-Path $PSScriptRoot 'NewPlayersChart.png'
$webhookUrl  = $env:DISCORD_WEBHOOK

if (-not (Test-Path $historyFile)) {
    Write-Error "StatsHistory.txt not found at $historyFile"
    exit 1
}

# 1. Load all logs, sort by timestamp
$entries = Get-Content $historyFile | ForEach-Object {
    $p = $_ -split ','
    [PSCustomObject]@{
        DateTime = [DateTime]::ParseExact($p[0], 'yyyy-MM-dd HH:mm', $null)
        Total    = [int]$p[2]
    }
} | Sort-Object DateTime

if (-not $entries) {
    Write-Error "No log entries found."
    exit 1
}

# 2. Determine dynamic time range (max 7 days)
$latestTime = $entries[-1].DateTime
$earliestTime = $entries[0].DateTime
$minStart = $latestTime.AddDays(-7)

if ($earliestTime -lt $minStart) {
    $startTime = $minStart
} else {
    $startTime = $earliestTime
}

$endTime = $latestTime

# 3. Calculate slot duration
$totalDuration = $endTime - $startTime
$slotDuration  = [TimeSpan]::FromTicks($totalDuration.Ticks / $Slots)

# 4. Build labels & compute joins per slot
$labels = @()
$data   = @()

for ($i = 0; $i -lt $Slots; $i++) {
    $bStart = $startTime + ($slotDuration * $i)
    $bEnd   = $startTime + ($slotDuration * ($i + 1))

    # Find the last log before or at the start of the bucket
    $prevLog = $entries |
        Where-Object { $_.DateTime -le $bStart } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1

    if (-not $prevLog) { $prevLog = $entries | Select-Object -First 1 }

    # Find the last log before or at the end of the bucket
    $endLog = $entries |
        Where-Object { $_.DateTime -le $bEnd } |
        Sort-Object DateTime -Descending |
        Select-Object -First 1

    $joined = 0
    if ($endLog) {
        $joined = [Math]::Max(0, $endLog.Total - $prevLog.Total)
    }

    # Label format depends on total range
    if ($totalDuration.TotalDays -gt 1) {
        $labels += $bStart.ToString('MM-dd HH:mm')
    } else {
        $labels += $bStart.ToString('HH:mm')
    }

    $data += $joined
}

# 5. QuickChart configuration (red bars, no title, watermark logo)
$chartConfig = @{
    type = 'bar'
    data = @{
        labels   = $labels
        datasets = @(@{
            data            = $data
            backgroundColor = 'rgba(255,99,132,0.6)'
        })
    }
    options = @{
        title  = @{ display = $false }
        legend = @{ display = $false }
        scales = @{
            xAxes = @(@{
                ticks     = @{ autoSkip = $false }
                gridLines = @{ display = $false }
            })
            yAxes = @(@{
                ticks     = @{ beginAtZero = $true }
                gridLines = @{ color = 'rgba(200,200,200,0.2)' }
            })
        }
        plugins = @{
            watermark = @{
                image    = 'https://i.imgur.com/Zdufcwx.jpeg'
                position = 'topRight'
                width    = 40
                opacity  = 0.5
            }
        }
        layout = @{
            padding = @{ top = 10 }
        }
    }
} | ConvertTo-Json -Depth 6

# 6. Download chart PNG
$encoded = [System.Net.WebUtility]::UrlEncode($chartConfig)
$uri     = "https://quickchart.io/chart?c=$encoded&width=800&height=400&format=png"
Invoke-WebRequest -Uri $uri -OutFile $outputImage

# 7. Send to Discord
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

Write-Host "Chart sent successfully with $Slots slot(s) over $([math]::Round($totalDuration.TotalDays,2)) day(s)."
