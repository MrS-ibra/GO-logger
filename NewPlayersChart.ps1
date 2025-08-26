#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Cumulative bar chart of new-player joins over the last up to 7 days,
  split into 20 slots (default), with smart labels, data labels,
  ImageMagick logo overlay (top-left), and Discord webhook posting.
.PARAMETER Slots
  How many time buckets (bars) to draw; default is 20.
#>
param(
  [int]   $Slots      = 20,
  [string]$StatsFile  = 'StatsHistory.txt',
  [string]$ChartFile  = 'NewPlayersChart.png',
  [string]$LogoUrl    = 'https://i.imgur.com/Zdufcwx.jpeg',
  [string]$LogoFile   = 'logo.png',
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK
)

# Helper: return “st”, “nd”, “rd”, or “th”
function Get-OrdinalSuffix($n) {
  switch ($n % 100) {
    { $_ -in 11..13 } { return 'th' }
  }
  switch ($n % 10) {
    1 { 'st'; break }
    2 { 'nd'; break }
    3 { 'rd'; break }
    default { 'th'; break }
  }
}

try {
  # 1. Load & sort your history entries
  if (-not (Test-Path $StatsFile)) { throw "Stats file not found: $StatsFile" }

  $entries = Get-Content $StatsFile | ForEach-Object {
    $parts = $_ -split ','
    try {
      $dt    = [DateTime]$parts[0]
      $total = [int]$parts[2]
    } catch {
      return    # skip malformed lines
    }
    [PSCustomObject]@{ DateTime = $dt; Total = $total }
  } | Sort-Object DateTime

  if ($entries.Count -eq 0) { throw "No valid log entries found." }

  # 2. Define your up-to-7-day window
  $latestTime   = $entries[-1].DateTime
  $earliestTime = $entries[0].DateTime
  $minStart     = $latestTime.AddDays(-7)
  $startTime    = if ($earliestTime -lt $minStart) { $minStart } else { $earliestTime }
  $windowSpan   = $latestTime - $startTime

  # 3. Compute slot duration
  $slotDuration = [TimeSpan]::FromTicks($windowSpan.Ticks / $Slots)

  # 4. Build cumulative data + labels
  $labels     = @()
  $data       = @()
  $cumulative = 0

  for ($i = 0; $i -lt $Slots; $i++) {
    $bStart = $startTime + ($slotDuration * $i)
    $bEnd   = $startTime + ($slotDuration * ($i + 1))

    # pick last log at or before bucket start
    $prev = $entries |
      Where-Object { $_.DateTime -le $bStart } |
      Sort-Object DateTime -Descending |
      Select-Object -First 1
    if (-not $prev) { $prev = $entries[0] }

    # pick last log at or before bucket end
    $endLog = $entries |
      Where-Object { $_.DateTime -le $bEnd } |
      Sort-Object DateTime -Descending |
      Select-Object -First 1

    # compute joins
    $joined = if ($endLog) { $endLog.Total - $prev.Total } else { 0 }
    if ($joined -gt 0) { $cumulative += $joined }

    # smart label:
    if ($windowSpan.TotalDays -gt 1) {
      # “Aug 25th, 8 PM”
      $mon   = $bStart.ToString('MMM')
      $day   = $bStart.Day
      $suffix= Get-OrdinalSuffix $day
      $time  = $bStart.ToString('h tt')
      $labels += "$mon $day$suffix, $time"
    } else {
      # “8 PM”
      $labels += $bStart.ToString('h tt')
    }

    $data += $cumulative
  }

  # 5. Build QuickChart payload
  $chartSpec = @{
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
          color  = 'white'
          anchor = 'end'
          align  = 'end'
          offset = -4
          font   = @{ size = 12 }
        }
      }
      layout = @{ padding = @{ top = 30; bottom = 10 } }
    }
  } | ConvertTo-Json -Depth 6

  # 6. Fetch chart PNG with datalabels plugin
  $cfgEncoded = [uri]::EscapeDataString($chartSpec)
  $chartUrl   = "https://quickchart.io/chart?c=$cfgEncoded&plugins=chartjs-plugin-datalabels"
  Invoke-WebRequest -Uri $chartUrl -OutFile $ChartFile -ErrorAction Stop

  # 7. Overlay your logo (top-left) via ImageMagick
  Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoFile -ErrorAction Stop
  $magick = (Get-Command magick -ErrorAction SilentlyContinue)?.Source `
         ?? (Get-Command convert -ErrorAction SilentlyContinue)?.Source
  if (-not $magick) { throw "ImageMagick not found on PATH." }
  & $magick $ChartFile $LogoFile -gravity northwest -geometry 260x260+10+10 -composite $ChartFile

  # 8. Send to Discord
  $payload = @{ embeds = @(@{ image = @{ url = "attachment://$ChartFile" } }) }
  $pj      = $payload | ConvertTo-Json -Depth 5
  Invoke-RestMethod -Uri $WebhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
      payload_json = $pj
      file1        = Get-Item $ChartFile
    }

  Write-Host "✅ Posted chart (cumulative max = $cumulative)."

} catch {
  Write-Error "❌ Failed: $($_.Exception.Message)"
  exit 1
}
