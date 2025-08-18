$response = Invoke-WebRequest -Uri "https://www.playgenerals.online/players" -UseBasicParsing
$html = $response.Content

$count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
$count = $count.Trim()

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$line = "$timestamp — Total Lifetime Players: $count"

Set-Content -Path "$PSScriptRoot/lifetime_log.txt" -Value $line
