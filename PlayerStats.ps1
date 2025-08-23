#!/usr/bin/env pwsh

# --- CONFIG ---
$webhookUrl = "YOUR_DISCORD_WEBHOOK_URL"

try {
    # 1) FETCH HTML
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

    # 2) PARSE TOTAL AND ONLINE
    # Total lifetime players
    $split1 = $html -split "Total Lifetime Players:"
    if ($split1.Count -gt 1) {
        $countPart = $split1[1] -split "<"
        $count     = $countPart[0] -replace '\D',''
    }
    else {
        $count = '0'
    }

    # Currently online
    if ($html -match "There are (\d+) online player") {
        $online = $matches[1]
    }
    else {
        $online = '0'
    }

    Write-Host "Stats – Total: $count  Online: $online"

    # 3) LOG HISTORY
    $peakLog = "StatsHistory.txt"
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 200) {
            Write-Host "Trimming $peakLog to last 190 entries."
            $all = $all[10..($all.Count - 1)]
            Set-Content -Path $peakLog -Value $all
        }
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
    Add-Content -Path $peakLog -Value "$timestamp,$online,$count"

    # 4) DAILY LAST-LOG SNAPSHOT AT 23:59 GMT
    $today      = Get-Date -Format 'yyyy-MM-dd'
    $nowTime    = Get-Date -Format 'HH:mm'
    if ($nowTime -eq '23:59') {
        $todayLinesAll = Get-Content $peakLog
        $todayEntries  = $todayLinesAll | Where-Object { $_ -like "$today*" }
        $lastOfDay     = $todayEntries | Select-Object -Last 1
        if ($lastOfDay) {
            Set-Content -Path "LastLogOfDay.txt" -Value $lastOfDay
            Write-Host "Wrote last log of day: $lastOfDay"
        }
        else {
            Set-Content -Path "LastLogOfDay.txt" -Value "No entries for $today"
            Write-Host "No entries for $today to write."
        }
    }

    # 5) COMPUTE TODAY’S PEAK
    $todayLines = Get-Content $peakLog | Where-Object {
        ($_ -split ',')[0] -like "$today*" -and
        (($_ -split ',').Count -eq 3)
    }

    $peakEntry = $todayLines |
        Sort-Object { [int](($_ -split ',')[1]) } -Descending |
        Select-Object -First 1

    if ($peakEntry) {
        $parts      = $peakEntry -split ','
        $peakTime   = ($parts[0] -split ' ')[1]
        $peakCount  = [int]$parts[1]
        if ([int]$online -eq $peakCount -and $todayLines.Count -gt 1) {
            $isNewPeak = $true
        }
        else {
            $isNewPeak = $false
        }
        $peakLine = "📈 Peak **$peakTime** (GMT) — **$peakCount** players"
        Write-Host "Today's peak: $peakLine"
    }
    else {
        $isNewPeak = $false
        $peakLine  = "**Today’s peak** not recorded ❔"
        Write-Host "No peak entry for today."
    }

    # 6) HOW MANY JOINED TODAY
    if ($todayLines.Count -ge 2) {
        $firstCount = [int]((($todayLines[0]  -split ',')[2]))
        $lastCount  = [int]((($todayLines[-1] -split ',')[2]))
        $joinedToday = $lastCount - $firstCount
    }
    else {
        $joinedToday = 0
    }
    Write-Host "Joined today: +$joinedToday"

    # 7) BUILD DISCORD MESSAGE LINES
    $timeOnly = Get-Date -Format 'HH:mm'

    if ($todayLines.Count -ge 2) {
        $prevCountVal = [int]((($todayLines[-2] -split ',')[2]))
    }
    else {
        $prevCountVal = [int]$count
    }

    if ([int]$count -gt $prevCountVal) {
        $marker = ' ⬆️'
    }
    elseif ([int]$count -lt $prevCountVal) {
        $marker = ' 🔻'
    }
    else {
        $marker = ''
    }

    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "👥 **$count** total$marker — **$online** Online 🟢"
    if ($isNewPeak) { $line2 += ' ⬆️' }
    $line3 = "🆕 **+$joinedToday** today"
    $line4 = $peakLine

    # 8) VIP DETECTION & PRIORITY
    $vipMessages = @{
        '-DoMiNaToR-'  = '🚨 Domi is online — the stream is live and the chaos begins!'
        'Kill toll^'   = "🚨 Kill toll^ is online — watch out for KT's surprises!"
        'Mr Stratos'   = '🚨 Mr Stratos is online — join his halal lounge!'
        'OldAnalytics' = '🚨 OldAnalytics is online — ready to solve your problems!'
        'Add later'    = '🚨 Add later.'
    }

    $vipPriority = @(
        '-DoMiNaToR-',
        'Kill toll^',
        'OldAnalytics',
        'Mr Stratos',
        'Add later'
    )

    $players = [regex]::Matches($html, "<th\s+scope=['""]row['""]>(.*?)</th>") |
               ForEach-Object { $_.Groups[1].Value }

    $vipOnline = @()
    foreach ($name in $vipMessages.Keys) {
        if ($players -match ("(?i)^" + [regex]::Escape($name) + "$")) {
            $vipOnline += $name
        }
    }

    $vipAlert = ''
    foreach ($vip in $vipPriority) {
        if ($vipOnline -contains $vip) {
            $vipAlert = $vipMessages[$vip]
            break
        }
    }

    # 9) WRITE TEXT LOG
    $logText = @(
        $line1
        $line2
        $line3
        $line4
    ) -join "`n"

    if ($vipAlert) {
        $logText += "`n`n" + $vipAlert
    }

    Set-Content -Path "NewStats.txt" -Value $logText
    Write-Host "Prepared NewStats.txt with VIP alert: '$vipAlert'"

    # 10) GENERATE QUICKCHART GRAPH
    $chartPath   = "TodayTrend.png"
    $chartExists = $false

    if ($todayLines.Count -gt 0) {
        $labels = $todayLines | ForEach-Object { ($_.Split(',')[0]).Split(' ')[1] }
        $data   = $todayLines | ForEach-Object { [int]($_.Split(',')[1]) }

        Write-Host "Chart labels: $($labels -join ', ')"
        Write-Host "Chart data:  $($data   -join ', ')"

        $chartConfig = @{
            type    = 'line'
            data    = @{
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
                Write-Warning "Chart file too small ($size bytes), skipping attachment."
            }
        }
        catch {
            Write-Warning "Failed to download chart: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "No today's data — skipping chart generation."
    }

    # 11) SEND TO DISCORD
    try {
        if ($chartExists) {
            Write-Host "Sending stats + chart to Discord..."
            $form = @{
                payload_json = (@{ content = $logText } | ConvertTo-Json)
                file         = Get-Item $chartPath
            }
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Form $form
        }
        else {
            Write-Host "Sending text-only stats to Discord..."
            $json = @{ content = $logText } | ConvertTo-Json
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $json -ContentType 'application/json'
        }
        Write-Host "✅ Discord post complete."
    }
    catch {
        Write-Warning "Discord post failed: $($_.Exception.Message)"
    }
}
catch {
    Write-Error "Fatal script error: $($_.Exception.Message)"
    exit 8
}
