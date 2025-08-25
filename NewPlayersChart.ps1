<#
.SYNOPSIS
  Builds a bar chart of new players over the last N days (daily) 
  or, if fewer than N+1 days exist, over the last N raw log intervals.
  Applies a watermark logo, and dynamic labels
.PARAMETER Days
  Number of days to target for daily mode (default = 7).
#>
param(
  [int]$Days = 7
)

# Paths & Settings
$historyFile = Join-Path $PSScriptRoot 'StatsHistory.txt'
$outputImage = Join-Path $PSScriptRoot 'NewPlayersChart.png'
$webhookUrl  = $env:DISCORD_WEBHOOK

if (-not (Test-Path $historyFile)) {
  Write-Error "StatsHistory.txt not found at $historyFile"
  exit 1
}

# 1. Load raw logs ("yyyy-MM-dd HH:mm,online,total")
$entries = Get-Content $historyFile | ForEach-Object {
  $p = $_ -split ','
  [PSCustomObject]@{
    DateTime = [DateTime]::ParseExact($p[0], 'yyyy-MM-dd HH:mm', $null)
    Total    = [int]$p[2]
  }
} | Sort-Object DateTime

# 2. Collapse to last record per calendar day
$dailyTotals = $entries `
  | Group-Object { $_.DateTime.Date } `
  | ForEach-Object { $_.Group | Sort-Object DateTime | Select-Object -Last 1 } `
  | Sort-Object DateTime

# 3. Choose bucket mode
$usingDaily = ($dailyTotals.Count - 1 -ge $Days)
if ($usingDaily) {
  Write-Host "Using daily buckets (found $($dailyTotals.Count) days of logs)."
  $window      = $dailyTotals | Select-Object -Last ($Days + 1)
  $labelFormat = 'MM-dd'
  $chartTitle  = "New Players Joined — Last $Days Days"
}
else {
  Write-Host "Not enough full days ($($dailyTotals.Count)); using raw-interval buckets."
  $countNeeded = [math]::Min($entries.Count, $Days + 1)
  $window      = $entries | Select-Object -Last $countNeeded
  $labelFormat = 'HH:mm'
  $intervals   = $window.Count - 1
  $chartTitle  = "New Players Joined — Last $intervals Entries"
}

# 4. Build labels & compute per-bucket joins
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

# 5. QuickChart configuration (bars + watermark logo)
$chartConfig = @{
  type = 'bar'
  data = @{
    labels   = $labels
    datasets = @(@{
      label           = 'New Players'
      data            = $data
      backgroundColor = 'rgba(54,162,235,0.6)'
    })
  }
  options = @{
    title = @{
      display = $true
      text    = $chartTitle
      fontSize = 18
    }
    legend = @{
      display = $false
    }
    scales = @{
      xAxes = @(@{
        ticks = @{ autoSkip = $false }
        gridLines = @{ display = $false }
      })
      yAxes = @(@{
        ticks = @{ beginAtZero = $true }
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
      padding = @{ top = 30 }
    }
  }
} | ConvertTo-Json -Depth 6

# 6. Download the chart PNG
$encoded = [System.Net.WebUtility]::UrlEncode($chartConfig)
$uri     = "https://quickchart.io/chart?c=$encoded&width=600&height=300&format=png"
Invoke-WebRequest -Uri $uri -OutFile $outputImage

# 7. Send to Discord
$payload = @{
  content = "**$chartTitle**"
  embeds  = @(@{ image = @{ url = 'attachment://NewPlayersChart.png' } })
}
$payloadJson = $payload | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri $webhookUrl `
  -Method Post `
  -ContentType 'multipart/form-data' `
  -Form @{
    payload_json = $payloadJson
    file1        = Get-Item $outputImage
  }

Write-Host "Chart sent successfully with $($labels.Count) bar(s)."
