# docker-relocate-to-d.ps1
# Moves Docker Desktop's local data (wsl disk images + runtime socket dirs) to D:
# using directory junctions, so Docker keeps using its normal paths.
# Safe to run repeatedly: old dirs are renamed, never deleted.
# ASCII only.

$ErrorActionPreference = 'Continue'
$log = 'D:\AI\产物\docker-relocate-log.txt'
function Log([string]$m) {
    $line = (Get-Date -Format 'HH:mm:ss') + '  ' + $m
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Host $line
}

$stamp = Get-Date -Format 'HHmmss'
$local = "$env:LOCALAPPDATA\Docker"
$secrets = "$env:LOCALAPPDATA\docker-secrets-engine"
$target = 'D:\Virtual\Docker'

Log '=== relocate: start ==='

$n = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'docker' }).Count
Log ("docker processes running: $n")
if ($n -gt 0) { Log 'ABORT: Docker is still running'; exit 1 }
wsl.exe --shutdown
Start-Sleep -Seconds 3

New-Item -ItemType Directory -Path "$target\AppData" -Force | Out-Null
New-Item -ItemType Directory -Path "$target\secrets-engine" -Force | Out-Null
Log ("target ready: $target")

if (Test-Path -LiteralPath $local) {
    $isLink = (Get-Item -LiteralPath $local -Force).LinkType
    if ($isLink) { Log "already a link ($isLink), removing link only"; cmd /c "rmdir `"$local`"" | Out-Null }
    else { Rename-Item -LiteralPath $local -NewName ("Docker.old-$stamp") -ErrorAction SilentlyContinue; Log "renamed old dir -> Docker.old-$stamp" }
}
if (Test-Path -LiteralPath $secrets) {
    $isLink2 = (Get-Item -LiteralPath $secrets -Force).LinkType
    if ($isLink2) { Log "secrets already a link, removing link only"; cmd /c "rmdir `"$secrets`"" | Out-Null }
    else { Rename-Item -LiteralPath $secrets -NewName ("docker-secrets-engine.old-$stamp") -ErrorAction SilentlyContinue; Log "renamed secrets dir" }
}

$r1 = cmd /c "mklink /J `"$local`" `"$target\AppData`"" 2>&1
Log ('mklink Docker: ' + ($r1 -join ' '))
$r2 = cmd /c "mklink /J `"$secrets`" `"$target\secrets-engine`"" 2>&1
Log ('mklink secrets: ' + ($r2 -join ' '))

foreach ($p in $local, $secrets) {
    if (Test-Path -LiteralPath $p) {
        $i = Get-Item -LiteralPath $p -Force
        Log ('link check: ' + $p + ' -> ' + $i.LinkType + ' -> ' + ($i.Target -join ','))
    }
    else { Log ('MISSING: ' + $p) }
}

Log 'starting Docker Desktop'
Start-Process -FilePath 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
$d = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$up = $false
for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Seconds 10
    $v = & $d version --format '{{.Server.Version}}' 2>$null
    if ($v) { Log ("engine up: server=$v, " + (($i + 1) * 10) + 's'); $up = $true; break }
}
if (-not $up) { Log 'engine did NOT come up in 240s' }

Log 'files now under D:\Virtual\Docker'
Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending | Select-Object -First 6 |
    ForEach-Object { Log ('   ' + [math]::Round($_.Length / 1MB, 1) + ' MB  ' + $_.FullName) }

Log 'C: still has wsl dir? ' + (Test-Path -LiteralPath "$local\wsl")
Log '=== relocate: done ==='
