# Runs separately and non-interactively after service startup.
# Retains the old START.bat behavior: ETag, size/PEM validation and bounded log.
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$folder = Join-Path $Root 'php\cert'
$cert = Join-Path $folder 'cert.pem'
$etagFile = Join-Path $folder 'cert.etag'
$tmp = Join-Path $folder 'cert.tmp'
$logFile = Join-Path $folder 'cert_update.log'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
if (Test-Path -LiteralPath $logFile) {
    try {
        $tail = @(Get-Content -LiteralPath $logFile -ErrorAction Stop | Select-Object -Last 2000)
        [System.IO.File]::WriteAllLines($logFile, [string[]]$tail)
    } catch { }
}
function Log([string]$message) {
    Add-Content -LiteralPath $logFile -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $message) -Encoding UTF8
}
Log '--- update start ---'
try {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $req = [System.Net.HttpWebRequest]::Create('https://curl.se/ca/cacert.pem')
    $req.UserAgent = 'LocalLightChat-Manager/0.1'
    $req.Timeout = 15000
    $req.ReadWriteTimeout = 15000
    if ((Test-Path -LiteralPath $cert) -and (Test-Path -LiteralPath $etagFile)) {
        $oldETag = (Get-Content -LiteralPath $etagFile -Raw).Trim()
        if ($oldETag) { $req.Headers.Add('If-None-Match', $oldETag) }
    }
    try {
        $response = $req.GetResponse()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 304) {
            Log 'Not modified (304)'; exit 0
        }
        throw
    }
    try {
        $status = [int]$response.StatusCode
        if ($status -ne 200) { Log ('HTTP ' + $status); exit 0 }
        $newETag = $response.Headers['ETag']
        $inputStream = $response.GetResponseStream()
        $outputStream = [System.IO.File]::Create($tmp)
        try { $inputStream.CopyTo($outputStream) }
        finally { $outputStream.Dispose(); $inputStream.Dispose() }
    } finally { $response.Dispose() }
    $size = (Get-Item -LiteralPath $tmp).Length
    if ($size -lt 102400 -or $size -gt 512000) {
        Log ('Rejected: invalid size ' + $size); exit 0
    }
    if (-not (Select-String -LiteralPath $tmp -Pattern 'BEGIN CERTIFICATE' -Quiet)) {
        Log 'Rejected: PEM validation'; exit 0
    }
    Move-Item -LiteralPath $tmp -Destination $cert -Force
    if ($newETag) { [System.IO.File]::WriteAllText($etagFile, $newETag) }
    else { Remove-Item -LiteralPath $etagFile -Force -ErrorAction SilentlyContinue }
    Log ('Updated cert.pem (' + $size + ' bytes)')
} catch {
    Log ('CA update failed: ' + $_.Exception.Message)
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
