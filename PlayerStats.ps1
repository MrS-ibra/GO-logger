# --- CONFIG ---
$webhookUrl = "YOUR_DISCORD_WEBHOOK_URL"

try {
    # --- FETCH HTML ---
    try {
        $url  = "https://www.playgenerals.online/players"
        $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content
    }
    catch {
        Write-Warning "Failed to fetch player page: $($_.Exception.Message)"
        $html = $null
    }

    if (-not $html) { throw "No HTML content retrieved" }

    # --- EXTRACT VALUES ---
    $count   = (($html -split "Total Lifetime Players:")[1] -split "<")[0] -replace '\D', ''
    $online  = if ($html -match "There are (\d+) online player") { $matches[1] } else { "0" }

    # --- LOG FILES ---
    $peakLog = "StatsHistory.txt"
    $logPath = "NewStats.txt"

    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 200) {
            Set-Content $peakLog $all[10..($all.Count - 1)]
        }
    }

    Add-Content $peakLog "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    # --- LAST LOG OF DAY ---
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

    # --- PEAK CALC ---
    $todayLines = Get-Content $peakLog | Where-Object { $_ -match "^$today" -and ($_ -split ",").Count -eq 3 }
    $peakEntry  = $todayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1

    if ($peakEntry) {
        $parts      = $peakEntry -split ","
        $peakTime   = ($parts[0] -split " ")[1]
        $peakCount  = [int]$parts[1]
        $isNewPeak  = ([int]$online -eq $peakCount -and $todayLines.Count -gt 1)
        $peakLine   = "📈 Peak ** $peakTime ** (GMT) — ** $peakCount ** players"
    }
    else {
        $peakLine   = "**Today’s peak** not recorded ❔"
        $isNewPeak  = $false
    }

    # --- JOINED TODAY ---
    $joinedToday = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-1] -split ",")[2]) - [int](($todayLines[0] -split ",")[2])
    } else { 0 }

    # --- TOTAL COUNT ARROW ---
    $prevCount = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-2] -split ",")[2])
    } else { [int]$count }
    $marker    = if ([int]$count -gt $prevCount) { " ⬆️" } elseif ([int]$count -lt $prevCount) { " 🔻" } else { "" }

    # --- DISCORD LINES ---
    $timeOnly = Get-Date -Format "HH:mm"
    $line1    = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2    = "👥** $count ** total$marker — ** $online ** Online 🟢" + ($(if ($isNewPeak) { " ⬆️" } else { "" }))
    $line3    = "🆕** +$joinedToday **today"
    $line4    = $peakLine

    # --- VIP MESSAGES ---
    $vipMessages = @{
        'Mr Stratos'   = '🚨 Ibra is online, join his halal lounge!'
        'Kill toll^'   = '🚨 Kill toll is online, watch out for the big KT!'
        '-DoMiNaToR-'  = '🚨 Domi is online/Live — expect big plays, and maybe some questionable maps!'
        'OldAnalytics' = '🚨 OldAnalytics is online, ready to solve your problems!'
        'Add later'    = '🚨 Add later.'
    }

    $vipPriority = @(
        '-DoMiNaToR-',
        'Kill toll^',
        'OldAnalytics',
        'Mr Stratos',
        'Add later'
    )

    # --- VIP DETECTION ---
    $players = [regex]::Matches($html, "<th\s+scope=['""]row['""]>(.*?)</th>") |
        ForEach-Object { $_.Groups[1].Value }

    $vipOnline = @()
    foreach ($name in $vipMessages.Keys) {
        if ($players -match ("(?i)^" + [regex]::Escape($name) + "$")) {
            $vipOnline += $name
        }
    }

    # --- WRITE MAIN STATS ---
    Set-Content $logPath "$line1`n$line2`n$line3`n$line4"

    if ($vipOnline.Count -gt 0) {
        Add-Content $logPath ""
        foreach ($vip in $vipPriority) {
            if ($vipOnline -contains $vip) {
                Add-Content $logPath $vipMessages[$vip]
                break
            }
        }
    }

    # --- QUICKCHART GRAPH ---
    $chartExists = $false
    try {
        if ($todayLines.Count -gt 0) {
            $labels = @()
            $data   = @()
            foreach ($line in $todayLines) {
                $parts = $line -split ","
                $labels += ($parts[0] -split " ")[1]
                $data   += [int]$parts[1]
            }

            Write-Host "Chart labels: $($labels -join ', ')"
            Write-Host "Chart data: $($data -join ', ')"

            $chartConfig = @{
                type = "line"
                data = @{
                    labels = $labels
                    datasets = @(@{
                        label = "Players Online"
                        data = $data
                        borderColor = "green"
                        fill = $false
                    })
                }
                options = @{
                    title = @{
                        display = $true
                        text = "Generals Online — $today"
                    }
                }
            } | ConvertTo-Json -Depth 10 -Compress

            $chartUrl = "https://quickchart.io/chart?c=$([uri]::EscapeDataString($chartConfig))"
            Invoke-WebRequest -Uri $chartUrl -OutFile "TodayTrend.png" -ErrorAction Stop

            if ((Get-Item "TodayTrend.png").Length -gt 1000) {
                $chartExists = $true
                Write-Host "Chart generated successfully."
            }
            else {
                Write-Warning "QuickChart returned a small/invalid file."
            }
        }
        else {
            Write-Warning "No data for today — chart skipped."
        }
    }
    catch {
        Write-Warning "Chart generation failed: $($_.Exception.Message)"
    }

    # --- SEND TO DISCORD ---
    try {
        if ($chartExists -and (Test-Path "TodayTrend.png")) {
            $body = @{
                "content" = Get-Content $logPath -Raw
            }
            $files = @{
                "file1" = Get-Item "TodayTrend.png"
            }
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Form ($body + $files)
        }
        else {
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Body (@{ "content" = Get-Content $logPath -Raw } | ConvertTo-Json) -ContentType 'application/json'
        }
    }
    catch {
        Write-Warning "Discord send failed: $($_.Exception.Message)"
    }

}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 8
}
