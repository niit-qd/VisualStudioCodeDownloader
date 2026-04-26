@echo off
chcp 65001 >nul
:: 临时放行策略，只本次生效，不改系统全局
:: 先清空变量
set "version="
:: 强制读取第一个参数，去引号
set "version=%~1"
echo version = %version%
if "%version%"=="" (
    powershell -ExecutionPolicy Bypass -File "download.ps1"
) else (
    powershell -ExecutionPolicy Bypass -File "download.ps1" %version%
)