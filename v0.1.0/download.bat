@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -File "download.ps1" %*
pause
