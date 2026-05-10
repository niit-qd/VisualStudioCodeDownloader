#!/bin/bash
PATH=.:$PATH

# ====================== 【请在这里配置】 ======================
# ====================== 【请在这里配置】 ======================
JSON_FILE="data.json"       # JSON 文件路径
# VERSION="${1: latest}"    # 要替换的版本号
# 默认值： latest
if [ $# -lt 1 ]; then
    VERSION="latest"
else
    VERSION="$1"
fi
DOWNLOAD_ROOT="../$VERSION"  # 下载根目录
# ==============================================================

# ========== 统计变量 ==========
total_count=0   # 总任务数
success_count=0 # 成功数
fail_count=0    # 失败数
ignore_count=0  # 失败数
failed_items=() # 失败任务列表（存储类型+URL）

echo "JSON_FILE     : $JSON_FILE"
echo "VERSION       : $VERSION"
echo "DOWNLOAD_ROOT : $DOWNLOAD_ROOT"

# 检查 jq
if ! command -v jq &> /dev/null; then
    echo "错误：请先安装 jq（JSON解析工具）"
    echo "Ubuntu/Debian: sudo apt install jq"
    echo "CentOS/RHEL: sudo yum install jq"
    echo "macOS: brew install jq"
    echo "windows: 从 \"https://github.com/jqlang/jq\" 下载exe文件，并放到PATH路径中。"
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

# 获取总数
length=$(jq '. | length' "$JSON_FILE")
total_count=$length

index=-1
for ((i=0; i<length; i++)); do
    echo "----------------------------------------------------------------------------------------------------"

    ((index++))
    echo "⬇️ 准备任务: $((index + 1)) / $total_count"

    # 读取字段
    download_type=$(jq -r ".[$i].\"Download type\"" "$JSON_FILE")
    raw_url=$(jq -r ".[$i].URL" "$JSON_FILE")

    if [ "$download_type" = "null" ] || [ "$raw_url" = "null" ]; then
        echo "⚠️ 跳过空项"
        ignore_count=$((ignore_count + 1))
        continue
    fi

    # 替换版本号
    final_url=${raw_url//\{version\}/$VERSION}

    # 目标目录
    target_dir="$DOWNLOAD_ROOT/$download_type"
    mkdir -p "$target_dir"

    echo "📁 目录：$target_dir"
    echo "🔗 原始URL：$raw_url"
    echo "🔗 最终URL：$final_url"
    echo "🔽 获取文件名并下载中..."

    # 获取文件名
    filename=$(curl -s -L -I "$final_url" 2>/dev/null \
        | grep -i content-disposition \
        | head -n 1 \
        | sed -E 's/.*filename=//i' \
        | sed -E 's/[\"; ].*//g' \
        | sed -E 's/^.*\///g' \
        | tr -d '\r\n' \
        | xargs)

    # 修复：basename 用 final_url
    if [ -z "$filename" ]; then
        echo "⚠️ 服务器未返回文件名，从URL提取"
        filename=$(basename "$final_url")
    else
        echo "📄 文件名：$filename ✅ 来源：服务器返回"
    fi

    save_path="${target_dir}/${filename}"

    # 下载
    curl --progress-bar -L -o "$save_path" "$final_url"

    # 判断结果
    if [ $? -eq 0 ]; then
        echo "✅ 下载完成：$save_path"
        success_count=$((success_count + 1))
    else
        echo "❌ 下载失败"
        fail_count=$((fail_count + 1))
        # 记录失败项
        failed_items+=("类型：$download_type | URL：$final_url")
    fi
    echo ""
done

# ====================== 最终汇总输出 ======================
echo
echo "===================================================================================================="
echo "                下载任务汇总"
echo "===================================================================================================="
echo "总任务数  ： $total_count"
echo "成功数    ： $success_count"
echo "失败数    ： $fail_count"
echo "忽略数    ： $ignore_count"
echo "===================================================================================================="

# 打印失败列表
if [ $fail_count -gt 0 ]; then
    echo "❌ 下载失败的任务："
    for item in "${failed_items[@]}"; do
        echo "  - $item"
    done
    echo ""
fi

echo -e "🎉 全部任务处理完毕！\n"