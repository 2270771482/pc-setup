# restore-known-folders.ps1
# Run as the normal user (no admin required).
# - moves loose documents out of D:\Downloads
# - merges the leftover folders of the old C: profile into D:\Documents
# - re-applies the D: redirect for the shell folders Documents and Downloads
# - removes the empty leftovers
# ASCII only on purpose: PowerShell 5.1 mis-decodes non-ASCII files without a BOM.

$ErrorActionPreference = 'Continue'
$logDir = 'D:\AI\产物'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir 'known-folders-log.txt'

function Log([string]$m) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Host $line
}

$cDoc = 'C:\Users\22707\Documents'
$dDoc = 'D:\Documents'
$cDl = 'C:\Users\22707\Downloads'
$dDl = 'D:\Downloads'

Log '=== restore known folders: start ==='

# ---------------------------------------------------------------- 1. loose docs
$docDest = 'D:\AI\文档'
New-Item -ItemType Directory -Path $docDest -Force | Out-Null
Get-ChildItem -LiteralPath 'D:\Downloads' -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.md' } |
    ForEach-Object {
        $target = Join-Path $docDest $_.Name
        Move-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Continue
        if (Test-Path -LiteralPath $target) { Log ('moved file  ' + $_.Name + ' -> ' + $docDest) }
        else { Log ('FAILED move ' + $_.FullName) }
    }

$logDest = 'D:\AI\产物\logs'
New-Item -ItemType Directory -Path $logDest -Force | Out-Null
Get-ChildItem -LiteralPath 'D:\Downloads\Installers' -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.txt' } |
    ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination $logDest -Force -ErrorAction Continue
    }
Log ('installer logs moved to ' + $logDest + ' : ' + ((Get-ChildItem -LiteralPath $logDest -File -ErrorAction SilentlyContinue | Measure-Object).Count) + ' files')

# remove the empty non-ASCII folder that an earlier attempt may have created
Get-ChildItem -LiteralPath $logDir -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '^[A-Za-z0-9_\-\.]+$' } |
    ForEach-Object {
        $n = (Get-ChildItem -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($n -eq 0) { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue; Log ('removed empty dir ' + $_.FullName) }
    }

# ------------------------------------------------------- 2. merge old profile
if (Test-Path -LiteralPath $cDoc) {
    Get-ChildItem -LiteralPath $cDoc -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $target = Join-Path $dDoc $_.Name
        if ($_.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target)) {
                Move-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Continue
                Log ('moved dir   ' + $_.FullName + ' -> ' + $target)
            }
            else {
                Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $t2 = Join-Path $target $_.Name
                    if (-not (Test-Path -LiteralPath $t2)) {
                        Move-Item -LiteralPath $_.FullName -Destination $t2 -Force -ErrorAction Continue
                        Log ('moved       ' + $_.FullName + ' -> ' + $t2)
                    }
                    else {
                        Log ('kept both   ' + $t2 + ' already exists, source kept at ' + $_.FullName)
                    }
                }
            }
        }
        else {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Continue
            Log ('copied file ' + $_.FullName + ' -> ' + $target)
        }
    }
}
else { Log ('no old profile folder at ' + $cDoc) }

# ------------------------------------------------------ 3. redirect the folders
$typeDef = @'
using System;
using System.Runtime.InteropServices;
public static class KFolders {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHSetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, string pszPath);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHGetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, out IntPtr ppszPath);
}
'@
Add-Type -TypeDefinition $typeDef -ErrorAction SilentlyContinue

$targets = @(
    @{ name = 'Documents'; id = 'FDD39AD0-238F-46AF-ADB4-6C85480369C7'; path = $dDoc; reg = 'Personal' },
    @{ name = 'Downloads'; id = '374DE290-123F-4565-9164-39C4925E467B'; path = $dDl; reg = '{374DE290-123F-4565-9164-39C4925E467B}' }
)

$ushKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$resKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'

foreach ($t in $targets) {
    New-Item -ItemType Directory -Path $t.path -Force | Out-Null
    $guid = [System.Guid]::Parse($t.id)
    $hr = 0
    try { $hr = [KFolders]::SHSetKnownFolderPath([ref]$guid, 0, [System.IntPtr]::Zero, $t.path) }
    catch { $hr = -1 }
    Log ('SHSetKnownFolderPath ' + $t.name + ' -> ' + $t.path + ' hr=' + $hr)

    # belt and braces: write the registry values the shell actually reads
    New-Item -Path $ushKey -Force | Out-Null
    Set-ItemProperty -Path $ushKey -Name $t.reg -Value $t.path -ErrorAction SilentlyContinue
    # only refresh the resolved copy that already exists, never create it half filled
    if (Test-Path -Path $resKey) {
        Set-ItemProperty -Path $resKey -Name $t.reg -Value $t.path -ErrorAction SilentlyContinue
    }
    $back = (Get-ItemProperty -Path $ushKey -Name $t.reg -ErrorAction SilentlyContinue).$($t.reg)
    Log ('registry ' + $t.reg + ' = ' + $back)
}

# --------------------------------------------------------------- 4. verify
foreach ($t in $targets) {
    $guid = [System.Guid]::Parse($t.id)
    $ptr = [System.IntPtr]::Zero
    $hr = [KFolders]::SHGetKnownFolderPath([ref]$guid, 0, [System.IntPtr]::Zero, [ref]$ptr)
    $p = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    Log ('verify ' + $t.name + ' = ' + $p + ' (hr=' + $hr + ')')
}

# --------------------------------------------------- 5. drop empty leftovers
foreach ($p in $cDoc, $cDl) {
    if (Test-Path -LiteralPath $p) {
        $n = (Get-ChildItem -LiteralPath $p -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($n -eq 0) {
            Remove-Item -LiteralPath $p -Force -Recurse -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $p) { Log ('leftover kept (in use or locked): ' + $p) }
            else { Log ('removed empty leftover ' + $p) }
        }
        else { Log ('leftover not empty, kept: ' + $p + ' items=' + $n) }
    }
}

$oldProjects = 'D:\Projects\PC-Setup'
if (Test-Path -LiteralPath $oldProjects) {
    $n = (Get-ChildItem -LiteralPath $oldProjects -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($n -eq 0) { Remove-Item -LiteralPath $oldProjects -Force -Recurse -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $oldProjects) { Log ('kept (not empty): ' + $oldProjects) } else { Log ('removed empty leftover ' + $oldProjects) }
}

Log '=== restore known folders: done ==='
