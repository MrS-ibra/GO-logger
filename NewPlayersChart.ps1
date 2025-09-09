#!/usr/bin/env pwsh
# Generates a cumulative bar chart of new players over last 7 days with transparency, overlays logo, posts to Discord

param(
  [int]   $Slots      = 20,
  [string]$StatsFile  = 'StatsHistory.txt',
  [string]$ChartFile  = 'NewPlayersChart.png',
  [string]$LogoUrl    = 'https://i.imgur.com/Zo9RY7b.png',
  [string]$LogoFile   = 'logo.png',
  [string]$WebhookUrl = $env:DISCORD_WEBHOOK
)

function Get-OrdinalSuffix($n) {
  switch ($n % 100) { { $_ -in 11..13 } { return 'th' } }
  switch ($n % 10) {
    1 { 'st'; break }
    2 { 'nd'; break }
    3 { 'rd'; break }
    default { 'th'; break }
  }
}

try {
  if (-not (Test-Path $StatsFile)) { throw "Stats file not found: $StatsFile" }

  $entries = Get-Content $StatsFile | ForEach-Object {
    $parts = $_ -split ','
    try {
      $dt    = [DateTime]$parts[0]
      $total = [int]$parts[2]
    } catch { return }
    [PSCustomObject]@{ DateTime = $dt; Total = $total }
  } | Sort-Object DateTime

  if ($entries.Count -eq 0) { throw "No valid log entries found." }

  $latestTime   = $entries[-1].DateTime
  $startTime    = $latestTime.AddDays(-20)
  $windowSpan   = $latestTime - $startTime
  $slotDuration = [TimeSpan]::FromTicks($windowSpan.Ticks / $Slots)

  $labels     = @()
  $data       = @()
  $cumulative = 0

  for ($i = 0; $i -lt $Slots; $i++) {
    $bStart = $startTime + ($slotDuration * $i)
    $bEnd   = $startTime + ($slotDuration * ($i + 1))

    $prev = $entries | Where-Object { $_.DateTime -le $bStart } | Sort-Object DateTime -Descending | Select-Object -First 1
    if (-not $prev) { $prev = $entries[0] }

    $endLog = $entries | Where-Object { $_.DateTime -le $bEnd } | Sort-Object DateTime -Descending | Select-Object -First 1
    $joined = if ($endLog) { $endLog.Total - $prev.Total } else { 0 }
    if ($joined -gt 0) { $cumulative += $joined }

    $mon    = $bStart.ToString('MMM')
    $day    = $bStart.Day
    $suffix = Get-OrdinalSuffix $day
    $labels += "$mon $day$suffix"

    $data += $cumulative
  }

  $chartSpec = @{
    type = 'bar'
    data = @{
      labels   = $labels
      datasets = @(@{
        data            = $data
        backgroundColor = 'rgba(54,162,235,0.7)'  # transparent blue
        borderColor     = 'rgba(54,162,235,1)'    # solid border
        borderWidth     = 1
      })
    }
    options = @{
      title = @{
        display   = $true
        text      = 'New Players — last 20 days'
        font      = @{ size = 21 }
        fontColor = 'red'
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
          font   = @{ size = 10 }
        }
      }
      layout = @{ padding = @{ top = 30; bottom = 10 } }
    }
  } | ConvertTo-Json -Depth 6

  $cfgEncoded = [uri]::EscapeDataString($chartSpec)
  $chartUrl   = "https://quickchart.io/chart?c=$cfgEncoded&plugins=chartjs-plugin-datalabels"
  Invoke-WebRequest -Uri $chartUrl -OutFile $ChartFile -ErrorAction Stop

  Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoFile -ErrorAction Stop
  $magick = (Get-Command magick -ErrorAction SilentlyContinue)?.Source `
         ?? (Get-Command convert -ErrorAction SilentlyContinue)?.Source
  if (-not $magick) { throw "ImageMagick not found on PATH." }

  & $magick $ChartFile $LogoFile -gravity north -geometry 260x260+10+10 -composite $ChartFile

  $payload = @{ embeds = @(@{ image = @{ url = "attachment://$ChartFile" } }) }
  $pj      = $payload | ConvertTo-Json -Depth 5
  Invoke-RestMethod -Uri $WebhookUrl `
    -Method Post `
    -ContentType 'multipart/form-data' `
    -Form @{
      payload_json = $pj
      file1        = Get-Item $ChartFile
    }

  Write-Host "✅ Posted transparent chart (cumulative max = $cumulative)."
}
catch {
  Write-Error "❌ Failed: $($_.Exception.Message)"
  exit 1
}
