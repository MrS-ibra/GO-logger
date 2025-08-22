Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

param(
    [string]$Url      = "https://www.playgenerals.online/players",
    [string]$HistPath = "StatsHistory.txt",
    [string]$OutPath  = "NewStats.txt"
)

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [int]$MaxRetries   = 3,
        [int]$DelaySec     = 5,
        [string]$UserAgent = "TelemetryBot/1.0"
    )
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            return Invoke-WebRequest `
                -Uri $Uri `
                -UseBasicParsing `
                -TimeoutSec 30 `
                -UserAgent $UserAgent `
                -ErrorAction Stop
        }
        catch {
            if ($i -lt $MaxRetries) {
                Start-Sleep -Seconds $DelaySec
            }
            else {
                throw $_
            }
        }
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level   = "INFO",
        [string]$LogFile = "script.log"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" |
        Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Parse-Stats {
    param([string]$Html)

    # Extract and sanitize total lifetime players
    $rawCount = ($Html -split "Total Lifetime Players:")[1] -split "<" | Select-Object -First 1
    $count    = ($rawCount.Trim() -replace '[^\d]', '')
    if (-not ($count -match '^\d+$')) { throw "Invalid total players value: '$rawCount'" }

    # Extract and sanitize online players
    if ($Html -match "There are (\d+) online player") {
        $online = $matches[1] -replace '[^\d]', ''
    }
    else { $online = "0" }

    return [PSCustomObject]@{
        Count    = [int]$count
        Online   = [int]$online
        TimeOnly = (Get-Date -Format "HH:mm")
    }
}

function Update-History {
    param(
        [PSCustomObject]$Stats,
        [string]        $HistFile
    )

    # Ensure history file exists
    if (-not (Test-Path $HistFile)) {
        New-Item -Path $HistFile -ItemType File | Out-Null
    }

    # Trim to last 180 entries
    $lines = Get-Content -Path $HistFile
    if ($lines.Count -ge 180) {
        $lines = $lines[10..($lines.Count - 1)]
        Set-Content -Path $HistFile -Value $lines -Encoding UTF8
    }

    # Append new entry
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    $entry     = "$timestamp,$($Stats.Online),$($Stats.Count)"
    Add-Content -Path $HistFile -Value $entry

    # Filter today's entries
    $today      = Get-Date -Format "yyyy-MM-dd"
    $todayLines = Get-Content $HistFile | Where-Object { $_ -match "^$today" }

    # Determine peak online for today
    if ($todayLines) {
        $peakEntryLine = $todayLines |
            Sort-Object {[int]($_ -split ',')[1]} -Descending |
            Select-Object -First 1
        $parts            = $peakEntryLine -split ','
        $Stats.PeakTime   = ($parts[0] -split ' ')[1]
        $Stats.PeakCount  = [int]$parts[1]
    }
    else {
        $Stats.PeakTime  = $null
        $Stats.PeakCount = $null
    }

    # Calculate new players today (difference in total lifetime count)
    if ($todayLines.Count -ge 2) {
        $firstTotal = [int](($todayLines[0] -split ',')[2])
        $lastTotal  = [int](($todayLines[-1] -split ',')[2])
        $Stats.JoinedToday = $lastTotal - $firstTotal
    }
    else {
        $Stats.JoinedToday = 0
    }

    # Determine marker arrow based on total count growth
    $prevTotal = if ($todayLines.Count -ge 2) {
        [int](($todayLines[-2] -split ',')[2])
    }
    else {
        $Stats.Count
    }
    $Stats.Marker = if ($Stats.Count -gt $prevTotal) { " ⬆️" } else { "" }

    return $Stats
}

function Build-Message {
    param([PSCustomObject]$Stats)

    $line1 = "**━━━━━━━Time (GMT): $($Stats.TimeOnly)━━━━━━━**"
    $line2 = "👥** $($Stats.Count) ** total$($Stats.Marker)"
    $line3 = "🟢** $($Stats.Online) ** online"
    $line4 = "🆕** +$($Stats.JoinedToday) **today"

    if ($Stats.PeakCount -ne $null) {
        $line5 = "📈 Peak ** $($Stats.PeakTime) ** (GMT) — ** $($Stats.PeakCount) ** players"
    }
    else {
        $line5 = "**Today’s peak**: not recorded ❔"
    }

    return "$line1`n$line2`n$line3`n$line4`n$line5"
}

try {
    $response = Invoke-WithRetry -Uri $Url
    $html     = $response.Content
    $html | Out-File -FilePath "raw_dump.txt" -Encoding UTF8

    $stats    = Parse-Stats   -Html $html
    $stats    = Update-History -Stats $stats -HistFile $HistPath
    $message  = Build-Message  -Stats $stats

    Set-Content -Path $OutPath -Value $message -Encoding UTF8 -Force
}
catch {
    Write-Log -Message $_.Exception.Message -Level "ERROR"
    $fallback = "❌ Failed to scrape stats at $(Get-Date -Format 'u')"
    Set-Content -Path $OutPath -Value $fallback -Encoding UTF8 -Force
    exit 1
}
