try {
    $url = "https://www.playgenerals.online/players"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    $html | Out-File -FilePath "raw_dump.txt"

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()

    $online = if ($html -match "There are (\d+) online player") {
        $matches[1]
    } else {
        "0"
    }

    $logPath = "lifetime_log.txt"
    $peakLog = "peak_log.txt"
    $today = Get-Date -Format "yyyy-MM-dd"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $timeOnly = Get-Date -Format "HH:mm"

    $maxLines = 150
    $trimCount = 25
    if (Test-Path $peakLog) {
        $logLines = Get-Content $peakLog
        if ($logLines.Count -ge $maxLines) {
            $logLines = $logLines[$trimCount..($logLines.Count - 1)]
            Set-Content -Path $peakLog -Value $logLines
        }
    }

    Add-Content -Path $peakLog -Value "$timestamp,$online,$count"

    $peakLogLines = Get-Content $peakLog
    $peakTodayLines = $peakLogLines | Where-Object {
        $_ -match "^$today" -and ($_ -split ",").Count -ge 3
    }

    $peakEntry = $peakTodayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1
    if ($peakEntry) {
        $peakTime, $peakCount = ($peakEntry -split ",")[0,1]
        $peakTime = $peakTime -split " " | Select-Object -Last 1
        $peakLine = "**Today’s peak**: $peakTime (GMT) — $peakCount players"
    } else {
        $peakLine = "**Today’s peak**: not recorded ❔"
    }

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

    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "**Total players**: $count$marker"
    $line3 = "**Online players**: $online"
    $line4 = "**New players today**: +$joinedToday"
    $line5 = $peakLine

    Set-Content -Path $logPath -Value @(
        $line1
        $line2
        $line3
        $line4
        $line5
    )
}
catch {
    $logPath = "lifetime_log.txt"
    $timeOnly = Get-Date -Format "HH:mm"
    $errorMsg = $_.Exception.Message -replace "`r`n", " " -replace "`n", " "

    Set-Content -Path $logPath -Value @(
        "━━━━━━━━━━━━━━━━━━━━━━"
        "   GMT Time: $timeOnly"
        "❌ Scrape failed: site unreachable or error occurred"
        "   Error: $errorMsg"
        "━━━━━━━━━━━━━━━━━━━━━━"
    )

    exit 8
}
