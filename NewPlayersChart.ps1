<#
.SYNOPSIS
  Reads StatsHistory.txt, calculates daily joins for the last N days (or fewer if not available),
  generates a bar chart via QuickChart, and posts it to Discord.
.PARAMETER Days
  Number of days to include in the chart (default 7).
#>
param(
    [int]$Days = 7
)

#–– Paths & Settings
$historyFile = Join-Path $PSScriptRoot 'StatsHistory.txt'
$outputImage = Join-Path $PSScriptRoot 'NewPlayersChart.png'
$webhookUrl  = $env:DISCORD_WEBHOOK

if (-not (Test-Path $historyFile)) {
    Write-Error "StatsHistory.txt not found at $historyFile"
    exit 1
}

#–– 1. Parse history ("yyyy-MM-dd HH:mm,online,total")
$entries = Get-Content $historyFile | ForEach-Object {
    $p = $_ -split ','
    [PSCustomObject]@{
        DateTime = [DateTime]::ParseExact($p[0], 'yyyy-MM-dd HH:mm', $null)
        Total    = [int]$p[2]
    }
}

#–– 2. Last log of each day, sorted
$dailyTotals = $entries |
  Group-Object { $_.DateTime.Date } |
  ForEach-Object { $_.Group | Sort DateTime | Select -Last 1 } |
  Sort DateTime

#–– 3. Grab up to Days+1 records (if fewer exist, it just returns what it has)
$window = $dailyTotals | Select-Object -Last ($Days + 1)

#–– 4. Build labels + daily-join counts
$labels = @()
$data   = @()

for ($i = 1; $i -lt $window.Count; $i++) {
    $prev   = $window[$i - 1]
    $cur    = $window[$i]
    $joined = $cur.Total - $prev.Total

    $labels += $cur.DateTime.ToString('MM-dd')
    $data   += $joined
}

if ($labels.Count -eq 0) {
    Write-Warning "Only one (or zero) day of data; chart will be empty."
}

#–– 5. QuickChart JSON
$chartConfig = @{
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
            text    = "Daily New Players (Last $($labels.Count) Day(s))"
        }
        scales = @{
            yAxes = @(@{ ticks = @{ beginAtZero = $true } })
        }
    }
} | ConvertTo-Json -Depth 5

#–– 6. Download the PNG
$enc = [System.Web.HttpUtility]::UrlEncode($chartConfig)
$uri = "https://quickchart.io/chart?c=$enc"
Invoke-WebRequest -Uri $uri -OutFile $outputImage

#–– 7. Post to Discord
$payload = @{
    username = 'GO-Logger'
    content  = "Here’s the new-player join chart for the last $($labels.Count) day(s):"
    embeds   = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } })
} | ConvertTo-Json

Invoke-RestMethod -Uri $webhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
        payload_json = $payload
        file1        = Get-Item $outputImage
    }

Write-Host "Chart sent with $($labels.Count) bar(s)."
