# --- CONFIG ---
$webhookUrl = "YOUR_DISCORD_WEBHOOK_URL"

try {
    # 1) FETCH HTML
    try {
        $url  = "https://www.playgenerals.online/players"
        $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop).Content
        Write-Host "✅ Fetched player page HTML."
    }
    catch {
        Write-Warning "Failed to fetch player page: $($_.Exception.Message)"
        throw
    }

    # 2) EXTRACT STATS
    $count  = (($html -split "Total Lifetime Players:")[1] -split "<")[0] -replace '\D',''
    $online = if ($html -match "There are (\d+) online player") { $matches[1] } else { '0' }
    Write-Host "Stats – Total:$count  Online:$online"

    # 3) UPDATE HISTORY LOG
    $peakLog = "StatsHistory.txt"
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 200) {
            Write-Host "Trimming $peakLog to last 190 entries."
            Set-Content $peakLog $all[10..($all.Count - 1)]
        }
    }
    Add-Content $peakLog "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    # 4) DAILY LAST-LOG SNAPSHOT
    $today = Get-Date -Format 'yyyy-MM-dd'
    if ((Get-Date -Format 'HH:mm') -eq '23:59') {
        $todayLast = Get-Content $peakLog | Where-Object { $_ -match "^$today" } | Select-Object -Last 1
        if ($todayLast) {
            Set-Content "LastLogOfDay.txt" $todayLast
            Write-Host "Wrote last log of day: $todayLast"
        } else {
            Set-Content "LastLogOfDay.txt" "No entries for $today"
            Write-Host "No entries for $today to write to LastLogOfDay.txt"
        }
    }

    # 5) COMPUTE PEAK & JOINED TODAY
    $todayLines = Get-Content $peakLog |
                  Where-Object { $_ -match "^$today" -and ($_ -split ',').Count -eq 3 }
    $peakEntry  = $todayLines |
                  Sort-Object { ($_ -split ',')[1] -as [int] } -Descending |
                  Select-Object -First 1

    if ($peakEntry) {
        $parts     = $peakEntry -split ','
        $peakTime  = ($parts[0] -split ' ')[1]
        $peakCount = [int]$parts[1]
        $isNewPeak = ([int]$online -eq $peakCount -and $todayLines.Count -gt 1)
        $peakLine  = "📈 Peak **$peakTime** (GMT) — **$peakCount** players"
        Write-Host "Today's peak: $peakLine"
    } else {
        $peakLine  = "**Today’s peak** not recorded ❔"
        $isNewPeak = $false
        Write-Host "No peak entry for today."
    }

    $joinedToday = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-1] -split ',')[2]) - [int](($todayLines[0] -split ',')[2])
    } else {
        0
    }
    Write-Host "Joined today: +$joinedToday"

    # 6) BUILD DISCORD LINES
    $timeOnly     = Get-Date -Format 'HH:mm'
    $prevCountVal = if ($todayLines.Count -ge 2) { [int]($todayLines[-2] -split ',')[2] } else { [int]$count }
    $marker       = if ([int]$count -gt $prevCountVal) { ' ⬆️' } elseif ([int]$count -lt $prevCountVal) { ' 🔻' } else { '' }
    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "👥 **$count** total$marker — **$online** Online 🟢" + (if ($isNewPeak) { ' ⬆️' } else { '' })
    $line3 = "🆕 **+$joinedToday** today"
    $line4 = $peakLine

    # 7) VIP DETECTION & PRIORITY
    $vipMessages = @{
        '-DoMiNaToR-'  = '🚨 Domi is online — the stream is live and the chaos begins!'
        'Kill toll^'   = "🚨 Kill toll^ is online — watch out for KT's surprises!"
        'Mr Stratos'   = '🚨 Mr Stratos is online — join his halal lounge!'
        'OldAnalytics' = '🚨 OldAnalytics is online — ready to solve your problems!'
        'Add later'    = '🚨 Add later.'
    }
    $vipPriority = @('-DoMiNaToR-','Kill toll^','OldAnalytics','Mr Stratos','Add later')

    $players  = [regex]::Matches($html, "<th\s+scope=['""]row['""]>(.*?)</th>") |
                ForEach-Object { $_.Groups[1].Value }
    $vipOnline = $vipMessages.Keys | Where-Object { $players -match ("(?i)^" + [regex]::Escape($_) + "$") }

    $vipAlert = ''
    foreach ($vip in $vipPriority) {
        if ($vipOnline -contains $vip) {
            $vipAlert = $vipMessages[$vip]
            break
        }
    }

    # 8) WRITE TEXT LOG
    $logText = "$line1`n$line2`n$line3`n$line4"
    if ($vipAlert) { $logText += "`n`n$vipAlert" }
    Set-Content "NewStats.txt" $logText
    Write-Host "Prepared NewStats.txt with VIP alert: '$vipAlert'"

    # 9) QUICKCHART GRAPH
    $chartPath   = "TodayTrend.png"
    $chartExists = $false

    if ($todayLines.Count -gt 0) {
        $labels = $todayLines | ForEach-Object { ($_ -split ',')[0] -split ' ')[1] }
        $data   = $todayLines | ForEach-Object { [int](($_ -split ',')[1]) }

        Write-Host "Chart labels: $($labels -join ', ')"
        Write-Host "Chart data:  $($data -join ', ')"

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

    # 10) SEND TO DISCORD
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
