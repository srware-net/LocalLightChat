@echo off
cd /d "nginx"
nginx.exe -s quit

taskkill /F /IM php-cgi.exe

timeout /t 1 /nobreak >nul
taskkill /F /IM nginx.exe