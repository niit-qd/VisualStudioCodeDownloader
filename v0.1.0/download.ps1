# VSCode Downloader - With Progress, File Verification, Status in Target Dir, i18n
Add-Type -AssemblyName System.Web

# Fix console encoding for emoji/Unicode output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$SCRIPT_VERSION = "0.1.0"

# Emoji constants (avoid encoding issues in PS1 file)
$E_FILE = [char]::ConvertFromUtf32(0x1F4C4)
$E_VER  = [char]::ConvertFromUtf32(0x1F3F7) + [char]0xFE0F
$E_DIR  = [char]::ConvertFromUtf32(0x1F4C1)
$E_LOG  = [char]::ConvertFromUtf32(0x1F4CB)
$E_TRY  = [char]::ConvertFromUtf32(0x1F504)
$E_WAIT = [char]::ConvertFromUtf32(0x23F1) + [char]0xFE0F
$E_RES  = [char]0x25B6 + [char]0xFE0F
$E_CHK  = [char]0x2705
$E_OK   = [char]0x2705
$E_WAIT2 = [char]::ConvertFromUtf32(0x23F3)

$jsonFilePath = "data.json"
$i18nDir = "i18n"
$version = "latest"
$command = "download"
$lang = ""
$maxRetries = -1
$retryDelaySeconds = 3
$resumeEnabled = $true
$silentMode = $false

# Parse arguments
foreach ($arg in $args) {
    if ($arg -match "^--command=?(.*)$") {
        $val = $Matches[1].Trim()
        if ($val) { $command = $val.ToLower() }
    }
    elseif ($arg -match "^--version=?(.*)$") {
        $val = $Matches[1].Trim()
        if ($val) { $version = $val }
    }
    elseif ($arg -match "^--lang=?(.*)$") {
        $val = $Matches[1].Trim()
        if ($val) { $lang = $val.ToLower() }
    }
    elseif ($arg -eq "--silent") {
        $silentMode = $true
    }
}

# ========== i18n ==========
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$i18n = @{}

function Load-I18n {
    param([string]$Lang)
    $i18nFile = Join-Path $scriptDir "$i18nDir\$Lang.json"
    if (-not (Test-Path $i18nFile)) { return }
    try {
        $content = Get-Content -Path $i18nFile -Raw -Encoding UTF8
        $langData = $content | ConvertFrom-Json
        foreach ($prop in $langData.PSObject.Properties) {
            $i18n[$prop.Name] = $prop.Value
        }
    }
    catch {
        Write-Warning "Failed to load i18n file: $_"
    }
}

# Extract version from title (e.g., "v3.0" from "VSCode Downloader v3.0 - Enhanced")
function Detect-Lang {
    # Detect system language
    $culture = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
    if ($culture -match "^zh") { return "zh" }
    return "en"
}

function T {
    $key = $args[0]
    if ($i18n.ContainsKey($key)) {
        $text = $i18n[$key]
        for ($i = 1; $i -lt $args.Count; $i++) {
            $text = $text.Replace("{$($i-1)}", "$($args[$i])")
        }
        return $text
    }
    return $key
}

# Determine language: --lang > system detect > default en
if ($lang) {
    Load-I18n -Lang $lang
    if ($i18n.Count -eq 0) {
        # Requested lang not found, fallback to system
        $lang = Detect-Lang
        Load-I18n -Lang $lang
    }
} else {
    $lang = Detect-Lang
    Load-I18n -Lang $lang
}

$downloadRoot = "../$version"
$statusFile = Join-Path $downloadRoot "download_status.json"

$totalCount = 0
$successCount = 0
$failCount = 0
$ignoreCount = 0
$skipCount = 0
$failedItems = @()
$successItems = @()
$newSuccessCount = 0
$newSkipCount = 0

function Load-DownloadStatus {
    if ($resumeEnabled -and (Test-Path $statusFile)) {
        try {
            $content = Get-Content -Path $statusFile -Raw -Encoding UTF8
            $status = $content | ConvertFrom-Json
            return ConvertTo-Hashtable -Object $status
        }
        catch {
            Write-Warning "$(T 'load_status_failed'): $_"
        }
    }
    return $null
}

