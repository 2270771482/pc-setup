@echo off
title boot time report
rem Reads the Windows boot-performance log. That log is Administrator-only,
rem so this file must be started with "Run as administrator".
rem ASCII-only on purpose: cmd.exe reads .cmd as GBK, so Chinese text inside
rem a UTF-8 file would be garbage. The Chinese folder is matched with a wildcard.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(Get-Item 'D:\AI\*\boot-time-report.ps1' -ErrorAction Stop).FullName; Write-Host ('script: ' + $s); & $s"
echo.
echo Done. The report is in the same folder as boot-time-report.ps1.
echo Press any key to close this window.
pause >nul
