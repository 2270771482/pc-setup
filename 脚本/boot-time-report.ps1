# boot-time-report.ps1 -- READ ONLY.
# Reads the Windows boot-performance log (Diagnostics-Performance, Event IDs 100/101/103/109)
# and writes a report. MUST run elevated: that log's ACL allows Administrators only.
# ASCII only on purpose (PowerShell 5.1 reads .ps1 as GBK when there is no BOM).
param(
    # Where to write the report. Defaults to the folder this script lives in
    # (kept ASCII-safe so it also works when launched through UAC elevation,
    # where a non-ASCII path in the command line can get mangled).
    [string]$OutDir = $PSScriptRoot
)
$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $OutDir ('boot-time-' + $stamp + '.txt')
function L([string]$m) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
    Add-Content -LiteralPath $out -Value $line -Encoding UTF8
}
L ('=== boot time report === elevated=' + $isAdmin + ' whoami=' + (whoami))
$os = Get-CimInstance Win32_OperatingSystem
L ('last boot = ' + $os.LastBootUpTime)
if (-not $isAdmin) { L 'NOT ELEVATED - the boot performance log cannot be read.'; Write-Host ('report: ' + $out); exit 1 }
try {
    $ev = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 400 -ErrorAction Stop
} catch {
    L ('event log read failed: ' + $_.Exception.Message)
    Write-Host ('report: ' + $out)
    exit 1
}
function GetEvData([object]$e) {
    $x = [xml]$e.ToXml()
    $d = @{}
    foreach ($n in $x.Event.EventData.Data) { if ($n.Name) { $d[$n.Name] = $n.'#text' } }
    return $d
}
$boots = $ev | Where-Object { $_.Id -eq 100 } | Select-Object -First 10
L '--- boot events (newest first) ---'
foreach ($e in $boots) {
    $d = GetEvData $e
    L ('[100] ' + $e.TimeCreated.ToString('MM-dd HH:mm:ss') +
       '  total=' + [math]::Round([double]$d.BootTime / 1000, 1) + 's' +
       '  mainPath=' + [math]::Round([double]$d.MainPathBootTime / 1000, 1) + 's' +
       '  postBoot=' + [math]::Round([double]$d.BootPostBootTime / 1000, 1) + 's' +
       '  kernelInit=' + [math]::Round([double]$d.BootKernelInitTime / 1000, 1) + 's')
}
$latest = $boots | Select-Object -First 1
if ($latest) {
    $t0 = $latest.TimeCreated
    L ('--- components over 1000 ms in the boot at ' + $t0.ToString('MM-dd HH:mm:ss') + ' (101=app, 103=service, 109=device) ---')
    $rows = @()
    foreach ($e in $ev) {
        if ($e.Id -in 101, 103, 109) {
            if ([math]::Abs(($e.TimeCreated - $t0).TotalMinutes) -lt 15) {
                $d = GetEvData $e
                $ms = 0
                if ($d.TotalTime) { $ms = [int]$d.TotalTime }
                if ($ms -ge 1000) { $rows += [pscustomobject]@{ Time = $e.TimeCreated; Id = $e.Id; Name = $d.Name; Ms = $ms } }
            }
        }
    }
    $rows | Sort-Object Ms -Descending | ForEach-Object {
        L ('  [' + $_.Id + '] ' + $_.Name + '  ' + $_.Ms + ' ms')
    }
}
L '=== end ==='
Write-Host ('report: ' + $out)
