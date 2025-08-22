try {
    $url     = "https://www.playgenerals.online/players"
    $html    = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content

    # extract values
    $count   = (($html -split "Total Lifetime Players:")[1] -split "<")[0] -replace '\D', ''
    $online  = if ($html -match "There are (\d+) online player") { $matches[1] } else { "0" }

    # log files
    $peakLog = "StatsHistory.txt"
    $logPath = "NewStats.txt"

    # trim history to last 170 lines if >180
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 180) {
            Set-Content $peakLog $all[10..($all.Count - 1)]
        }
    }

    # append this run
    Add-Content $peakLog "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    # isolate today’s entries and find today’s peak (highest online)
    $today          = Get-Date -Format 'yyyy-MM-dd'
    $todayLines     = Get-Content $peakLog | Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -eq 3 }
    $peakEntry      = $todayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1

    if ($peakEntry) {
        $parts      = $peakEntry -split ","
        $peakTime   = ($parts[0] -split " ")[1]
        $peakCount  = [int]$parts[1]
        # new-peak if current online equals today’s peak and we’ve seen at least one prior entry
        $isNewPeak  = ([int]$online -eq $peakCount -and $todayLines.Count -gt 1)
        $peakLine   = "📈 Peak ** $peakTime ** (GMT) — ** $peakCount ** players" + ($(if ($isNewPeak) { " 🔺" } else { "" }))
    }
    else {
        $peakLine   = "**Today’s peak**: not recorded ❔"
        $isNewPeak  = $false
    }

    # how many joined today (delta of lifetime count)
    $joinedToday = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-1] -split ",")[2]) - [int](($todayLines[0] -split ",")[2])
    } else { 0 }

    # total count arrow (lifetime)
    $prevCount   = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-2] -split ",")[2])
    } else { [int]$count }
    $marker      = if ([int]$count -gt $prevCount) { " ⬆️" } elseif ([int]$count -lt $prevCount) { " 🔻" } else { "" }

    # final Discord lines (unchanged)
    $timeOnly = Get-Date -Format "HH:mm"
    $line1    = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2    = "👥** $count ** total$marker"
    $line3    = "🟢** $online ** online" + ($(if ($isNewPeak) { " 🔺" } else { "" }))
    $line4    = "🆕** +$joinedToday **today"
    $line5    = $peakLine

    Set-Content $logPath "$line1`n$line2`n$line3`n$line4`n$line5"
}
catch {
    Set-Content "NewStats.txt" "━━━━━━━━━━━━━━━━━━━━━━`n❌ Failed: site unreachable or error occurred`n━━━━━━━━━━━━━━━━━━━━━━"
    exit 8
}
