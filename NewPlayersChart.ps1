<#
.SYNOPSIS
  Reads StatsHistory.txt, calculates daily joins for the last N days, generates a bar chart, and sends it to Discord.

.PARAMETER Days
  Number of days to include in the chart (default is 7).
#>
param(
    [int]$Days = 7
)

# Paths and settings
$historyFile   = Join-Path $PSScriptRoot 'StatsHistory.txt'
$outputImage   = Join-Path $PSScriptRoot 'JoinChart.png'
$webhookUrl    = $env:DISCORD_WEBHOOK

if (-not (Test-Path $historyFile)) {
    Write-Error "StatsHistory.txt not found at $historyFile"
    exit 1
}

# 1. Load and parse history lines: "yyyy-MM-dd HH:mm,online,total"
$entries = Get-Content $historyFile | ForEach-Object {
    $parts = $_ -split ','
    [PSCustomObject]@{
        DateTime = [DateTime]::ParseExact($parts[0], 'yyyy-MM-dd HH:mm', $null)
        Total    = [int]$parts[2]
    }
}

# 2. Group by date, pick last log of each day
$dailyTotals = $entries |
    Group-Object { $_.DateTime.Date } |
    ForEach-Object {
        $_.Group | Sort-Object DateTime | Select-Object -Last 1
    } |
    Sort-Object DateTime

# 3. Select window of Days + 1 entries (to calculate diffs)
$window = $dailyTotals | Select-Object -Last ($Days + 1)

if ($window.Count -lt ($Days + 1)) {
    Write-Error "Insufficient data: found $($window.Count) days, need $($Days + 1)"
    exit 1
}

# 4. Build labels (MM-dd) and compute joined counts
$labels = @()
$data   = @()

for ($i = 1; $i -lt $window.Count; $i++) {
    $prev = $window[$i - 1]
    $cur  = $window[$i]
    $joined = $cur.Total - $prev.Total

    $labels += $cur.DateTime.ToString('MM-dd')
    $data   += $joined
}

# 5. Construct QuickChart chart configuration
$chartConfig = @{
    type = 'bar'
    data = @{
        labels   = $labels
        datasets = @(@{
            label           = 'Players Joined'
            data            = $data
            backgroundColor = 'rgba(54, 162, 235, 0.6)'
        })
    }
    options = @{
        title = @{
            display = $true
            text    = "Daily Players Joined (Last $Days Days)"
        }
        scales = @{
            yAxes = @(@{ ticks = @{ beginAtZero = $true } })
        }
    }
} | ConvertTo-Json -Depth 5

# 6. Download chart as PNG
$encodedConfig = [System.Web.HttpUtility]::UrlEncode($chartConfig)
$chartUrl      = "https://quickchart.io/chart?c=$encodedConfig"
Invoke-WebRequest -Uri $chartUrl -OutFile $outputImage

# 7. Send chart to Discord via webhook
$payload = @{
    username = 'GO-Logger'
    content  = "Here’s the new-player join chart for the last $Days days:"
    embeds   = @(@{ image = @{ url = 'attachment://JoinChart.png' } })
} | ConvertTo-Json

Invoke-RestMethod -Uri $webhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
        payload_json = $payload
        file1        = Get-Item $outputImage
    }

Write-Host "Chart sent successfully."
