function Get-PeakLine($entries) {
    $peakEntry = $entries |
        Sort-Object { ($_ -split ",")[1] -as [int] } -Descending |
        Select-Object -First 1

    if ($peakEntry) {
        $peakTime, $peakCount = ($peakEntry -split ",")[0,1]
        $peakTime = $peakTime -split " " | Select-Object -Last 1
        return "📈 Peak ** $peakTime ** (GMT) — ** $peakCount ** players"
    }

    return "**📈 Peak not recorded ❔"
}

try {
    $url      = "https://www.playgenerals.online/players"
    $response = Invoke-RestMethod -Uri $url -ErrorAction Stop
    $html     = $response.ToString()

    $count  = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count  = $count.Trim() -replace '[^\d]', ''
    $online = ($html -match "There are (\d+) online player") ? $matches[1] : "0"

    $now      = [datetime]::Now
    $today    = $now.ToString("yyyy-MM-dd")
    $timeOnly = $now.ToString("HH:mm")

    $logPath = "NewStats.txt"
    $peakLog = "StatsHistory.txt"

    # 1. Read entire history (all dates)
    $historyLines = if (Test-Path $peakLog) {
        Get-Content $peakLog
    } else {
        @()
    }

    # 2. Extract only today's lines (three columns: date, online, total)
    $peakTodayLines = $historyLines |
        Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -ge 3 }

    # 3. Build the new entry
    $newEntry = "$today $timeOnly,$online,$count"

    # 4. Append the new entry to full history
    $historyLines += $newEntry

    # 5. If history exceeds 500 lines, drop the oldest 25
    if ($historyLines.Count -gt 500) {
        $historyLines = $historyLines | Select-Object -Skip 25
    }

    # 6. Write trimmed history back to StatsHistory.txt
    [System.IO.File]::WriteAllLines($peakLog, $historyLines)

    # 7. Refresh today's lines to include the new entry
    $peakTodayLines = $historyLines |
        Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -ge 3 }

    # 8. Compute joinedToday based on first and last of today's lines
    $joinedToday = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-1] -split ",")[2]) -
        [int](($peakTodayLines[0]  -split ",")[2])
    } else {
        0
    }

    # 9. Determine marker (⬆️) if this run increased lifetime total
    $previousCount = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-2] -split ",")[2])
    } else {
        [int]$count
    }

    $marker   = ([int]$count -gt $previousCount) ? " ⬆️" : ""

    # 10. Build the peak line from today's entries
    $peakLine = Get-PeakLine $peakTodayLines

    # 11. Write NewStats.txt for Discord/webhook
    $output = @(
        "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
        "👥** $count ** total$marker"
        "🟢** $online ** online"
        "🆕** +$joinedToday **today"
        $peakLine
    )
    Set-Content -Path $logPath -Value ($output -join "`n")
}
catch {
    Set-Content -Path $logPath -Value @"
━━━━━━━━━━━━━━━━━━━━━━
❌ Failed: site unreachable or error occurred
━━━━━━━━━━━━━━━━━━━━━━
"@
    exit 8
}
