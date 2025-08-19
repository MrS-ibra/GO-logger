try {
    Write-Host "Starting scrape..."

    $url = "https://www.playgenerals.online/players"
    Write-Host "Requesting: $url"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    Write-Host "Response received."

    $html = $response.Content
    Write-Host "HTML length: $($html.Length)"

    # Dump raw HTML for inspection
    $html | Out-File -FilePath "raw_dump.txt"
    Write-Host "Raw HTML dumped to raw_dump.txt"

    # Extract lifetime player count
    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()
    Write-Host "Extracted count: $count"

    # Extract online player count
    $online = if ($html -match "There are (\d+) online player") {
        $matches[1]
    } else {
        "?"
    }
    Write-Host "Extracted online: $online"

    $logPath = "lifetime_log.txt"
    $peakLog = "peak_log.txt"
    $today = Get-Date -Format "yyyy-MM-dd"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $timeOnly = Get-Date -Format "HH:mm"

    # Read previous log line
    $previousLine = if (Test-Path $logPath) {
        Get-Content $logPath | Where-Object { $_ -match "Total Lifetime Players:" } | Select-Object -Last 1
    } else {
        ""
    }

    $previousCount = if ($previousLine -match "Total Lifetime Players:") {
        ($previousLine -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
    } else {
        $count
    }

    $marker = if ([int]$count -gt [int]$previousCount) { " ⬆️📈" } else { "" }
    $line = "$timestamp  —  Total Lifetime Players: $count$marker"
    $onlineLine = "There are $online online players now. 🎮"

    # Append main log lines
    Add-Content -Path $logPath -Value $line
    Add-Content -Path $logPath -Value $onlineLine

    # Track peak hour
    Add-Content -Path $peakLog -Value "$timestamp,$online"

    # Remove previous summary and peak lines
    $logContent = Get-Content $logPath
    $filteredLog = $logContent | Where-Object {
        ($_ -notmatch "^A total of \d+ players have joined Generals Online today.") -and
        ($_ -notmatch "^Peak hour today was at \d{2}:\d{2} with \d+ players online.")
    }
    $filteredLog | Set-Content $logPath

    # Recalculate today's summary
    $todayLines = $filteredLog | Where-Object {
        $_ -match "^$today\s+\d{2}:\d{2}\s+—\s+Total Lifetime Players:"
    }

    if ($todayLines.Count -ge 2) {
        $firstToday = ($todayLines[0] -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
        $lastToday  = ($todayLines[-1] -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
        $joinedToday = [int]$lastToday - [int]$firstToday
        $summary = "A total of $joinedToday players have joined Generals Online today."
    } else {
        $summary = "A total of 0 players have joined Generals Online today."
    }

    # Recalculate peak hour
    $peakTodayLines = Get-Content $peakLog | Where-Object { $_ -match "^$today" }
    $peakEntry = $peakTodayLines | Sort-Object {
        ($_ -split ",")[1] -as [int]
    } -Descending | Select-Object -First 1

    if ($peakEntry) {
        $peakTime = ($peakEntry -split ",")[0] -split " " | Select-Object -Last 1
        $peakCount = ($peakEntry -split ",")[1]
        $peakLine = "Peak time today was at $peakTime GMT with $peakCount players online. 🕐 "
    } else {
        $peakLine = "Peak hour today was not recorded. ❔"
    }

    # Append summary and peak lines last
    Add-Content -Path $logPath -Value $summary
    Add-Content -Path $logPath -Value $peakLine

    Write-Host $summary
    Write-Host $peakLine
}
catch {
    Write-Host "ERROR OCCURRED:"
    Write-Host $_.Exception.Message
    exit 8
}
