try {
    $url = "https://www.playgenerals.online/players"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    $html | Out-File -FilePath "raw_dump.txt"

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim() -replace '[^\d]', ''  # Remove non-digit characters

    $online = if ($html -match "There are (\d+) online player") { $matches[1] } else { "0" }

    $logPath = "lifetime_log.txt"
    $peakLog = "peak_log.txt"

    if (Test-Path $peakLog) {
        $logLines = Get-Content $peakLog
        if ($logLines.Count -ge 1500) {
            $logLines = $logLines[10..($logLines.Count - 1)]
            Set-Content -Path $peakLog -Value $logLines
        }
    }

    Add-Content -Path $peakLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    $peakLogLines = Get-Content $peakLog
    $today = Get-Date -Format "yyyy-MM-dd"
    $peakTodayLines = $peakLogLines | Where-Object {
        $_ -match "^$today" -and ($_ -split ",").Count -ge 3
    }

    $peakEntry = $peakTodayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1
    $peakLine = if ($peakEntry) {
        $peakTime, $peakCount = ($peakEntry -split ",")[0,1]
        $peakTime = $peakTime -split " " | Select-Object -Last 1
        "**Today’s peak**: $peakTime (GMT) — $peakCount players"
    } else {
        "**Today’s peak**: not recorded ❔"
    }

    $joinedToday = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-1] -split ",")[2]) - [int](($peakTodayLines[0] -split ",")[2])
    } else { 0 }

    $previousCount = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-2] -split ",")[2])
    } else {
        [int]$count
    }

    $marker = if ([int]$count -gt $previousCount) { " ⬆️" } else { "" }

    $timeOnly = Get-Date -Format "HH:mm"
    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "**Total players**: $count$marker"
    $line3 = "**Online players**: $online"
    $line4 = "**New players today**: +$joinedToday"
    $line5 = $peakLine

    Set-Content -Path $logPath -Value "$line1`n$line2`n$line3`n$line4`n$line5"
}
catch {
    $logPath = "lifetime_log.txt"
    $message = "━━━━━━━━━━━━━━━━━━━━━━`n❌ Failed: site unreachable or error occurred`n━━━━━━━━━━━━━━━━━━━━━━"
    Set-Content -Path $logPath -Value $message
    exit 8
}
