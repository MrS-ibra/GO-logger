#!/usr/bin/env pwsh

try {
    $url     = "https://www.playgenerals.online/players"
    $html    = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content

    # extract values
    $count   = (($html -split "Total Lifetime Players:")[1] -split "<")[0] -replace '\D',''
    $online  = if ($html -match "There are (\d+) online player") { $matches[1] } else { '0' }

    # log files
    $peakLog = "StatsHistory.txt"
    $logPath = "NewStats.txt"

    # trim history
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 200) {
            Set-Content $peakLog $all[10..($all.Count - 1)]
        }
    }

    # append this run
    Add-Content $peakLog "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    # last log of day at 23:59 GMT
    $today = Get-Date -Format 'yyyy-MM-dd'
    if ((Get-Date -Format 'HH:mm') -eq '23:59') {
        $lines = Get-Content $peakLog | Where-Object { $_ -match "^$today" }
        $last  = $lines | Select-Object -Last 1
        if ($last) { Set-Content "LastLogOfDay.txt" $last }
        else       { Set-Content "LastLogOfDay.txt" "No entries for $today" }
    }

    # today’s stats & peak
    $todayLines = Get-Content $peakLog |
                  Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -eq 3 }
    $peakEntry  = $todayLines |
                  Sort-Object { [int](($_ -split ",")[1]) } -Descending |
                  Select-Object -First 1

    if ($peakEntry) {
        $p         = $peakEntry -split ","
        $peakTime  = ($p[0] -split " ")[1]
        $peakCount = [int]$p[1]
        $isNewPeak = ([int]$online -eq $peakCount -and $todayLines.Count -gt 1)
        $peakLine  = "📈 Peak **$peakTime** (GMT) — **$peakCount** players"
    }
    else {
        $isNewPeak = $false
        $peakLine  = "**Today’s peak** not recorded ❔"
    }

    # joined today
    if ($todayLines.Count -ge 2) {
        $firstCount  = [int](($todayLines[0]  -split ",")[2])
        $lastCount   = [int](($todayLines[-1] -split ",")[2])
        $joinedToday = $lastCount - $firstCount
    }
    else { $joinedToday = 0 }

    # arrow marker
    if ($todayLines.Count -ge 2) {
        $prevCount = [int](($todayLines[-2] -split ",")[2])
    } else {
        $prevCount = [int]$count
    }
    if ([int]$count -gt $prevCount)   { $marker = " ⬆️" }
    elseif ([int]$count -lt $prevCount) { $marker = " 🔻" }
    else                                { $marker = "" }

    # build Discord lines
    $timeOnly = Get-Date -Format "HH:mm"
    $line1    = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2    = "👥** $count ** total$marker — ** $online ** Online 🟢"
    if ($isNewPeak) { $line2 += " ⬆️" }
    $line3    = "🆕** +$joinedToday **today"
    $line4    = $peakLine

    # VIP detection (unchanged)
    $vipMessages = @{
        'Mr Stratos'   = '🚨 Ibra is online, join his halal lounge!'
        'Kill toll^'   = '🚨 Kill toll is online, watch out for the big KT!'
        '-DoMiNaToR-'  = '🚨 Domi is online/Live — expect big plays, and maybe some questionable maps!'
        'OldAnalytics' = '🚨 OldAnalytics is online, ready to solve your problems!'
        'Add later'    = '🚨 Add later.'
    }
    $vipPriority = @('-DoMiNaToR-','Kill toll^','OldAnalytics','Mr Stratos','Add later')
    $players     = [regex]::Matches($html,"<th\s+scope=['""]row['""]>(.*?)</th>") |
                   ForEach-Object { $_.Groups[1].Value }

    $vipOnline = $vipMessages.Keys | Where-Object {
        $players -match ("(?i)^" + [regex]::Escape($_) + "$")
    }

    # write main stats
    Set-Content $logPath "$line1`n$line2`n$line3`n$line4"

    # append first matching VIP
    if ($vipOnline.Count -gt 0) {
        Add-Content $logPath ""
        foreach ($vip in $vipPriority) {
            if ($vipOnline -contains $vip) {
                Add-Content $logPath $vipMessages[$vip]
                break
            }
        }
    }

    #
    # SEND TO DISCORD
    #
    if ($env:DISCORD_WEBHOOK) {
        try {
            $payload = @{ content = Get-Content $logPath -Raw } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri $env:DISCORD_WEBHOOK `
                              -Method Post `
                              -Body $payload `
                              -ContentType 'application/json'
            Write-Host "✅ Posted to Discord"
        }
        catch {
            Write-Warning "Discord post failed: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Error "Script error: $($_.Exception.Message)"
    # do NOT exit non-zero here so GitHub Action step succeeds
}
