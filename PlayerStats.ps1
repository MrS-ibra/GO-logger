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

    $now       = [datetime]::UtcNow
    $today     = $now.ToString("yyyy-MM-dd")
    $timeOnly  = $now.ToString("HH:mm")

    $logPath  = "NewStats.txt"
    $peakLog  = "StatsHistory.txt"

    # Read only today's lines with three columns
    $peakTodayLines = if (Test-Path $peakLog) {
        Get-Content $peakLog |
          Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -ge 3 }
    } else {
        @()
    }

    # Build new entry and full list
    $newEntry   = "$today $timeOnly,$online,$count"
    $allEntries = $peakTodayLines + $newEntry

    # --- FIX: Write each entry as its own line ---
    [System.IO.File]::WriteAllLines($peakLog, $allEntries)

    # Reassign so joinedToday includes the new entry
    $peakTodayLines = $allEntries

    # Compute joined today
    $joinedToday = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-1] -split ",")[2]) -
        [int](($peakTodayLines[0]  -split ",")[2])
    } else {
        0
    }

    # Compare to previous count for marker
    $previousCount = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-2] -split ",")[2])
    } else {
        [int]$count
    }

    $marker   = ([int]$count -gt $previousCount) ? " ⬆️" : ""
    $peakLine = Get-PeakLine $allEntries

    # Build NewStats.txt output
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
