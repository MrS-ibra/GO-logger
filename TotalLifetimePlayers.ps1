try {
    Write-Host "▶ Starting scrape..."

    $url = "https://www.playgenerals.online/players"
    Write-Host "🔗 Requesting: $url"

    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ Response received."

    $html = $response.Content
    Write-Host "📄 HTML length: $($html.Length)"

    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = $count.Trim()
    Write-Host "🎯 Extracted count: $count"

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp — Total Lifetime Players: $count"
    Write-Host "📝 Log line: $line"

    # GitHub Actions repo path
    $repoRoot = Join-Path $env:GITHUB_WORKSPACE ""
    $logPath = Join-Path $repoRoot "lifetime_log.txt"
    Write-Host "📁 Writing to: $logPath"

    Set-Content -Path $logPath -Value $line
    Write-Host "✅ Log file written successfully."
}
catch {
    Write-Host "❌ ERROR OCCURRED:"
    Write-Host "$($_.Exception | Format-List -Force)"
    exit 8
}
