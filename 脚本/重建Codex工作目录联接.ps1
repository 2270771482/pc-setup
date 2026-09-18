# Rebuild the junction C:\Users\22707\Documents\Codex -> D:\Codex
# Needed after a system reinstall/reset (C: gets wiped, D: keeps the data).
# ASCII only on purpose. Safe by default: refuses to touch a non-empty real directory.

$ErrorActionPreference = 'Stop'
$link = 'C:\Users\22707\Documents\Codex'
$target = 'D:\Codex'
function Say([string]$m) { Write-Host $m }

Say ('link   = ' + $link)
Say ('target = ' + $target)

if (-not (Test-Path -LiteralPath $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Say 'created target directory'
}

if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link -Force
    if ($item.LinkType -eq 'Junction') {
        Say ('already a junction -> ' + ($item.Target -join ','))
        exit 0
    }
    $count = @(Get-ChildItem -LiteralPath $link -Force -ErrorAction SilentlyContinue).Count
    if ($count -gt 0) {
        Say ('REFUSING: ' + $link + ' is a real directory with ' + $count + ' items.')
        Say ('Move its content into ' + $target + ' first, then delete it and rerun this script.')
        exit 1
    }
    Remove-Item -LiteralPath $link -Force
    Say 'removed empty directory'
}

cmd /c "mklink /J `"$link`" `"$target`"" | Out-Null

if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link -Force
    Say ('done: LinkType=' + $item.LinkType + ' Target=' + ($item.Target -join ','))
} else {
    Say 'FAILED: junction was not created'
    exit 1
}
