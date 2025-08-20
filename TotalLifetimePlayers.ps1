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

    # Updated online player extraction
    $online = if ($html -match "There are (\d+) online player") {
        $matches[1]
    } elseif ($html -match "There are no players online") {
        "0"
    } else {
        "No idea"
    }
    Write-Host "Extracted online: $online"

    $logPath = "lifetime_log.txt"
    $peakLog = "peak_log.txt"
    $today = Get-Date -Format "yyyy-MM-dd"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $timeOnly = Get-Date -Format "HH:mm"

    # Trim peak_log.txt if it exceeds 150 lines
    $maxLines = 150
    $trimCount = 25
    if (Test-Path $peakLog) {
        $logLines = Get-Content $peakLog
        if ($logLines.Count -ge $maxLines) {
            $logLines = $logLines[$trimCount..($logLines.Count - 1)]
            Set-Content -Path $peakLog -Value $logLines
        }
    }

    # Append new entry
    Add-Content -Path $peakLog -Value "$timestamp,$online,$count"

    # Cache today's entries
    $peakLogLines = Get-Content $peakLog
    $peakTodayLines = $peakLogLines | Where-Object {
        $_ -match "^$today" -and ($_ -split ",").Count -ge 3
    }

    # Peak extraction
    $peakEntry = $peakTodayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1
    if ($peakEntry) {
        $peakTime, $peakCount = ($peakEntry -split ",")[0,1]
        $peakTime = $peakTime -split " " | Select-Object -Last 1
        $peakLine = "**Peak time today:** $peakTime GMT with $peakCount players"
    } else {
        $peakLine = "**Peak time today:** not recorded ❔"
    }

    # joinedToday logic
    $joinedToday = 0
    if ($peakTodayLines.Count -ge 2) {
        $firstToday = [int](($peakTodayLines[0] -split ",")[2])
        $lastToday  = [int](($peakTodayLines[-1] -split ",")[2])
        $joinedToday = $lastToday - $firstToday
    } elseif ($peakTodayLines.Count -eq 1) {
        $firstToday = [int](($peakTodayLines[0] -split ",")[2])
    } else {
        $firstToday = [int]$count
    }

    $previousCount = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-2] -split ",")[2])
    } else {
        [int]$count
    }

    $marker = if ([int]$count -gt $previousCount) { " ⬆️" } else { "" }

    $line1 = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    $line2 = "**Time (GMT):** $timeOnly"
    $line3 = "**Lifetime players:** $count$marker"
    $line4 = "**Online players:** $online"
    $line5 = "**Joined Today:** +$joinedToday"
    $line6 = $peakLine
    $line7 = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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

    $logPath = "lifetime_log.txt"
    $timeOnly = Get-Date -Format "HH:mm"
    $errorMsg = $_.Exception.Message -replace "`r`n", " " -replace "`n", " "

    Set-Content -Path $logPath -Value @(
        "━━━━━━━━━━━━━━━━━━━━━━"
        "   **Time:** $timeOnly GMT"
        "❌ **Scrape failed:** site unreachable or error occurred"
        "   **Error:** $errorMsg"
        "━━━━━━━━━━━━━━━━━━━━━━"
    )

    exit 8
}