function Save-DownloadStatus {
    param([object]$Status)
    if ($resumeEnabled) {
        try {
            $dir = Split-Path $statusFile -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $obj = ConvertTo-PSCustomObject -Hash $Status
            $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $statusFile -Encoding UTF8
        }
        catch {
            Write-Warning "$(T 'save_status_failed'): $_"
        }
    }
}

function ConvertTo-Hashtable {
    param([object]$Object)
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) { return $Object }
    if ($Object -is [System.Collections.ICollection]) {
        $result = @()
        foreach ($item in $Object) { $result += ConvertTo-Hashtable -Object $item }
        return $result
    }
    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        $Object.PSObject.Properties | ForEach-Object {
            $hash[$_.Name] = ConvertTo-Hashtable -Object $_.Value
        }
        return $hash
    }
    return $Object
}

function ConvertTo-PSCustomObject {
    param([object]$Hash)
    if ($null -eq $Hash) { return $null }
    if ($Hash -is [hashtable]) {
        $obj = New-Object PSObject
        $Hash.GetEnumerator() | ForEach-Object {
            $obj | Add-Member -NotePropertyName $_.Key -NotePropertyValue (ConvertTo-PSCustomObject -Hash $_.Value)
        }
        return $obj
    }
    return $Hash
}

function Get-LocalFileSize {
    param([string]$FilePath)
    if (Test-Path $FilePath) { return (Get-Item $FilePath).Length }
    return -1
}

function Mark-DownloadCompleted {
    param([string]$Version, [string]$FolderName, [string]$FileName, [long]$FileSize)
    $status = Load-DownloadStatus
    if ($null -eq $status) { $status = @{} }
    if ($null -eq $status.$Version) { $status.$Version = @{} }
    $status.$Version.($FolderName) = @{
        completed = $true
        fileName = $FileName
        fileSize = $FileSize
        completedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    Save-DownloadStatus -Status $status
}

function Reset-DownloadStatus {
    param([string]$Version)
    $status = Load-DownloadStatus
    if ($null -ne $status -and $null -ne $status.$Version) {
        $status.$Version = @{}
        Save-DownloadStatus -Status $status
        Write-Host (T 'reset_done' $Version) -ForegroundColor Yellow
    }
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -lt 0) { return "Unknown" }
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    if ($Bytes -lt 1GB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    return "{0:N2} GB" -f ($Bytes / 1GB)
}

function Do-Exit {
    param([int]$Code)
    if (-not $silentMode) {
        Write-Host ""
        Write-Host (T 'press_enter') -ForegroundColor Gray
        [Console]::ReadLine() | Out-Null
    }
    exit $Code
}

# ========== Show config ==========
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "       $(T 'title' $SCRIPT_VERSION)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  $E_FILE $(T 'config_file'): $jsonFilePath"
Write-Host "  $E_VER  $(T 'version_label'):  $version"
Write-Host "  $E_DIR $(T 'download_to'): $downloadRoot"
Write-Host "  $E_LOG $(T 'status_file'): $statusFile"
Write-Host "  $E_TRY $(T 'max_retries'): $(if ($maxRetries -eq -1) { T 'infinite' } else { $maxRetries })"
Write-Host "  $E_WAIT $(T 'retry_delay'): ${retryDelaySeconds}s"
Write-Host "  $E_RES  $(T 'resume'):      $(if ($resumeEnabled) { T 'enabled' } else { T 'disabled' })"
Write-Host "  $E_CHK  $(T 'verify'):      $(T 'file_size_check')"
Write-Host ""
[Console]::Out.Flush()

New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

# ========== Mutex ==========
$lockDir = Join-Path $downloadRoot ".download.lock"

# Check for stale lock before attempting mkdir
if (Test-Path $lockDir) {
    $pidFile = Join-Path $lockDir "pid"
    $oldPidStr = ""
    if (Test-Path $pidFile) {
        $oldPidStr = (Get-Content $pidFile -Raw -ErrorAction Stop).Trim()
    }
    if ($oldPidStr -match '^\d+$') {
        $oldPid = [int]$oldPidStr
        $pidAlive = $false
        try {
            $p = Get-Process -Id $oldPid -ErrorAction Stop
            if ($null -ne $p) { $pidAlive = $true }
        } catch { }
        if (-not $pidAlive) {
            Write-Host "[INFO] $(T 'stale_lock_cleaned' $oldPid)" -ForegroundColor Yellow
            Remove-Item $lockDir -Recurse -Force
        }
    } else {
        # No valid PID file, lock is stale
        Remove-Item $lockDir -Recurse -Force
    }
}

try {
    New-Item -ItemType Directory -Path $lockDir -ErrorAction Stop | Out-Null
}
catch {
    Write-Host (T 'another_instance') -ForegroundColor Red
    Write-Host (T 'another_instance_tip' $lockDir) -ForegroundColor Yellow
    Do-Exit 1
}
# Write current PID
Set-Content -Path (Join-Path $lockDir "pid") -Value $PID -NoNewline
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if (Test-Path $lockDir) { Remove-Item $lockDir -Recurse -Force }
}

