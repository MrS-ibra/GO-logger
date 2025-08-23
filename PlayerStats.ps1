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

    # write last log of the day at 23:59 GMT
    $today = Get-Date -Format 'yyyy-MM-dd'
    if ((Get-Date -Format 'HH:mm') -eq '23:59') {
        $lastLogFile = "LastLogOfDay.txt"
        $todayLast   = Get-Content $peakLog | Where-Object { $_ -match "^$today" } | Select-Object -Last 1
        if ($todayLast) {
            Set-Content $lastLogFile $todayLast
        }
        else {
            Set-Content $lastLogFile "No entries for $today"
        }
    }

    # isolate today’s entries and find today’s peak (highest online)
    $todayLines     = Get-Content $peakLog | Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -eq 3 }
    $peakEntry      = $todayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1

    if ($peakEntry) {
        $parts      = $peakEntry -split ","
        $peakTime   = ($parts[0] -split " ")[1]
        $peakCount  = [int]$parts[1]
        # new peak if current online equals today’s peak and we’ve seen at least one prior entry
        $isNewPeak  = ([int]$online -eq $peakCount -and $todayLines.Count -gt 1)
        $peakLine   = "📈 Peak ** $peakTime ** (GMT) — ** $peakCount ** players"
    }
    else {
        $peakLine   = "**Today’s peak** not recorded ❔"
        $isNewPeak  = $false
    }

    # how many joined today 
    $joinedToday = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-1] -split ",")[2]) - [int](($todayLines[0] -split ",")[2])
    } else { 0 }

    # total count arrow 
    $prevCount   = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-2] -split ",")[2])
    } else { [int]$count }
    $marker      = if ([int]$count -gt $prevCount) { " ⬆️" } elseif ([int]$count -lt $prevCount) { " 🔻" } else { "" }

    # Discord message
    $timeOnly = Get-Date -Format "HH:mm"
    $line1    = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2    = "👥** $count ** total$marker"
    $line3    = "🟢** $online ** online" + ($(if ($isNewPeak) { " ⬆️" } else { "" }))
    $line4    = "🆕** +$joinedToday **today"
    $line5    = $peakLine

    # --- VIP detection ---
    $watchList = @(
        'Mr Stratos',
        'Kill toll^',
        '-DoMiNaToR-',
        'OldAnalytics',
        'Add later'
        # Add more names here
    )

    # Extract player names from HTML
    $players = [regex]::Matches($html, "<th\s+scope=['""]row['""]>(.*?)</th>") |
        ForEach-Object { $_.Groups[1].Value }

    # Find which VIPs are online
    $vipOnline = @()
    foreach ($name in $watchList) {
        if ($players -match ("(?i)^" + [regex]::Escape($name) + "$")) {
            $vipOnline += $name
        }
    }

    # Write main stats
    Set-Content $logPath "$line1`n$line2`n$line3`n$line4`n$line5"

    # Append VIP alerts if any
    if ($vipOnline.Count -gt 0) {
        Add-Content $logPath ""
        if ($vipOnline.Count -eq 1) {
            Add-Content $logPath ("Hey Generals! {0} is online right now! 🎯" -f $vipOnline[0])
        }
        else {
            $lastName = $vipOnline[-1]
            $otherNames = $vipOnline[0..($vipOnline.Count - 2)]
            $nameList = ($otherNames -join ', ') + " and " + $lastName
            Add-Content $logPath ("Hey Generals! {0} are online right now! 🎯" -f $nameList)
        }
    }

}
catch {
    Set-Content "NewStats.txt" "━━━━━━━━━━━━━━━━━━━━━━`n❌** Failed **: site unreachable or error occurred`n━━━━━━━━━━━━━━━━━━━━━━"
    exit 8
}
