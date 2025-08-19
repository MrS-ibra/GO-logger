try {
    Write-Host "Starting scrape..."

    $url = "https://www.playgenerals.online/players"
    Write-Host "Requesting: $url"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    Write-Host "Response received."

    $html = $response.Content
    Write-Host "HTML length: $($html.Length)"

    $html | Out-File -FilePath "raw_dump.txt"
    Write-Host "Raw HTML dumped to raw_dump.txt"

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()
    Write-Host "Extracted count: $count"

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

    # Append to peak log with lifetime count
    Add-Content -Path $peakLog -Value "$timestamp,$online,$count"

    # Get today's entries with valid lifetime counts
    $peakTodayLines = Get-Content $peakLog | Where-Object {
        $_ -match "^$today" -and ($_ -split ",").Count -ge 3
    }

    # Calculate peak hour
    $peakEntry = $peakTodayLines | Sort-Object {
        ($_ -split ",")[1] -as [int]
    } -Descending | Select-Object -First 1

    if ($peakEntry) {
        $peakTime = ($peakEntry -split ",")[0] -split " " | Select-Object -Last 1
        $peakCount = ($peakEntry -split ",")[1]
        $peakLine = "🔥 Peak time today:  **$peakTime GMT** with **$peakCount players**"
    } else {
        $peakLine = "🔥 Peak time today:  **not recorded** ❔"
    }

    # Calculate daily growth from lifetime counts
    if ($peakTodayLines.Count -ge 2) {
        $firstToday = [int](($peakTodayLines[0] -split ",")[2])
        $lastToday  = [int](($peakTodayLines[-1] -split ",")[2])
        $joinedToday = $lastToday - $firstToday
        $summary = "📈 Joined Today:       **+$joinedToday**"
    } elseif ($peakTodayLines.Count -eq 1) {
        $firstToday = [int](($peakTodayLines[0] -split ",")[2])
        $joinedToday = 0
        $summary = "📈 Joined Today:       **+0**"
    } else {
        $firstToday = [int]$count
        $joinedToday = 0
        $summary = "📈 Joined Today:       **+0**"
    }

    # Compare to previous run (not first of day)
    $previousCount = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-2] -split ",")[2])
    } else {
        [int]$count
    }

    $marker = if ([int]$count -gt $previousCount) { " ⬆️📈" } else { "" }

    # Final log lines (6 total)
    $line1 = "━━━━━━━━━━━━━━━━━━━━━━"
    $line2 = "📅 Time:                         $timeOnly GMT"
    $line3 = "👥 Lifetime players:   **$count**$marker"
    $line4 = "🎮 Online:                   **$online**"
    $line5 = $summary
    $line6 = $peakLine
    $line7 = "━━━━━━━━━━━━━━━━━━━━━━"

    # Overwrite log with leaderboard block
    Set-Content -Path $logPath -Value @(
        $line1
        $line2
        $line3
        $line4
        $line5
        $line6
        $line7
    )

    Write-Host $line2
    Write-Host $line3
    Write-Host $line4
    Write-Host $line5
    Write-Host $line6
}
catch {
    Write-Host "ERROR OCCURRED:"
    Write-Host $_.Exception.Message
    exit 8
}
