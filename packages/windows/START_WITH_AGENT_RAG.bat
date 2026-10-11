@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM 0) REQUIRE VC++ (x64) FIRST (hard stop with pause)
REM ============================================================
set "VC_MIN=14.40.0.0"
call :require_vc_redist_x64 "%VC_MIN%"
if errorlevel 1 (
  echo.
  echo Please install VC_redist.x64.exe first
  echo.
  pause
  exit /b 1
)

REM --- Self-call for background update ---
if /i "%~1"=="__update_cacert__" goto :update_cacert

REM ============================================================
REM 1) PATHS
REM ============================================================
set "ROOT=%~dp0"
set "PHPDIR=%ROOT%php"
set "NGINXDIR=%ROOT%nginx"
set "PATCHER=%PHPDIR%\PatchPHPConfig.exe"

REM ============================================================
REM 2) PATCH php.ini with Lazarus tool
REM ============================================================
if exist "%PATCHER%" (
  "%PATCHER%"
) else (
  echo [WARN] PatchPHPConfig.exe not found - skipping INI patch
)

REM ============================================================
REM 3) START SERVICES
REM ============================================================
cd /d "%ROOT%"
start "PHP-CGI" /MIN cmd /c "cd /d ""%PHPDIR%"" && php-cgi.exe -b 127.0.0.1:9002"
start "nginx"   /MIN cmd /c "cd /d ""%NGINXDIR%"" && nginx.exe"
start "RAG"     /MIN cmd /c "cd /d ""%ROOT%rag"" && ragd.exe"
start "MCP"     /MIN cmd /c "cd /d ""%ROOT%mcp\server"" && mcp_server.exe"

REM Background updater (does not block)
start "CA-UPDATE" /MIN cmd /c ""%~f0" __update_cacert__"

timeout /t 1 /nobreak >nul
start http://127.0.0.1:8081
exit /b 0


:require_vc_redist_x64
setlocal EnableExtensions EnableDelayedExpansion
set "MIN=%~1"
if not defined MIN set "MIN=14.40.0.0"

set "K1=HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
set "K2=HKLM\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"

set "VER="
for %%K in ("%K1%" "%K2%") do (
  for /f "tokens=2,*" %%A in ('reg query "%%~K" /v Version 2^>nul ^| find /i "Version"') do (
    set "VER=%%B"
  )
  if defined VER goto :got_ver_vc
)
:got_ver_vc

if not defined VER (
  endlocal & exit /b 1
)

set "VER=!VER:v=!"
for /f "tokens=1-4 delims=." %%a in ("!VER!") do set "VERN=%%a.%%b.%%c.%%d"
for /f "tokens=1-4 delims=." %%a in ("%MIN%") do set "MINN=%%a.%%b.%%c.%%d"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$v=[version]'!VERN!'; $m=[version]'!MINN!'; if($v -lt $m){ exit 1 } else { exit 0 }" >nul 2>nul

if errorlevel 1 ( endlocal & exit /b 1 )
endlocal & exit /b 0


:update_cacert
setlocal EnableExtensions

set "ROOT=%~dp0"
set "PHPDIR=%ROOT%php"
set "CERTDIR=%PHPDIR%\cert"
set "CERTFILE=%CERTDIR%\cert.pem"
set "ETAG=%CERTDIR%\cert.etag"
set "TMP=%CERTDIR%\cert.tmp"
set "LOG=%CERTDIR%\cert_update.log"
set "URL=https://curl.se/ca/cacert.pem"

if not exist "%CERTDIR%" mkdir "%CERTDIR%" >nul 2>&1

REM Rotate log
if exist "%LOG%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$p='%LOG%';" ^
    "try { $lines=Get-Content -LiteralPath $p -ErrorAction Stop; if($lines.Count -gt 2000){ $lines = $lines[-2000..-1]; Set-Content -LiteralPath $p -Value $lines -Encoding UTF8 } } catch { }" >nul 2>nul
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
  "$url='%URL%'; $tmp='%TMP%'; $cert='%CERTFILE%'; $etag='%ETAG%'; $log='%LOG%';" ^
  "function Log($m){ Add-Content -LiteralPath $log -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')+'  '+$m) -Encoding UTF8 }" ^
  "Log('--- update start ---');" ^
  "New-Item -ItemType Directory -Force -Path (Split-Path $cert) | Out-Null;" ^
  "if(Test-Path $tmp){ Remove-Item -LiteralPath $tmp -Force }" ^
  "$h=@{}; $oldETag=$null;" ^
  "if((Test-Path $cert) -and (Test-Path $etag)){" ^
  "  $oldETag=(Get-Content -LiteralPath $etag -Raw -ErrorAction SilentlyContinue).Trim();" ^
  "  if($oldETag){ $h['If-None-Match']=$oldETag; Log('If-None-Match: '+$oldETag) }" ^
  "}" ^
  "try {" ^
  "  $wr=[System.Net.HttpWebRequest]::Create($url);" ^
  "  foreach($k in $h.Keys){ $wr.Headers.Add($k, $h[$k]) }" ^
  "  $wr.UserAgent='Mozilla/5.0';" ^
  "  $resp=$wr.GetResponse();" ^
  "  $statusCode=[int]$resp.StatusCode;" ^
  "  $newETag=$resp.Headers['ETag'];" ^
  "  Log('HTTP '+$statusCode);" ^
  "  if($statusCode -eq 304){ Log('Not modified'); $resp.Close(); exit 0 }" ^
  "  $stream=$resp.GetResponseStream();" ^
  "  $fs=[System.IO.File]::Create($tmp);" ^
  "  $stream.CopyTo($fs);" ^
  "  $fs.Close(); $stream.Close(); $resp.Close();" ^
  "  if($newETag){ Set-Content -LiteralPath $etag -Value $newETag -Encoding ascii -NoNewline; Log('ETag saved: '+$newETag) }" ^
  "} catch [System.Net.WebException] {" ^
  "  $we=$_.Exception;" ^
  "  if($we.Response){" ^
  "    $sc=[int]$we.Response.StatusCode;" ^
  "    if($sc -eq 304){ Log('Not modified (304)'); exit 0 }" ^
  "    Log('WebException: '+$sc+' '+$we.Message);" ^
  "  } else { Log('WebException: '+$we.Message) }" ^
  "  exit 0" ^
  "} catch { Log('Error: '+$_.Exception.Message); exit 0 }" ^
  "$fi=Get-Item -LiteralPath $tmp -ErrorAction SilentlyContinue;" ^
  "if(-not $fi){ Log('TMP missing'); exit 0 }" ^
  "$sz=$fi.Length; Log('Size: '+$sz);" ^
  "if($sz -lt 102400 -or $sz -gt 512000){ Log('Size invalid'); Remove-Item -LiteralPath $tmp -Force; exit 0 }" ^
  "if(-not (Select-String -LiteralPath $tmp -Pattern 'BEGIN CERTIFICATE' -Quiet)) { Log('PEM check failed'); Remove-Item -LiteralPath $tmp -Force; exit 0 }" ^
  "Move-Item -LiteralPath $tmp -Destination $cert -Force; Log('Updated cert.pem');" ^
  "Log('--- done ---');" 1>nul 2>nul

exit /b 0