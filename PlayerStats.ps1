#!/usr/bin/env pwsh

# Read webhook URL from environment (set in GitHub Actions secrets)
$webhookUrl = $env:DISCORD_WEBHOOK

try {
    # 1) FETCH HTML
    try {
        $html = (Invoke-WebRequest -Uri "https://www.playgenerals.online/players" -UseBasicParsing -ErrorAction Stop).Content
    } catch {
        Write-Warning "Failed to fetch site: $($_.Exception.Message)"
        throw
    }

    # 2) PARSE COUNTS
    if ($html -match "There are (\d+) online player") { $online = $matches[1] } else { $online = "0" }
    $count = (($html -split "Total Lifetime Players:")[1] -split "<")[0] -replace '\D','0'

    # 3) APPEND HISTORY
    $peakLog = "StatsHistory.txt"
    if (Test-Path $peakLog) {
        $all = Get-Content $peakLog
        if ($all.Count -ge 200) {
            $all = $all[10..($all.Count - 1)]
            Set-Content $peakLog $all
        }
    }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
    Add-Content $peakLog "$ts,$online,$count"

    # 4) DAILY SNAPSHOT AT 23:59 GMT
    $today = Get-Date -Format "yyyy-MM-dd"; $now = Get-Date -Format "HH:mm"
    if ($now -eq "23:59") {
        $last = Get-Content $peakLog | Where-Object { $_ -like "$today*" } | Select-Object -Last 1
        if ($last) { Set-Content "LastLogOfDay.txt" $last }
        else      { Set-Content "LastLogOfDay.txt" "No entries for $today" }
    }

    # 5) TODAY’S PEAK & JOINED
    $todayLines = Get-Content $peakLog |
        Where-Object { ($_.Split(',')[0] -like "$today*") -and ($_.Split(',').Count -eq 3) }

    $peakEntry = $todayLines |
        Sort-Object {[int]($_.Split(',')[1])} -Descending |
        Select-Object -First 1

    if ($peakEntry) {
        $p = $peakEntry.Split(',')
        $peakTime  = $p[0].Split(' ')[1]
        $peakCount = [int]$p[1]
        $isNewPeak = ([int]$online -eq $peakCount -and $todayLines.Count -gt 1)
        $peakLine  = "📈 Peak **$peakTime** (GMT) — **$peakCount** players"
    } else {
        $peakLine  = "**Today’s peak** not recorded ❔"
        $isNewPeak = $false
    }

    if ($todayLines.Count -ge 2) {
        $first = [int]$todayLines[0].Split(',')[2]
        $last  = [int]$todayLines[-1].Split(',')[2]
        $joinedToday = $last - $first
    } else { $joinedToday = 0 }

    # 6) BUILD STATS LINES
    $timeOnly = Get-Date -Format "HH:mm"
    if ($todayLines.Count -ge 2) { $prevCount = [int]$todayLines[-2].Split(',')[2] }
    else                          { $prevCount = [int]$count }
    if ([int]$count -gt $prevCount) { $marker = " ⬆️" }
    elseif ([int]$count -lt $prevCount) { $marker = " 🔻" }
    else { $marker = "" }

    $line1 = "**━━━━━━━Time (GMT): $timeOnly━━━━━━━**"
    $line2 = "👥 **$count** total$marker — **$online** Online 🟢" + (if ($isNewPeak) { " ⬆️" } else { "" })
    $line3 = "🆕 **+$joinedToday** today"
    $line4 = $peakLine

    # 7) VIP DETECTION
    $vipMessages = @{
        '-DoMiNaToR-'  = '🚨 Domi is online — the stream is live and the chaos begins!'
        'Kill toll^'   = "🚨 Kill toll^ is online — watch out for KT's surprises!"
        'Mr Stratos'   = '🚨 Mr Stratos is online — join his halal lounge!'
        'OldAnalytics' = '🚨 OldAnalytics is online — ready to solve your problems!'
        'Add later'    = '🚨 Add later.'
    }
    $vipPriority = @('-DoMiNaToR-','Kill toll^','OldAnalytics','Mr Stratos','Add later')

    $players  = [regex]::Matches($html,"<th\s+scope=['""]row['""]>(.*?)</th>") | ForEach-Object { $_.Groups[1].Value }
    $vipOnline = $vipMessages.Keys | Where-Object { $players -match ("(?i)^" + [regex]::Escape($_) + "$") }

    $vipAlert = ""
    foreach ($vip in $vipPriority) {
        if ($vipOnline -contains $vip) { $vipAlert = $vipMessages[$vip]; break }
    }

    # 8) WRITE TEXT LOG
    $logTextLines = @($line1,$line2,$line3,$line4)
    if ($vipAlert) { $logTextLines += ""; $logTextLines += $vipAlert }
    $logText = $logTextLines -join "`n"
    Set-Content "NewStats.txt" $logText

    # 9) BUILD CHART
    $chartPath   = "TodayTrend.png"
    $chartExists = $false

    if ($todayLines.Count -gt 0) {
        $labels = $todayLines | ForEach-Object { ($_.Split(',')[0]).Split(' ')[1] }
        $data   = $todayLines | ForEach-Object { [int]($_.Split(',')[1]) }

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

        try {
            Invoke-WebRequest -Uri "https://quickchart.io/chart?c=$([uri]::EscapeDataString($chartConfig))" `
                              -OutFile $chartPath -ErrorAction Stop
            if ((Get-Item $chartPath).Length -gt 2000) { $chartExists = $true }
        } catch {
            Write-Warning "Chart generation failed: $($_.Exception.Message)"
        }
    }

    # 10) POST TO DISCORD (multipart with compact JSON)
    $jsonPayload = @{ content = $logText } | ConvertTo-Json -Compress
    try {
        if ($chartExists) {
            Invoke-RestMethod -Uri $webhookUrl -Method Post -Form @{
                payload_json = $jsonPayload
                file         = Get-Item $chartPath
            } -ErrorAction Stop
            Write-Host "✅ Discord multipart post succeeded."
        }
        else {
            throw "No chart => multipart skipped"
        }
    }
    catch {
        Write-Warning "multipart post failed: $($_.Exception.Message)"
        Write-Host "→ retrying text-only..."
        try {
            Invoke-RestMethod -Uri $webhookUrl -Method Post `
                -Body ($jsonPayload) -ContentType 'application/json' -ErrorAction Stop
            Write-Host "✅ Discord text-only post succeeded."
        }
        catch {
            Write-Error "Discord text-only retry failed: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Error "Fatal script error: $($_.Exception.Message)"
    exit 8
}
