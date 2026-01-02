try {
    # 1) Fetch total lifetime players & current online
    $url  = 'https://www.playgenerals.online/players'
    $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content

    $count = (($html -split 'Total Lifetime Players:')[1] -split '<')[0] -replace '\D', ''
    if ($html -match 'There are (\d+) online player') {
        $online = [int]$matches[1]
    } else {
        $online = 0
    }

    # 2) Fetch service stats HTML and parse peak concurrent players
    $statsUrl  = 'https://www.playgenerals.online/servicestats'
    $statsHtml = (Invoke-WebRequest -Uri $statsUrl -UseBasicParsing -ErrorAction Stop).Content

    if ($statsHtml -match 'Peak Concurrent Players:\s*(\d+)') {
        $peakCount = [int]$matches[1]
    } else {
        $peakCount = 0
    }

    $peakLine = "📈 Peak: ** $peakCount ** players - last 24 hours"

    # 4) Append this run to history for join-today calculation
    $peakLog = 'StatsHistory.txt'
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 4000) {
            # keep only most recent 3990 lines
            Set-Content $peakLog $all[10..($all.Count - 1)]
        }
    }
    Add-Content $peakLog "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    # 5) Calculate how many joined today
    $today      = Get-Date -Format 'yyyy-MM-dd'
    $todayLines = Get-Content $peakLog |
                  Where-Object { $_ -match "^$today" -and ($_ -split ',').Count -eq 3 }

    $joinedToday = if ($todayLines.Count -ge 2) {
        [int]($todayLines[-1] -split ',')[2] - [int]($todayLines[0] -split ',')[2]
    } else {
        0
    }

    # 6) Total count change arrow
    $prevCount = if ($todayLines.Count -ge 2) {
        [int]($todayLines[-2] -split ',')[2]
    } else {
        [int]$count
    }
    $marker = if ([int]$count -gt $prevCount) { ' ⬆️' }
              elseif ([int]$count -lt $prevCount) { ' 🔻' }
              else { '' }

    # 7) VIP detection
    $vipMessages = @{
        'Kill toll^'   = '🚨 Kill toll is online!'
        '-DoMiNaToR-'  = '🚨 Domi is online!'
        'Legi'         = '🚨 Legi is online!'
        'DrGoldFish'   = '🚨 DrGoldFish is online!'
    }
    $vipPriority = @('-DoMiNaToR-', 'Legi', 'Kill toll^', 'DrGoldFish')

    $playerNames = [regex]::Matches($html, "<th\s+scope=['""]row['""]>(.*?)</th>") |
                   ForEach-Object { $_.Groups[1].Value }

    $vipOnline = @()
    foreach ($vip in $vipMessages.Keys) {
        if ($playerNames -match ("(?i)^" + [regex]::Escape($vip) + "$")) {
            $vipOnline += $vip
        }
    }

    # 8) Build Discord message lines
    $timeOnly = Get-Date -Format 'HH:mm'
    $line1    = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2    = "👥** $count ** total$marker — ** $online ** Online 🟢"
    $line3    = "🆕** +$joinedToday **joined today"
    $line4    = $peakLine

    # 9) Write output file
    $logPath = 'NewStats.txt'
    Set-Content $logPath "$line2`n$line3`n$line4"

    if ($vipOnline.Count -gt 0) {
        Add-Content $logPath ''
        foreach ($vip in $vipPriority) {
            if ($vipOnline -contains $vip) {
                Add-Content $logPath $vipMessages[$vip]
                break
            }
        }
    }

} catch {
    Set-Content 'NewStats.txt' "━━━━━━━━━━━━━━━━━━━━━━`n❌** Failed **: site unreachable or error occurred`n━━━━━━━━━━━━━━━━━━━━━━"
    exit 8
}
