#!/usr/bin/env pwsh

# 0) CONFIG — make sure this is "https://…"
$webhookUrl = "https://discord.com/api/webhooks/1406980157561897021/0CMP5oEuG1mDhIij2k0EjhPq1Cn5xgDlJYZtXwRnM2dzrXouEKrNIyNjwi8afGHq46Ys"

try {
    #
    # 1) FETCH HTML
    #
    try {
        $url      = "https://www.playgenerals.online/players"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $html     = $response.Content
        Write-Host "✅ Fetched player page HTML."
    }
    catch {
        Write-Warning "Failed to fetch player page: $($_.Exception.Message)"
        throw
    }

    #
    # 2) PARSE STATS
    #
    if ($html -match "There are (\d+) online player") {
        $online = $matches[1]
    } else {
        $online = "0"
    }
    $count = (($html -split "Total Lifetime Players:")[1] -split "<")[0] -replace '\D','0'
    Write-Host "Stats – Total: $count  Online: $online"

    #
    # 3) LOG HISTORY
    #
    $peakLog = "StatsHistory.txt"
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 200) {
            Write-Host "Trimming $peakLog to last 190 entries."
            $all = $all[10..($all.Count - 1)]
            Set-Content -Path $peakLog -Value $all
        }
    }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
    Add-Content -Path $peakLog -Value "$ts,$online,$count"

    #
    # 4) DAILY SNAPSHOT AT 23:59 GMT
    #
    $today = Get-Date -Format "yyyy-MM-dd"
    $now   = Get-Date -Format "HH:mm"
    if ($now -eq "23:59") {
        $entries   = Get-Content $peakLog | Where-Object { $_ -like "$today*" }
        $lastEntry = $entries | Select-Object -Last 1
        if ($lastEntry) {
            Set-Content -Path "LastLogOfDay.txt" -Value $lastEntry
            Write-Host "Wrote last log of day: $lastEntry"
        }
        else {
            Set-Content -Path "LastLogOfDay.txt" -Value "No entries for $today"
            Write-Host "No entries for $today to write."
        }
    }

    #
    # 5) COMPUTE TODAY’S PEAK & JOINED
    #
    $todayLines = Get-Content $peakLog | Where-Object {
        ($_.Split(',')[0] -like "$today*") -and ($_.Split(',').Count -eq 3)
    }

    # Peak
    $peakEntry = $todayLines |
        Sort-Object {[int]($_.Split(',')[1])} -Descending |
        Select-Object -First 1

    if ($peakEntry) {
        $parts       = $peakEntry.Split(',')
        $peakTime    = $parts[0].Split(' ')[1]
        $peakCount   = [int]$parts[1]
        $isNewPeak   = ([int]$online -eq $peakCount -and $todayLines.Count -gt 1)
        $peakLine    = "📈 Peak **$peakTime** (GMT) — **$peakCount** players"
        Write-Host "Today's peak: $peakLine"
    }
    else {
        $peakLine  = "**Today’s peak** not recorded ❔"
        $isNewPeak = $false
        Write-Host "No peak entry for today."
    }

    # Joined
    if ($todayLines.Count -ge 2) {
        $firstCount  = [int]$todayLines[0].Split(',')[2]
        $lastCount   = [int]$todayLines[-1].Split(',')[2]
        $joinedToday = $lastCount - $firstCount
    }
    else {
        $joinedToday = 0
    }
    Write-Host "Joined today: +$joinedToday"

    #
    # 6) BUILD MESSAGE LINES
    #
    $timeOnly = Get-Date -Format "HH:mm"

    if ($todayLines.Count -ge 2) {
        $prevCountVal = [int]$todayLines[-2].Split(',')[2]
    }
    else {
        $prevCountVal = [int]$count
    }

    if ([int]$count -gt $prevCountVal) {
        $marker = " ⬆️"
    }
    elseif ([int]$count -lt $prevCountVal) {
        $marker = " 🔻"
    }
    else {
        $marker = ""
    }

    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "👥 **$count** total$marker — **$online** Online 🟢"
    if ($isNewPeak) { $line2 += " ⬆️" }
    $line3 = "🆕 **+$joinedToday** today"
    $line4 = $peakLine

    #
    # 7) VIP DETECTION
    #
    $vipMessages = @{
        '-DoMiNaToR-'  = '🚨 Domi is online — the stream is live and the chaos begins!'
        'Kill toll^'   = "🚨 Kill toll^ is online — watch out for KT's surprises!"
        'Mr Stratos'   = '🚨 Mr Stratos is online — join his halal lounge!'
        'OldAnalytics' = '🚨 OldAnalytics is online — ready to solve your problems!'
        'Add later'    = '🚨 Add later.'
    }
    $vipPriority = @('-DoMiNaToR-','Kill toll^','OldAnalytics','Mr Stratos','Add later')

    $players  = [regex]::Matches($html,"<th\s+scope=['""]row['""]>(.*?)</th>") |
                ForEach-Object { $_.Groups[1].Value }
    $vipOnline = @()
    foreach ($name in $vipMessages.Keys) {
        if ($players -match ("(?i)^"+[regex]::Escape($name)+"$")) {
            $vipOnline += $name
        }
    }

    $vipAlert = ""
    foreach ($vip in $vipPriority) {
        if ($vipOnline -contains $vip) {
            $vipAlert = $vipMessages[$vip]
            break
        }
    }

    #
    # 8) WRITE TEXT LOG
    #
    $logText = @($line1,$line2,$line3,$line4) -join "`n"
    if ($vipAlert) { $logText += "`n`n$vipAlert" }
    Set-Content -Path "NewStats.txt" -Value $logText
    Write-Host "Prepared NewStats.txt (VIP alert: '$vipAlert')."

    #
    # 9) GENERATE QUICKCHART GRAPH
    #
    $chartPath   = "TodayTrend.png"
    $chartExists = $false

    if ($todayLines.Count -gt 0) {
        $labels = $todayLines | ForEach-Object { ($_.Split(',')[0]).Split(' ')[1] }
        $data   = $todayLines | ForEach-Object { [int]($_.Split(',')[1]) }
        Write-Host "Chart labels: $($labels -join ', ')"
        Write-Host "Chart data:  $($data   -join ', ')"

        $chartConfig = @{
            type = 'line'
            data = @{
                labels   = $labels
                datasets = @(@{
                    label       = 'Players Online'
                    data        = $data
                    borderColor = 'green'
                    fill        = $false
                })
            }
            options = @{
                title = @{
                    display = $true
                    text    = "Generals Online — $today"
                }
            }
        } | ConvertTo-Json -Depth 10 -Compress

        $chartUrl = "https://quickchart.io/chart?c=$([uri]::EscapeDataString($chartConfig))"
        try {
            Invoke-WebRequest -Uri $chartUrl -OutFile $chartPath -ErrorAction Stop
            $size = (Get-Item $chartPath).Length
            if ($size -gt 2000) {
                Write-Host "✅ Chart downloaded ($size bytes)."
                $chartExists = $true
            }
            else {
                Write-Warning "Chart file too small ($size bytes)."
            }
        }
        catch {
            Write-Warning "QuickChart download failed: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "No data today — skipping chart."
    }

    #
    # 10) SEND TO DISCORD (with fallback)
    #
    try {
        if ($chartExists) {
            Write-Host "Sending stats + chart to Discord (multipart)..."
            $form = @{
                payload_json = (@{ content = $logText } | ConvertTo-Json)
                file         = Get-Item $chartPath
            }
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Form $form -ErrorAction Stop
        }
        else {
            throw "Skipping multipart because no chart."
        }
        Write-Host "✅ Multipart Discord post succeeded."
    }
    catch {
        Write-Warning "Multipart post failed: $($_.Exception.Message)"
        Write-Host  "Retrying text-only Discord post..."
        try {
            $json = @{ content = $logText } | ConvertTo-Json
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $json -ContentType 'application/json' -ErrorAction Stop
            Write-Host "✅ Text-only Discord post succeeded."
        }
        catch {
            Write-Error "Text-only retry failed: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Error "Fatal script error: $($_.Exception.Message)"
    exit 8
}
