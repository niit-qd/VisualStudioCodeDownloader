<#
    脚本功能：
    1. 读取JSON数组（字段：Download type、URL）
    2. 将URL中的 {version} 替换为指定版本号
    3. 以 Download type 作为文件夹名创建目录
    4. 下载替换后的真实URL到对应文件夹
#>

# ====================== 【请在这里配置】 ======================
$jsonFilePath = "data.json"                             # JSON文件路径
$version = if ($args[0]) { $args[0] } else { "latest" } # 你要替换的版本号（可随意修改）
$downloadRoot = "../$version"                 # 下载根目录
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
        # 获取文件名
        $fileName = [System.IO.Path]::GetFileName($finalUrl)
        $savePath = Join-Path $targetFolder $fileName

        Write-Host "`n? 目录：$folderName"
        Write-Host "? 原始URL：$rawUrl"
        Write-Host "? 替换后：$finalUrl"
        Write-Host "? 下载中..."

        # 开始下载
        Invoke-WebRequest -Uri $finalUrl -OutFile $savePath -UseBasicParsing

        Write-Host "? 下载完成：$savePath" -ForegroundColor Green
    }
    catch {
        Write-Error "? 下载失败：$_"
    }
}

Write-Host "`n===== 全部任务处理完毕 =====`n" -ForegroundColor Green