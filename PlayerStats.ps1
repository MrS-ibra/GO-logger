function Get-PeakLine($entries) {
    $validEntries = $entries | Where-Object { ($_ -split ",").Count -ge 3 }
    $peakEntry = $validEntries | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1
    if ($peakEntry) {
        $peakTime, $peakCount = ($peakEntry -split ",")[0,1]
        $peakTime = $peakTime -split " " | Select-Object -Last 1
        return "📈 Peak ** $peakTime ** (GMT) — ** $peakCount ** players"
    }
    return "**📈 Peak not recorded ❔**"
}

try {
    $url = "https://www.playgenerals.online/players"
    $response = Invoke-RestMethod -Uri $url -ErrorAction Stop
    $html = $response.ToString()

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim() -replace '[^\d]', ''
    $online = ($html -match "There are (\d+) online player") ? [int]$matches[1] : 0

    $now = [datetime]::Now
    $today = $now.ToString("yyyy-MM-dd")
    $timeOnly = $now.ToString("HH:mm")

    $logPath = "NewStats.txt"
    $peakLog = "StatsHistory.txt"

    # Read today's entries from history
    $peakTodayLines = if (Test-Path $peakLog) {
        Get-Content $peakLog | Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -ge 3 }
    } else { @() }

    # Create new entry and append it
    $newEntry = "$today $timeOnly,$online,$count"
    $allEntries = $peakTodayLines + $newEntry
    Set-Content -Path $peakLog -Value $allEntries

    # ✅ Ensure peak logic includes latest entry
    $peakTodayLines = $allEntries

    # Calculate joined today
    $joinedToday = ($peakTodayLines.Count -ge 2) ?
        [int](($peakTodayLines[-1] -split ",")[2]) - [int](($peakTodayLines[0] -split ",")[2]) : 0

    # Compare with previous count to detect increase
    $previousCount = ($peakTodayLines.Count -ge 2) ?
        [int](($peakTodayLines[-2] -split ",")[2]) : [int]$count

    $marker = ([int]$count -gt $previousCount) ? " ⬆️" : ""

    # 🔺 Optional: Add peak marker if new high
    $previousPeak = ($peakTodayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1) -split ",")[1]
    $peakMarker = ($online -gt [int]$previousPeak) ? " 🔺" : ""

    $peakLine = "📈 Peak ** $timeOnly ** (GMT) — ** $online ** players$peakMarker"

    # Final output
    $output = @(
        "━━━━━━** Time (GMT): $timeOnly **━━━━━━"
        "👥** $count ** total$marker"
        "🟢** $online ** online"
        "🆕** +$joinedToday **today"
        $peakLine
    )

    Set-Content -Path $logPath -Value ($output -join "`n")
} # ← This was missing
catch {
    Set-Content -Path "NewStats.txt" -Value @"
━━━━━━━━━━━━━━━━━━━━━━
❌ Failed: site unreachable or error occurred
━━━━━━━━━━━━━━━━━━━━━━
"@
    exit 8
}
