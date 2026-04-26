<#
    脚本功能：
    1. 读取JSON数组（字段：Download type、URL）
    2. 将URL中的 {version} 替换为指定版本号
    3. 以 Download type 作为文件夹名创建目录
    4. 下载替换后的真实URL到对应文件夹
    5. 优先使用服务器返回的文件名保存（Content-Disposition）
    6. 统计：总任务数、成功数、失败数
    7. 失败任务列表输出 + 最终汇总报告
#>

# ====================== 【请在这里配置】 ======================
$jsonFilePath = "data.json"                             # JSON文件路径
$version = if ($args[0]) { $args[0] } else { "latest" } # 你要替换的版本号，默认值： latest
$downloadRoot = "../$version"                           # 下载根目录
Write-Host "jsonFilePath    : $jsonFilePath"
Write-Host "version         : $version"
Write-Host "downloadRoot    : $downloadRoot"
# ==============================================================

# 初始化统计变量
$totalCount = 0     # 总任务数
$successCount = 0   # 成功数
$failCount = 0      # 失败数
$ignoreCount = 0    # 失败数
$failedItems = @()  # 失败任务列表（存储类型+URL）

# 读取并解析JSON
try {
    $jsonContent = Get-Content -Path $jsonFilePath -Raw -Encoding UTF8
    $dataArray = $jsonContent | ConvertFrom-Json
    $totalCount = $dataArray.Count
}
catch {
    Write-Error "JSON读取/解析失败：$_"
    exit 1
}

# 创建总下载目录
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

Write-Host "`n===== 开始批量下载（版本号：$version）=====`n" -ForegroundColor Green
Write-Host "? 总任务数：$totalCount`n" -ForegroundColor Cyan

# 遍历每个下载项
$index = -1 # 当前任务索引
foreach ($item in $dataArray) {
    Write-Host "----------------------------------------------------------------------------------------------------"

    $index++
    Write-Host "?? 准备任务: $($index + 1) / $totalCount"

    # 读取字段
    $folderName = $item.'Download type'
    $rawUrl = $item.URL

    # 空值校验
    if (-not $folderName -or -not $rawUrl) {
        Write-Warning "跳过无效项：文件夹名或URL为空"
        $ignoreCount++
        continue
    }

    # ====================== 核心：替换 {version} ======================
    $finalUrl = $rawUrl -replace '\{version\}', $version
    # =================================================================

    # 拼接文件夹路径
    $targetFolder = Join-Path $downloadRoot $folderName
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null

    $downloadSuccess = $false
    try {
        Write-Host "? 目录：$folderName"
        Write-Host "? 原始URL：$rawUrl"
        Write-Host "? 替换后：$finalUrl"
        Write-Host "?? 下载中..."

        # ====================== 获取服务器返回的真实文件名 ======================
        $fileName = $null
        try {
            $response = Invoke-WebRequest -Uri $finalUrl -UseBasicParsing -Method Head -ErrorAction Stop
            $contentDisposition = $response.Headers.'Content-Disposition'
            
            if ($contentDisposition -match 'filename\*?=.*?([^\";]+)') {
                $fileName = [System.Web.HttpUtility]::UrlDecode($matches[1].Trim())
                Write-Host "? 文件名：$fileName ? 来源：服务器返回的文件名（Content-Disposition）"
            } 
        }
        catch {
            # HEAD请求失败则使用URL文件名
        }

        # 兜底：没有获取到服务端文件名则使用URL中的文件名
        if (-not $fileName) {
            $fileName = [System.IO.Path]::GetFileName($finalUrl)
            Write-Host "? 文件名：$fileName ?? 来源：从URL中自动提取"
        }
        # ========================================================================

        $savePath = Join-Path $targetFolder $fileName

        # 下载文件（使用原生curl.exe，速度更快）
        curl.exe --progress-bar -L -o "$savePath" "$finalUrl"
        
        # 判断curl退出码（0=成功）
        if ($LASTEXITCODE -eq 0) {
            $successCount++
            $downloadSuccess = $true
            Write-Host "? 下载完成：$savePath" -ForegroundColor Green
        } else {
            throw "curl.exe 下载失败，退出码：$LASTEXITCODE"
        }
    }
    catch {
        $failCount++
        $downloadSuccess = $false
        $errorMsg = $_.Exception.Message
        Write-Error "? 下载失败：$errorMsg"
        
        # 记录失败项
        $failedItems += [PSCustomObject]@{
            Type = $folderName
            URL  = $finalUrl
            Error = $errorMsg
        }
    }
    Write-Host
}

# ====================== 最终输出汇总报告 ======================
Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "                下载任务汇总" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "总任务数： $totalCount"
Write-Host "成功数  ： $successCount" -ForegroundColor Green
Write-Host "失败数  ： $failCount" -ForegroundColor Red
Write-Host "忽略数  ： $ignoreCount" -ForegroundColor Red
Write-Host "=============================================`n"

# 打印失败列表
if ($failCount -gt 0) {
    Write-Host "? 下载失败的任务列表：" -ForegroundColor Red
    $failedItems | Format-Table -AutoSize -Property Type, URL, Error
    Write-Host
}

Write-Host "? 全部任务处理完毕！" -ForegroundColor Green