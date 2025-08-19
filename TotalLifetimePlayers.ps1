try {
    Write-Host "Starting scrape..."

    $url = "https://www.playgenerals.online/players"
    Write-Host "Requesting: $url"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    Write-Host "Response received."

    $html = $response.Content
    Write-Host "HTML length: $($html.Length)"

    # Dump raw HTML for inspection (overwrites each run)
    $html | Out-File -FilePath "raw_dump.txt"
    Write-Host "Raw HTML dumped to raw_dump.txt"

    # Extract lifetime player count
    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()
    Write-Host "Extracted count: $count"

    # Precise extraction of online player count
    $online = if ($html -match "There are (\d+) online player") {
        $matches[1]
    } else {
        "?"
    }
    Write-Host "Extracted online: $online"

    $logPath = "lifetime_log.txt"
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
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $line = "$timestamp  —  Total Lifetime Players: $count$marker"
    $onlineLine = "There are $online online players now. 🎮"

    Write-Host "Log line: $line"
    Add-Content -Path $logPath -Value $line
    Add-Content -Path $logPath -Value $onlineLine

    # Check and log peak online count
    $today = Get-Date -Format "yyyy-MM-dd"
    $logLinesToday = if (Test-Path $logPath) {
        Get-Content $logPath | Where-Object { $_ -match "^$today" -and $_ -match "online players now" }
    } else {
        @()
    }

    $previousPeak = ($logLinesToday | ForEach-Object {
        if ($_ -match "There are (\d+) online players now") { [int]$matches[1] } else { 0 }
    }) | Sort-Object -Descending | Select-Object -First 1

    if ([int]$online -gt $previousPeak) {
        $peakTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
        $peakLine = "🕒 Peak Online Today: $online players at $peakTimestamp 🔥"
        Add-Content -Path $logPath -Value $peakLine
        Write-Host $peakLine
    }

    # Calculate today's total growth
    $todayLines = Get-Content $logPath | Where-Object {
        $_ -match "^$today\s+\d{2}:\d{2}\s+—\s+Total Lifetime Players:"
    }

    if ($todayLines.Count -ge 2) {
        $firstToday = ($todayLines[0] -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
        $lastToday  = ($todayLines[-1] -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
        $joinedToday = [int]$lastToday - [int]$firstToday
        $summary = "A total of $joinedToday players have joined Generals Online today. 🎉"
        Add-Content -Path $logPath -Value $summary
        Write-Host $summary
    }

    Write-Host "Log file updated successfully."
}
catch {
    Write-Host "ERROR OCCURRED:"
    Write-Host $_.Exception.Message
    exit 8
}