# ========== Handle commands ==========
if ($command -eq "reset") {
    Reset-DownloadStatus -Version $version
    Do-Exit 0
}

if ($command -eq "status") {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "           $(T 'download_status_title')" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    $status = Load-DownloadStatus
    if ($null -ne $status) {
        $versionStatus = $status.$version
        if ($null -ne $versionStatus) {
            $completed = 0
            $total = 0
            foreach ($key in $versionStatus.Keys) {
                $total++
                if ($versionStatus.$key.completed -eq $true) { $completed++ }
            }
            Write-Host ""
            Write-Host "  $E_OK $(T 'completed_count' $completed $total)" -ForegroundColor Green
            Write-Host ""
            foreach ($key in $versionStatus.Keys) {
                $item = $versionStatus.$key
                $statusIcon = if ($item.completed) { $E_OK } else { $E_WAIT2 }
                $sizeStr = if ($item.fileSize) { Format-FileSize $item.fileSize } else { "Unknown" }
                Write-Host "  $statusIcon $key" -ForegroundColor $(if ($item.completed) { "Green" } else { "Yellow" })
                Write-Host "      $(T 'file'): $($item.fileName)" -ForegroundColor Gray
                Write-Host "      $(T 'size'): $sizeStr" -ForegroundColor Gray
                if ($item.completedAt) {
                    Write-Host "      $(T 'time'): $($item.completedAt)" -ForegroundColor Gray
                }
                Write-Host ""
            }
        } else {
            Write-Host "  $(T 'no_tasks_version' $version)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  $(T 'no_status_found')" -ForegroundColor Yellow
    }
    Write-Host "==================================================" -ForegroundColor Cyan
    Do-Exit 0
}

if ($command -ne "download") {
    Write-Host (T 'unknown_command' $command) -ForegroundColor Red
    Write-Host (T 'valid_commands') -ForegroundColor Yellow
    Do-Exit 1
}

try {
    $jsonContent = Get-Content -Path $jsonFilePath -Raw -Encoding UTF8
    $dataArray = $jsonContent | ConvertFrom-Json
    $totalCount = $dataArray.Count
}
catch {
    Write-Error (T 'json_read_failed' $_)
    Do-Exit 1
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "  $(T 'starting_download' $version)" -ForegroundColor Green
Write-Host "  $(T 'total_tasks' $totalCount)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
[Console]::Out.Flush()

$index = -1
foreach ($item in $dataArray) {
    $index++

    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkGray
    Write-Host "  $(T 'task_progress' ($index + 1) $totalCount)" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor DarkGray
    [Console]::Out.Flush()

    $folderName = $item.'Download type'
    $rawUrl = $item.URL

    if (-not $folderName -or -not $rawUrl) {
        Write-Host "  [SKIP] $(T 'skip_invalid')" -ForegroundColor Yellow
        $ignoreCount++
        continue
    }

    $finalUrl = $rawUrl -replace '\{version\}', $version
    $targetFolder = Join-Path $downloadRoot $folderName
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null

    # ========== Get file info via HEAD request ==========
    $fileName = $null
    $expectedSize = -1

    try {
        $response = Invoke-WebRequest -Uri $finalUrl -UseBasicParsing -Method Head -ErrorAction Stop -TimeoutSec 30
        $contentDisposition = $response.Headers.'Content-Disposition'

        if ($contentDisposition) {
            $startIndex = $contentDisposition.IndexOf("filename")
            if ($startIndex -ge 0) {
                $temp = $contentDisposition.Substring($startIndex + 8)
                $temp = $temp.TrimStart("=", "*")
                $q = $temp.IndexOf([char]34)
                $s = $temp.IndexOf(";")
                $end = $temp.Length
                if ($q -gt 0 -and ($s -eq -1 -or $q -lt $s)) { $end = $q }
                elseif ($s -gt 0) { $end = $s }
                $temp = $temp.Substring(0, $end).Trim()
                if ($temp.Length -gt 0) {
                    $fileName = [System.Web.HttpUtility]::UrlDecode($temp)
                }
            }
        }

        $contentLength = $response.Headers.'Content-Length'
        if ($contentLength) {
            $expectedSize = [long]$contentLength
            if ($expectedSize -gt 0 -and $expectedSize -lt 1024) {
                $expectedSize = -1
            }
        }
    }
    catch {
        Write-Host "  [WARN] $(T 'head_failed')" -ForegroundColor Yellow
    }

    if (-not $fileName) {
        $fileName = [System.IO.Path]::GetFileName($finalUrl)
    }

    $savePath = Join-Path $targetFolder $fileName

    # ========== Check if already completed ==========
    $shouldSkip = $false
    if ($resumeEnabled -and (Test-Path $statusFile)) {
        try {
            $content = Get-Content -Path $statusFile -Raw -Encoding UTF8
            $allStatus = $content | ConvertFrom-Json
            $versionStatus = $allStatus.$version
            if ($null -ne $versionStatus) {
                $folderStatus = $versionStatus.($folderName)
                if ($null -ne $folderStatus -and $folderStatus.completed -eq $true) {
                    $savedFileName = $folderStatus.fileName
                    $savedFileSize = $folderStatus.fileSize
                    if ($savedFileSize -is [string]) { $savedFileSize = [long]$savedFileSize }

                    if ($savedFileName -eq $fileName) {
                        if (Test-Path $savePath) {
                            $actualSize = Get-LocalFileSize $savePath
                            if ($savedFileSize -gt 0 -and $actualSize -eq $savedFileSize) {
                                $shouldSkip = $true
                            } elseif ($expectedSize -gt 0 -and $actualSize -eq $expectedSize) {
                                $shouldSkip = $true
                            } elseif ($actualSize -gt 0) {
                                Write-Host "  [WARN] $(T 'size_mismatch' (Format-FileSize $savedFileSize) (Format-FileSize $actualSize))" -ForegroundColor Yellow
                                Write-Host "  [INFO] $(T 'will_redownload')" -ForegroundColor Cyan
                            }
                        } else {
                            Write-Host "  [INFO] $(T 'file_missing' $savePath)" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
        catch { }
    }

    if ($shouldSkip) {
        $fileSizeStr = Format-FileSize (Get-LocalFileSize $savePath)
        $relativePath = $savePath.Substring($downloadRoot.Length + 1)
        Write-Host "  [SKIP] $(T 'skip_completed' $relativePath $fileSizeStr)" -ForegroundColor Yellow
        $skipCount++
        $newSkipCount++
        $successCount++
        [Console]::Out.Flush()
        continue
    }

    # ========== Download with progress ==========
    $downloadSuccess = $false
    $currentRetry = 0
    $lastError = $null

    while (-not $downloadSuccess) {
        if ($currentRetry -gt 0) {
            Write-Host ""
            Write-Host "  [RETRY $currentRetry] $(T 'retry_waiting' $currentRetry $retryDelaySeconds)" -ForegroundColor Yellow
            [Console]::Out.Flush()
            Start-Sleep -Seconds $retryDelaySeconds
        }

        $startTime = Get-Date
        try {
            Write-Host "  $(T 'folder'): $folderName" -ForegroundColor Gray
            Write-Host "  $(T 'url'): $finalUrl" -ForegroundColor Gray
            Write-Host "  $(T 'save_to'): $savePath" -ForegroundColor Gray
            if ($expectedSize -gt 0) {
                Write-Host "  $(T 'expected_size'): $(Format-FileSize $expectedSize)" -ForegroundColor Gray
            }
            Write-Host "  $(T 'downloading')" -ForegroundColor Cyan
            [Console]::Out.Flush()

            curl.exe --connect-timeout 30 --max-time 600 -# -L -o "$savePath" "$finalUrl"
            $exitCode = $LASTEXITCODE

            $endTime = Get-Date
            $duration = $endTime - $startTime

            if ($exitCode -eq 0) {
                $actualSize = Get-LocalFileSize $savePath
                $fileSizeStr = Format-FileSize $actualSize

                if ($expectedSize -gt 0 -and $actualSize -ne $expectedSize) {
                    Write-Host ""
                    Write-Host "  [WARN] $(T 'size_mismatch_dl' (Format-FileSize $expectedSize) $fileSizeStr)" -ForegroundColor Yellow
                    throw "Downloaded file size mismatch"
                }

                $downloadSuccess = $true
                $successCount++
                $newSuccessCount++
                $successItems += [PSCustomObject]@{
                    Folder = $folderName; FileName = $fileName; FullPath = $savePath; Size = $fileSizeStr; Duration = $duration
                }
                Mark-DownloadCompleted -Version $version -FolderName $folderName -FileName $fileName -FileSize $actualSize
                $relativePath = $savePath.Substring($downloadRoot.Length + 1)
                Write-Host ""
                Write-Host "  [SUCCESS] $(T 'downloaded' $relativePath $fileSizeStr $(($duration).TotalSeconds.ToString('F1')))" -ForegroundColor Green
            }
            else {
                throw (T 'curl_failed' $exitCode)
            }
        }
        catch {
            $endTime = Get-Date
            $duration = $endTime - $startTime
            $lastError = $_.Exception.Message
            $currentRetry++

            if ($maxRetries -ne -1 -and $currentRetry -ge $maxRetries) {
                Write-Host ""
                Write-Host "  [FAILED] $(T 'failed_retries' $maxRetries $(($duration).TotalSeconds.ToString('F1')))" -ForegroundColor Red
                Write-Host "  $(T 'error' $lastError)" -ForegroundColor Red
                $failCount++
                $failedItems += [PSCustomObject]@{
                    Type = $folderName; URL = $finalUrl; Error = $lastError; Retries = $currentRetry
                }
                break
            }
            else {
                Write-Host ""
                Write-Host "  [WARNING] $(T 'failed_msg' $(($duration).TotalSeconds.ToString('F1')) $($lastError.Substring(0, [Math]::Min(60, $lastError.Length))))" -ForegroundColor Yellow
                Write-Host "  [INFO] $(T 'will_retry')" -ForegroundColor Cyan
            }
        }
        [Console]::Out.Flush()
    }
    Write-Host ""
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "           $(T 'report_title')" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($newSuccessCount -gt 0) {
    Write-Host ""
    Write-Host "$(T 'newly_downloaded' $newSuccessCount):" -ForegroundColor Green
    Write-Host "--------------------------------------------" -ForegroundColor Green
    $successItems | Format-Table -AutoSize -Property FileName, Size, Duration
}

if ($newSkipCount -gt 0) {
    Write-Host ""
    Write-Host "$(T 'skipped_count' $newSkipCount)" -ForegroundColor Yellow
}

if ($failCount -gt 0) {
    Write-Host ""
    Write-Host "$(T 'failed_tasks' $failCount):" -ForegroundColor Red
    Write-Host "--------------------------------------------" -ForegroundColor Red
    $failedItems | Format-Table -AutoSize -Property Type, URL, Error, Retries
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  $(T 'total'):     $totalCount"
Write-Host "  $(T 'success'):   $successCount" -ForegroundColor Green
Write-Host "  $(T 'failed'):    $failCount" -ForegroundColor Red
Write-Host "  $(T 'skipped'):   $skipCount" -ForegroundColor Yellow
Write-Host "  $(T 'ignored'):   $ignoreCount" -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($failCount -gt 0) {
    Write-Host (T 'tip_rerun') -ForegroundColor Cyan
    Write-Host (T 'tip_reset') -ForegroundColor Cyan
}
elseif ($successCount -gt 0) {
    Write-Host (T 'all_done') -ForegroundColor Green
}
else {
    Write-Host (T 'no_downloads') -ForegroundColor Yellow
}

Write-Host ""
