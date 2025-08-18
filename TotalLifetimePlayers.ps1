try {
    Write-Host "Starting scrape..."

    $response = Invoke-WebRequest -Uri "https://www.playgenerals.online/players" -UseBasicParsing
    $html = $response.Content
    Write-Host "HTML content received."

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()
    Write-Host "Extracted count: $count"

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp — Total Lifetime Players: $count"
    Write-Host "Log line: $line"

    Set-Content -Path "$PSScriptRoot/lifetime_log.txt" -Value $line
    Write-Host "Log file written."
}
catch {
    Write-Host "❌ ERROR: $($_.Exception.Message)"
    exit 8
}
