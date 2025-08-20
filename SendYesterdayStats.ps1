$dailyLogPath = "daily_totals.txt"
if (-not (Test-Path $dailyLogPath)) { exit }

$lines = Get-Content $dailyLogPath | Where-Object { ($_ -split ",").Count -ge 3 }
if ($lines.Count -lt 2) { exit }

# Get yesterday and day-before-yesterday entries
$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
$dayBefore = (Get-Date).AddDays(-2).ToString("yyyy-MM-dd")

$yesterdayEntry = $lines | Where-Object { $_ -match "^$yesterday" } | Select-Object -Last 1
$dayBeforeEntry = $lines | Where-Object { $_ -match "^$dayBefore" } | Select-Object -Last 1

if ($yesterdayEntry -and $dayBeforeEntry) {
    $yesterdayCount = [int]($yesterdayEntry -split ",")[2]
    $dayBeforeCount = [int]($dayBeforeEntry -split ",")[2]
    $joinedYesterday = $yesterdayCount - $dayBeforeCount

    $message = "**📊 Yesterday’s new players**: +$joinedYesterday"
} else {
    $message = "**📊 Yesterday’s new players**: data incomplete ❔"
}

# Send to Discord
$webhook = "${env:DISCORD_WEBHOOK}"
Invoke-RestMethod -Uri $webhook -Method Post -ContentType "application/json" -Body (@{ content = $message } | ConvertTo-Json)
