# databases-start.ps1
# Starts MySQL84 and postgresql-x64-17 (they are set to manual startup).
# Re-launches itself elevated if needed. ASCII only.

$ErrorActionPreference = 'Continue'
$log = 'D:\AI\产物\db-service-log.txt'
function Log([string]$m) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Host $line
}

$me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath `
        -Verb RunAs -WindowStyle Hidden
    exit
}

Log '=== start databases (elevated) ==='
foreach ($svc in 'MySQL84', 'postgresql-x64-17') {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if (-not $s) { Log ($svc + ' not found'); continue }
    if ($s.Status -eq 'Running') { Log ($svc + ' already running'); continue }
    try { Start-Service -Name $svc -ErrorAction Stop; Log ($svc + ' started') }
    catch { Log ($svc + ' start FAILED: ' + $_.Exception.Message) }
}
Start-Sleep -Seconds 4
foreach ($svc in 'MySQL84', 'postgresql-x64-17') {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    Log ($svc + ' now: ' + $s.Status + ' / ' + $s.StartType)
}
foreach ($p in 3306, 5432) {
    $listeners = @(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
    Log ('port ' + $p + ' listeners: ' + $listeners.Count)
}
Log '=== done ==='
