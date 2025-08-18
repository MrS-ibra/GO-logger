try {
    Write-Host "Starting scrape..."

    $url = "https://www.playgenerals.online/players"
    Write-Host "Requesting: $url"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    Write-Host "Response received."

    $html = $response.Content
    Write-Host "HTML length: $($html.Length)"

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = [int]$count.Trim()
    Write-Host "Extracted count: $count"

    $logPath = "lifetime_log.txt"
    $previousLine = if (Test-Path $logPath) { Get-Content $logPath | Select-Object -Last 1 } else { "" }
    $previousCount = if ($previousLine -match "\d+$") { [int]($previousLine -replace "[^\d]+", "") } else { $count }

    $marker = if ($count -gt $previousCount) { " ⬆️📈🔥" } else { "" }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp — Total Lifetime Players: $count$marker"
    Write-Host "Log line: $line"

    Add-Content -Path $logPath -Value $line
    Write-Host "Log file updated successfully."
}
catch {
    Write-Host "ERROR OCCURRED:"
    Write-Host $_.Exception.Message
    exit 8
}
