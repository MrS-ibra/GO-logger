try {
    Write-Host "Starting scrape..."

    $url = "https://www.playgenerals.online/players"
    Write-Host "Requesting: $url"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    Write-Host "Response received."

    $html = $response.Content
    Write-Host "HTML length: $($html.Length)"

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()
    Write-Host "Extracted count: $count"

    $logPath = "lifetime_log.txt"
    $previousLine = if (Test-Path $logPath) {
        Get-Content $logPath | Where-Object { $_ -match "Total Lifetime Players:" -and $_ -match "—" } | Select-Object -Last 1
    } else {
        ""
    }

    $previousCount = if ($previousLine -match "Total Lifetime Players:") {
        ($previousLine -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
    } else {
        $count
    }

    if ([int]$count -gt [int]$previousCount) {
        $marker = " ⬆️📈🔥"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
        $line = "$timestamp  —  Total Lifetime Players: $count$marker"
        Write-Host "Log line: $line"
        Add-Content -Path $logPath -Value $line
        Write-Host "Log file updated successfully."

        # Calculate today's total growth
        $today = Get-Date -Format "yyyy-MM-dd"
        $todayLines = Get-Content $logPath | Where-Object {
            $_ -like "$today*" -and $_ -match "Total Lifetime Players:" -and $_ -match "—"
        }

        if ($todayLines.Count -ge 2) {
            $firstToday = ($todayLines[0] -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
            $lastToday  = ($todayLines[-1] -split "Total Lifetime Players:")[1].Trim() -split " " | Select-Object -First 1
            $joinedToday = [int]$lastToday - [int]$firstToday
            $summary = "A total of $joinedToday players have joined Generals Online today so far. 🎉"
            Add-Content -Path $logPath -Value $summary
            Write-Host $summary
        }
    }
    else {
        Write-Host "No increase detected. Skipping log."
    }
}
catch {
    Write-Host "ERROR OCCURRED:"
    Write-Host $_.Exception.Message
    exit 8
}
