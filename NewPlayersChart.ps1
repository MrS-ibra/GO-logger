<#
.SYNOPSIS
  Builds a bar chart of new players over the last 7 days (or, if fewer daily logs exist,
  over the last N intervals based on raw logs), then sends it to Discord.

.PARAMETER Days
  Number of days to target for "daily" mode (default = 7).
#>
param(
    [int]$Days = 7
)

# Paths & settings
$historyFile = Join-Path $PSScriptRoot 'StatsHistory.txt'
$outputImage = Join-Path $PSScriptRoot 'NewPlayersChart.png'
$webhookUrl  = $env:DISCORD_WEBHOOK

if (-not (Test-Path $historyFile)) {
    Write-Error "StatsHistory.txt not found at $historyFile"
    exit 1
}

# 1. Load raw logs: "yyyy-MM-dd HH:mm,online,total"
$entries = Get-Content $historyFile | ForEach-Object {
    $parts = $_ -split ','
    [PSCustomObject]@{
        DateTime = [DateTime]::ParseExact($parts[0], 'yyyy-MM-dd HH:mm', $null)
        Total    = [int]$parts[2]
    }
} | Sort-Object DateTime

# 2. Extract last log per calendar day
$dailyTotals = $entries `
  | Group-Object { $_.DateTime.Date } `
  | ForEach-Object { $_.Group | Sort-Object DateTime | Select-Object -Last 1 } `
  | Sort-Object DateTime

# 3. Decide whether to use daily buckets or raw‐interval buckets
if ($dailyTotals.Count - 1 -ge $Days) {
    Write-Host "Using daily buckets (found $($dailyTotals.Count) days of logs)."
    $window = $dailyTotals | Select-Object -Last ($Days + 1)
    $labelFormat = 'MM-dd'
}
else {
    Write-Host "Not enough full days ($($dailyTotals.Count)); using raw‐interval buckets."
    # Determine how many raw records we need: Days+1 or as many as exist
    $countNeeded = [math]::Min($entries.Count, $Days + 1)
    $window = $entries | Select-Object -Last $countNeeded
    $labelFormat = 'MM-dd HH:mm'
}

# 4. Build labels & compute delta between adjacent window entries
$labels = @()
$data   = @()

for ($i = 1; $i -lt $window.Count; $i++) {
    $prev   = $window[$i - 1]
    $cur    = $window[$i]
    $joined = $cur.Total - $prev.Total

    $labels += $cur.DateTime.ToString($labelFormat)
    $data   += $joined
}

if ($labels.Count -eq 0) {
    Write-Warning "Only one (or zero) log entries available; chart will be empty."
}

# 5. Build QuickChart JSON payload
$chart = @{
    type = 'bar'
    data = @{
        labels   = $labels
        datasets = @(@{
            label           = 'New Players Joined'
            data            = $data
            backgroundColor = 'rgba(54, 162, 235, 0.6)'
        })
    }
    options = @{
        title = @{
            display = $true
            text    = "New Players Joined (Last $($labels.Count) Interval(s))"
        }
        scales = @{
            yAxes = @(@{ ticks = @{ beginAtZero = $true } })
        }
    }
} | ConvertTo-Json -Depth 5

# 6. Download chart PNG
$encoded = [System.Net.WebUtility]::UrlEncode($chart)
$uri     = "https://quickchart.io/chart?c=$encoded"
Invoke-WebRequest -Uri $uri -OutFile $outputImage

# 7. Post to Discord
$payload = @{
    username = 'GO-Logger'
    content  = "Here’s the new-player join chart for the last $($labels.Count) interval(s):"
    embeds   = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } })
} | ConvertTo-Json

Invoke-RestMethod -Uri $webhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
        payload_json = $payload
        file1        = Get-Item $outputImage
    }

Write-Host "Chart sent successfully with $($labels.Count) bar(s)."
