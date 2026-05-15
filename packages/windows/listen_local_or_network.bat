REM listen_local_or_network.bat
@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
echo ========================================
echo   NGINX Network Configuration
echo ========================================
echo.
echo Select listening mode:
echo.
echo [1] Local only (127.0.0.1) - accessible from this machine only
echo [2] Network access (0.0.0.0) - accessible from other devices
echo.
set /p choice="Enter your choice (1 or 2): "

if "!choice!"=="1" goto local
if "!choice!"=="2" goto network
goto invalid

:local
powershell -Command "$config = Get-Content nginx\conf\nginx.conf -Raw; $config = $config -replace '(?m)^(\s*)listen\s+(?:0\.0\.0\.0|127\.0\.0\.1)?:?8081;', '$1listen       127.0.0.1:8081;'; $config = $config -replace '(?m)^(\s*)listen\s+(?:0\.0\.0\.0|127\.0\.0\.1)?:?8082\s+ssl;', '$1listen       127.0.0.1:8082 ssl;'; $config | Set-Content nginx\conf\nginx.conf -NoNewline"
echo.
echo Configuration updated:
echo   HTTP:  127.0.0.1:8081
echo   HTTPS: 127.0.0.1:8082
goto end

:network
powershell -Command "$config = Get-Content nginx\conf\nginx.conf -Raw; $config = $config -replace '(?m)^(\s*)listen\s+(?:0\.0\.0\.0|127\.0\.0\.1)?:?8081;', '$1listen       0.0.0.0:8081;'; $config = $config -replace '(?m)^(\s*)listen\s+(?:0\.0\.0\.0|127\.0\.0\.1)?:?8082\s+ssl;', '$1listen       0.0.0.0:8082 ssl;'; $config | Set-Content nginx\conf\nginx.conf -NoNewline"
echo.
echo Configuration updated:
echo   HTTP:  0.0.0.0:8081 (network accessible)
echo   HTTPS: 0.0.0.0:8082 (network accessible)
goto end

:invalid
echo.
echo Invalid choice. Configuration unchanged.

:end
echo.
echo Press any key to exit...
pause >nul