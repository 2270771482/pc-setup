# set-databases-manual.ps1
# Stops MySQL84 and postgresql-x64-17 and sets both to manual startup.
# MUST run elevated (UAC). ASCII only.

$ErrorActionPreference = 'Continue'
$log = 'D:\AI\产物\db-service-log.txt'
function Log([string]$m) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Host $line
}

$me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$elevated = $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log '=== set databases to manual: start ==='
Log ('elevated = ' + $elevated + ' , user = ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
if (-not $elevated) { Log 'ABORT: not elevated'; exit 1 }

foreach ($svc in 'MySQL84', 'postgresql-x64-17') {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if (-not $s) { Log ($svc + ' : not found'); continue }
    Log ($svc + ' before: ' + $s.Status + ' / ' + $s.StartType)
    try { Stop-Service -Name $svc -Force -ErrorAction Stop; Log ($svc + ' stopped') }
    catch { Log ($svc + ' stop FAILED: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 4
    try { Set-Service -Name $svc -StartupType Manual -ErrorAction Stop; Log ($svc + ' -> Manual') }
    catch { Log ($svc + ' Set-Service FAILED: ' + $_.Exception.Message) }
    $s2 = Get-Service -Name $svc -ErrorAction SilentlyContinue
    Log ($svc + ' after: ' + $s2.Status + ' / ' + $s2.StartType)
}

Start-Sleep -Seconds 2
foreach ($p in 3306, 5432) {
    $listeners = @(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
    Log ('port ' + $p + ' listeners: ' + $listeners.Count)
}
$procs = @(Get-Process mysqld, postgres -ErrorAction SilentlyContinue)
Log ('database processes left: ' + $procs.Count)
$free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
Log ('free physical memory: {0:N2} GB' -f $free)
Log '=== done ==='
