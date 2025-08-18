$log = "lifetime_log.txt"
$url = "https://www.playgenerals.online/players"
$useEmoji = $true

function GetPlayers {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
    $html = $response.Content

    $rows = ($html -split "<tr") | Where-Object { $_ -match "<td>" -or $_ -match "<th>" }

    $names = @()
    foreach ($row in $rows) {
        $cells = ($row -split "<t[dh].*?>") | Select-Object -Skip 1
        $decoded = $cells | ForEach-Object {
            [System.Web.HttpUtility]::HtmlDecode(($_ -split "</t[dh]>")[0].Trim())
        }
        if ($decoded.Count -ge 1) {
            $name = $decoded[0]
            $names += $name
        }
    }

    return $names
}

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Lifetime count
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    $count = ($html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count = [int]$count.Trim()

    $previousLine = if (Test-Path $log) { Get-Content $log | Where-Object { $_ -match "Total Lifetime Players:" } | Select-Object -Last 1 } else { "" }
    $previousCount = if ($previousLine -match "\d+$") { [int]($previousLine -replace "[^\d]+", "") } else { $
