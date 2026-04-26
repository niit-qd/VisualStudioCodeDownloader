<#
    脚本功能：
    1. 读取JSON数组（字段：Download type、URL）
    2. 将URL中的 {version} 替换为指定版本号
    3. 以 Download type 作为文件夹名创建目录
    4. 下载替换后的真实URL到对应文件夹
    5. 优先使用服务器返回的文件名保存（Content-Disposition）
#>

# ====================== 【请在这里配置】 ======================
$jsonFilePath = "data.json"                             # JSON文件路径
$version = if ($args[0]) { $args[0] } else { "latest" } # 你要替换的版本号（可随意修改）
$downloadRoot = "../$version"                           # 下载根目录
Write-Host "jsonFilePath    : $jsonFilePath"
Write-Host "version         : $version"
Write-Host "downloadRoot    : $downloadRoot"
# ==============================================================

# 读取并解析JSON
try {
    $jsonContent = Get-Content -Path $jsonFilePath -Raw -Encoding UTF8
    $dataArray = $jsonContent | ConvertFrom-Json
}
catch {
    Write-Error "JSON读取/解析失败：$_"
    exit 1
}

# 创建总下载目录
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

Write-Host "`n===== 开始批量下载（版本号：$version）=====`n" -ForegroundColor Green

# 遍历每个下载项
foreach ($item in $dataArray) {
    Write-Host "----------------------------------------------------------------------------------------------------"

    # 读取字段
    $folderName = $item.'Download type'
    $rawUrl = $item.URL

    # 空值校验
    if (-not $folderName -or -not $rawUrl) {
        Write-Warning "跳过无效项：文件夹名或URL为空"
        continue
    }

    # ====================== 核心：替换 {version} ======================
    $finalUrl = $rawUrl -replace '\{version\}', $version
    # =================================================================

    # 拼接文件夹路径
    $targetFolder = Join-Path $downloadRoot $folderName
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null

    try {
        Write-Host "? 目录：$folderName"
        Write-Host "? 原始URL：$rawUrl"
        Write-Host "? 替换后：$finalUrl"
        Write-Host "?? 下载中..."

        # ====================== 修复：获取服务器返回的真实文件名 ======================
        $fileName = $null
        try {
            # 发送HEAD请求获取响应头
            $response = Invoke-WebRequest -Uri $finalUrl -UseBasicParsing -Method Head -ErrorAction Stop
            $contentDisposition = $response.Headers.'Content-Disposition'
            
            # 修复后的正则表达式
            if ($contentDisposition -match 'filename\*?=.*?([^\";]+)') {
                $fileName = [System.Web.HttpUtility]::UrlDecode($matches[1].Trim())
                Write-Host "? 文件名：$fileName ? 来源：服务器返回的文件名（Content-Disposition）"
            } 
        }
        catch {
            # HEAD请求失败时忽略，使用URL文件名
        }

        # 兜底：没有获取到服务端文件名则使用URL中的文件名
        if (-not $fileName) {
            $fileName = [System.IO.Path]::GetFileName($finalUrl)
                Write-Host "? 文件名：$fileName ?? 来源：从URL中自动提取"
        }
        # ================================================================================

        $savePath = Join-Path $targetFolder $fileName

        # 下载文件
        # Invoke-WebRequest -Uri $finalUrl -OutFile $savePath -UseBasicParsing
        # PowerShell 里的 curl 是别名，指向 Invoke-WebRequest（慢！）
        curl.exe --progress-bar -L -o "$savePath" "$finalUrl"

        Write-Host "? 下载完成：$savePath" -ForegroundColor Green
    }
    catch {
        Write-Error "? 下载失败：$_"
    }
    Write-Host
}

Write-Host "`n===== 全部任务处理完毕 =====`n" -ForegroundColor Green