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
    Write-Host "Fetching: $url"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Lifetime count
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
    $html = $response.Content
    $count = [regex]::Match($html, "Total Lifetime Players:\s*(\d+)").Groups[1].Value
    $count = [int]$count

    $previousLine = if (Test-Path $log) {
        Get-Content $log | Where-Object { $_ -match "Total Lifetime Players:" } | Select-Object -Last 1
    } else {
        ""
    }

    if ($previousLine -match "\d+$") {
        $previousCount = [int]($previousLine -replace "[^\d]+", "")
    } else {
        $previousCount = $count
    }

    $marker = if ($count -gt $previousCount) { " ⬆️📈🔥" } else { "" }
    $header = "$timestamp — Total Lifetime Players: $count$marker"

    Add-Content $log ""
    Add-Content $log $header
    Write-Host $header

    # Player list
    $players = GetPlayers
    $players = $players | Sort-Object

    for ($i = 0; $i -lt $players.Count; $i++) {
        $line = "$($i + 1). $($players[$i])"
        Add-Content $log $line
        Write-Host $line
    }

    Write-Host "Log updated at: $log"
}
catch {
    Write-Host "ERROR OCCURRED:"
    Write-Host $_.Exception.Message
    exit 8
}
