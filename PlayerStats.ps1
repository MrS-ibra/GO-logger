try {
    # 1) Fetch players page (everything we need is here)
    $url  = 'https://www.playgenerals.online/players'
    $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content

    # Online
    $online = 0
    if ($html -match 'Online Now\s*\[(\d+)\]') {
        $online = [int]$matches[1]
    }

    # Lifetime Stats: Total Users
    $count = 0
    if ($html -match '(\d+)\s*<span>\s*Total Users\s*</span>') {
        $count = [int]$matches[1]
    }

    # Lifetime Stats: Peak Concurrent
    $peakConcurrent = 0
    if ($html -match '(\d+)\s*<span>\s*Peak Concurrent\s*</span>') {
        $peakConcurrent = [int]$matches[1]
    }

    # Unique Players: Last 24 hours
    $unique24 = 0
    if ($html -match '(\d+)\s*<span>\s*Last 24 hours\s*</span>') {
        $unique24 = [int]$matches[1]
    }

    # Online Now breakdown: Quickmatch + Custom = active games
    $quickmatch = 0
    if ($html -match '(\d+)\s*<span>\s*Quickmatch\s*</span>') {
        $quickmatch = [int]$matches[1]
    }

    $custom = 0
    if ($html -match '(\d+)\s*<span>\s*Custom\s*</span>') {
        $custom = [int]$matches[1]
    }

    $activeGames = $quickmatch + $custom

    # Peak line: concurrent peak + unique 24h
    $peakLine = "📈 ** $peakConcurrent ** Peak — ** $unique24 ** unique last 24h"

    # 4) Append this run to history for join-today calculation (based on total users)
    $peakLog = 'StatsHistory.txt'
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 4000) {
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
    $marker = if ([int]$count -gt $prevCount) { ' ▲' }
              elseif ([int]$count -lt $prevCount) { ' 🔻' }
              else { '' }

    # 7) VIP detection with new HTML structure
    $vipMessages = @{
        'Kill toll^'   = '🚨 Kill toll is online!'
        '-DoMiNaToR-'  = '🚨 Domi is online!'
        'Legi'         = '🚨 Legi is online!'
        'DrGoldFish'   = '🚨 DrGoldFish is online!'
    }
    $vipPriority = @('-DoMiNaToR-', 'Legi', 'Kill toll^', 'DrGoldFish')

    $playerNames = [regex]::Matches($html, "<th>\s*<span class=['""]lbl['""]>Player name</span>\s*(.*?)\s*</th>") |
                   ForEach-Object { $_.Groups[1].Value.Trim() }

    $vipOnline = @()
    foreach ($vip in $vipMessages.Keys) {
        if ($playerNames -match ("(?i)^" + [regex]::Escape($vip) + "$")) {
            $vipOnline += $vip
        }
    }

    # 8) Build Discord message lines
    $timeOnly = Get-Date -Format 'HH:mm'
    $line2    = "👥** $count ** total — ** +$joinedToday **joined today$marker"
    $line3    = "🟢 ** $online ** Online — ** $activeGames ** in active games"
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
