#!/usr/bin/env pwsh
# Generates a bar chart of peak online players per day over last 15 days, and posts to Discord

param(
  [string]$StatsFile  = 'StatsHistory.txt',
  [string]$ChartFile  = 'PeakOnlineChart.png',
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
      $dt     = [DateTime]$parts[0]
      $online = [int]$parts[1]
    } catch { return }
    [PSCustomObject]@{ Date = $dt.Date; Time = $dt; Online = $online }
  }

$labels = @()
$data   = @()

$latestDate = ($entries | Sort-Object Date -Descending | Select-Object -First 1).Date
$days = 0..19 | ForEach-Object { $latestDate.AddDays(-$_) } | Sort-Object

foreach ($day in $days) {
  $suffix = Get-OrdinalSuffix $day.Day
  $label  = "$($day.ToString('MMM')) $($day.Day)$suffix"
  $group  = $entries | Where-Object { $_.Date -eq $day }

  if ($group.Count -gt 0) {
    $peak = ($group | Sort-Object Online -Descending | Select-Object -First 1).Online
  } else {
    $peak = 0
  }

  $labels += $label
  $data   += $peak
}

  $chartSpec = @{
    type = 'bar'
    data = @{
      labels   = $labels
      datasets = @(@{
        data            = $data
        backgroundColor = 'rgba(0,200,100,0.6)'
        borderColor     = 'rgba(0,200,100,0.9)'
        borderWidth     = 1
      })
    }
    options = @{
      title = @{
        display   = $true
        text      = 'Peak Online Players — last 20 days'
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
          font   = @{ size = 12 }
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

  Write-Host "✅ Posted peak chart."
}
catch {
  Write-Error "❌ Failed: $($_.Exception.Message)"
  exit 1
}
