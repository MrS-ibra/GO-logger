try {
    $url = "https://www.playgenerals.online/players"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    $html | Out-File -FilePath "raw_dump.txt"

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()

    $online = if ($html -match "There are (\d+) online player") { $matches[1] } else { "0" }

    $logPath = "lifetime_log.txt"
    $peakLog = "peak_log.txt"

    if (Test-Path $peakLog) {
        $logLines = Get-Content $peakLog
        if ($logLines.Count -ge 180) {
            $logLines = $logLines[10..($logLines.Count - 1)]
            Set-Content -Path $peakLog -Value $logLines
        }
    }

    Add-Content -Path $peakLog -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm'),$online,$count"

    $peakLogLines = Get-Content $peakLog
    $today = Get-Date -Format "yyyy-MM-dd"
    $peakTodayLines = $peakLogLines | Where-Object {
        $_ -match "^$today" -and ($_ -split ",").Count -ge 3
    }

    $peakEntry = $peakTodayLines | Sort-Object { ($_ -split ",")[1] -as [int] } -Descending | Select-Object -First 1
    $peakCount = if ($peakEntry) {
        ($peakEntry -split ",")[1]
    } else {
        "N/A"
    }

    $joinedToday = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-1] -split ",")[2]) - [int](($peakTodayLines[0] -split ",")[2])
    } else { 0 }

    $previousCount = if ($peakTodayLines.Count -ge 2) {
        [int](($peakTodayLines[-2] -split ",")[2])
    } else {
        [int]$count
    }

    $marker = if ([int]$count -gt $previousCount) { "⬆️" } else { "" }

    $timeOnly = Get-Date -Format "HH:mm"

    $summary = @" 
    ```
━━━━━━━ Player Stats ━━━━━━━

| Time (GMT) | Online | Total     | New Today | Peak |
|------------|--------|-----------|-----------|------|
| $timeOnly  | $online | $count $marker | +$joinedToday | $peakCount |
```
"@

    Set-Content -Path $logPath -Value $summary -Force
}
catch {
    $logPath = "lifetime_log.txt"
    $message = @"
━━━━━━━━━━━━━━━━━━━━━━
❌ Failed: site unreachable or error occurred
━━━━━━━━━━━━━━━━━━━━━━
"@
    Set-Content -Path $logPath -Value $message -Force
    exit 8
}
