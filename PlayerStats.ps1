try {
    $url = "https://www.playgenerals.online/players"
    $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content

    $count = (($html -split "Total Lifetime Players:")[1] -split "<")[0] -replace '\D', ''
    $online = if ($html -match "There are (\d+) online player") { $matches[1] } else { "0" }

    $peakLog = "StatsHistory.txt"
    $logPath = "NewStats.txt"

    if (Test-Path $peakLog) {
        $logLines = Get-Content $peakLog
        if ($logLines.Count -ge 180) {
            Set-Content $peakLog $logLines[10..($logLines.Count - 1)]
        }
    }

    Add-Content $peakLog "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    $today = Get-Date -Format "yyyy-MM-dd"
    $peakTodayLines = Get-Content $peakLog | Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -ge 3 }
    $peakEntry = $peakTodayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1

    if ($peakEntry) {
        $peakTime, $peakCount = ($peakEntry -split ",")[0,1]
        $peakTime = $peakTime.Split(" ")[1]
        $isNewPeak = ([int]$online -eq [int]$peakCount -and $peakTodayLines.Count -gt 1)
        $peakLine = "📈 Peak ** $peakTime ** (GMT) — ** $peakCount ** players" + ($(if ($isNewPeak) { " 🔺" } else { "" }))
    } else {
        $peakLine = "**Today’s peak**: not recorded ❔"
        $isNewPeak = $false
    }

    $joinedToday = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-1] -split ",")[2]) - [int](($peakTodayLines[0] -split ",")[2])
    } else { 0 }

    $previousCount = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-2] -split ",")[2])
    } else { [int]$count }

    $marker = if ([int]$count -gt $previousCount) { " ⬆️" } elseif ([int]$count -lt $previousCount) { " 🔻" } else { "" }

    $timeOnly = Get-Date -Format "HH:mm"
    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "👥** $count ** total$marker"
    $line3 = "🟢** $online ** online" + ($(if ($isNewPeak) { " 🔺" } else { "" }))
    $line4 = "🆕** +$joinedToday **today"
    $line5 = $peakLine

    Set-Content $logPath "$line1`n$line2`n$line3`n$line4`n$line5"
}
catch {
    Set-Content "NewStats.txt" "━━━━━━━━━━━━━━━━━━━━━━`n❌ Failed: site unreachable or error occurred`n━━━━━━━━━━━━━━━━━━━━━━"
    exit 8
}
