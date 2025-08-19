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

    # Get today's entries from peak log
    $peakTodayLines = Get-Content $peakLog | Where-Object { $_ -match "^$today" }

    # Calculate peak hour
    $peakEntry = $peakTodayLines | Sort-Object {
        ($_ -split ",")[1] -as [int]
    } -Descending | Select-Object -First 1

    if ($peakEntry) {
        $peakTime = ($peakEntry -split ",")[0] -split " " | Select-Object -Last 1
        $peakCount = ($peakEntry -split ",")[1]
        $peakLine = "Peak time today was at $peakTime GMT with $peakCount players online. 🕐"
    } else {
        $peakLine = "Peak time today was not recorded. ❔"
    }

    # Calculate daily growth from lifetime counts
    if ($peakTodayLines.Count -ge 2) {
        $firstToday = ($peakTodayLines[0] -split ",")[2]
        $lastToday  = ($peakTodayLines[-1] -split ",")[2]
        $joinedToday = [int]$lastToday - [int]$firstToday
        $summary = "A total of $joinedToday players have joined Generals Online today."
    } elseif ($peakTodayLines.Count -eq 1) {
        $firstToday = ($peakTodayLines[0] -split ",")[2]
        $joinedToday = 0
        $summary = "A total of 0 players have joined Generals Online today."
    } else {
        $firstToday = $count
        $joinedToday = 0
        $summary = "A total of 0 players have joined Generals Online today."
    }

    # Compare to previous run (not first of day)
    $previousCount = if ($peakTodayLines.Count -ge 2) {
        ($peakTodayLines[-2] -split ",")[2]
    } else {
        $count
    }

    $marker = if ([int]$count -gt [int]$previousCount) { " ⬆️📈" } else { "" }

    # Final log lines
    $line = "$timestamp  —  Total Lifetime Players: $count$marker"
    $onlineLine = "There are $online online players now. 🎮"

    # Overwrite log with clean block
    Set-Content -Path $logPath -Value @(
        $line
        $onlineLine
        $summary
        $peakLine
    )

    Write-Host $line
    Write-Host $onlineLine
    Write-Host $summary
    Write-Host $peakLine
}
catch {
    Write-Host "ERROR OCCURRED:"
    Write-Host $_.Exception.Message
    exit 8
}
