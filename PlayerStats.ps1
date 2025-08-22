try {
    $url = "https://www.playgenerals.online/players"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim() -replace '[^\d]', ''  # Remove non-digit characters

    $online = if ($html -match "There are (\d+) online player") { $matches[1] } else { "0" }

    # Keep log tracking in StatsHistory.txt
    $peakLog = "StatsHistory.txt"
    $logPath = "NewStats.txt"   

    if (Test-Path $peakLog) {
        $logLines = Get-Content $peakLog
        if ($logLines.Count -ge 180) {
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

    # Determine today's peak
    $peakEntry = $peakTodayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1
    if ($peakEntry) {
        $peakTime, $peakCount = ($peakEntry -split ",")[0,1]
        $peakTime = $peakTime -split " " | Select-Object -Last 1

        # Highlight if current online count is the new peak
        $isNewPeak = ([int]$online -eq [int]$peakCount -and $peakTodayLines.Count -gt 1)
        $peakEmoji = if ($isNewPeak) { " 🔺" } else { "" }

        $peakLine = "📈 Peak ** $peakTime ** (GMT) — ** $peakCount ** players$peakEmoji"
    }
    else {
        $peakLine = "**Today’s peak**: not recorded ❔"
        $isNewPeak = $false
    }

    # Joined today calculation
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

    # Discord Message
    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "👥** $count ** total$marker"
    $line3 = "🟢** $online ** online" + ($(if ($isNewPeak) { " 🔺" } else { "" }))
    $line4 = "🆕** +$joinedToday **today"
    $line5 = $peakLine

    # Write final message to NewStats.txt
    Set-Content -Path $logPath -Value "$line1`n$line2`n$line3`n$line4`n$line5"
}
catch {
    $logPath = "NewStats.txt"
    $message = "━━━━━━━━━━━━━━━━━━━━━━`n❌ Failed: site unreachable or error occurred`n━━━━━━━━━━━━━━━━━━━━━━"
    Set-Content -Path $logPath -Value $message
    exit 8
}
