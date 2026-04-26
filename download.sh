#!/bin/bash

PATH=.:$PATH

# ====================== 【请在这里配置】 ======================
JSON_FILE="data.json"          # JSON 文件路径
# VERSION="${1: latest}"       # 要替换的版本号
if [ $# -lt 1 ]; then
    VERSION="latest"
else
    VERSION="$1"
fi
DOWNLOAD_ROOT="../$VERSION"    # 下载根目录
echo "JSON_FILE     : $JSON_FILE"
echo "VERSION       : $VERSION"
echo "DOWNLOAD_ROOT : $DOWNLOAD_ROOT"
# ==============================================================

# 检查 jq
if ! command -v jq &> /dev/null; then
    echo "错误：请先安装 jq（JSON解析工具）"
    echo "Ubuntu/Debian: sudo apt install jq"
    echo "CentOS/RHEL: sudo yum install jq"
    echo "macOS: brew install jq"
    echo "windows: 从https://github.com/jqlang/jq下载exe文件放到PATH路径中"
    read -p "按回车键退出..."
    exit 1
fi

# 检查文件
if [ ! -f "$JSON_FILE" ]; then
    echo "JSON 文件不存在"
    exit 1
fi

mkdir -p "$DOWNLOAD_ROOT"

echo -e "\n===== 开始下载（版本：$VERSION）=====\n"

length=$(jq '. | length' "$JSON_FILE")
for ((i=0; i<length; i++)); do
    echo "----------------------------------------------------------------------------------------------------"

    # 读取字段
    download_type=$(jq -r ".[$i].\"Download type\"" "$JSON_FILE")
    raw_url=$(jq -r ".[$i].URL" "$JSON_FILE")

    if [ "$download_type" = "null" ] || [ "$raw_url" = "null" ]; then
        echo "⚠️ 跳过空项"
        continue
    fi

    # 替换版本号
    final_url=${raw_url//\{version\}/$VERSION}

    # 目标目录
    target_dir="$DOWNLOAD_ROOT/$download_type"
    mkdir -p "$target_dir"

    echo -e "📁 目录：$target_dir"
    echo "🔗 原始URL：$raw_url"
    echo "🔗 最终URL：$final_url"
    echo "🔽 获取文件名并下载中..."

    # ====================== 核心：获取服务器返回的文件名 ======================
    # curl 官方正确方式：直接读取响应头的文件名，不依赖URL
    # ==============================================
    # 【终极正确】从响应头提取纯净文件名，剔除所有杂质
    # ==============================================
    filename=$(curl -s -L -I "$final_url" 2>/dev/null \
        | grep -i content-disposition \
        | head -n 1 \
        | sed -E 's/.*filename=//i' \
        | sed -E 's/[\"; ].*//g' \
        | sed -E 's/^.*\///g' \
        | tr -d '\r\n' \
        | xargs)

    # 如果服务器没有返回文件名，才报错退出（不使用URL文件名）
    if [ -z "$filename" ]; then
        echo "❌ 服务器未返回文件名"
        filename=$(basename "$url")
        echo "📄 文件名：${filename} ⚠️ 来源：从URL中自动提取"
    else
        echo "📄 文件名：${filename} ✅ 来源：服务器返回的文件名"
    fi

    # 最终保存路径（绝对正确）
    save_path="${target_dir}/${filename}"

    # 下载
    # curl -s -L -o "$save_path" "$final_url"
    curl --progress-bar -L -o "$save_path" "$final_url"

    if [ $? -eq 0 ]; then
        echo "✅ 下载完成：$save_path"
    else
        echo "❌ 下载失败"
    fi
    echo ""
done

echo -e "\n===== 全部任务完成 =====\n"