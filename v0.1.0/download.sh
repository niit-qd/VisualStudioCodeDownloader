#!/bin/bash

# Script version (used to replace {0} in title)
SCRIPT_VERSION="0.1.0"

# Get the directory where this script resides (cross-platform)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATH="$SCRIPT_DIR:$PATH"

# ====================== Config ======================
JSON_FILE="$SCRIPT_DIR/data.json"
I18N_DIR="$SCRIPT_DIR/i18n"
VERSION="latest"
MAX_RETRIES=-1
RETRY_DELAY=3
RESUME_ENABLED=true
SILENT_MODE=false
COMMAND="download"
LANG_OVERRIDE=""
# ======================================================

# ========== Stats ==========
total_count=0
success_count=0
fail_count=0
ignore_count=0
skip_count=0
failed_items=()

# ========== i18n ==========
I18N_DATA=""

load_i18n() {
    local lang="$1"
    local lang_file="$I18N_DIR/$lang.json"
    if [ ! -f "$lang_file" ]; then return; fi
    I18N_DATA=$(cat "$lang_file" 2>/dev/null)
    if [ -z "$I18N_DATA" ]; then
        I18N_DATA=""
    fi
}

detect_lang() {
    # Check shell locale variables
    local lc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    case "$lc" in
        zh_*|zh-CN*|zh_TW*|zh_HK*|zh_CN) echo "zh"; return ;;
    esac

    # Git Bash on Windows: check Windows system locale via systeminfo or reg
    if [[ "$(uname -s)" == *MINGW* ]] || [[ "$(uname -s)" == *MSYS* ]]; then
        # Try reading Windows locale from registry via reg query
        local win_locale=$(reg query "HKCU\Control Panel\International" /v LocaleName 2>/dev/null | grep -i "zh" 2>/dev/null)
        if [ -n "$win_locale" ]; then echo "zh"; return; fi
    fi

    # Fallback: check LANGUAGE variable (some Linux distros)
    case "${LANGUAGE:-}" in
        zh*|zh_CN*|zh_TW*) echo "zh"; return ;;
    esac

    echo "en"
}

t() {
    local key="$1"
    shift
    if [ -n "$I18N_DATA" ]; then
        local val=$(echo "$I18N_DATA" | jq -r ".\"$key\"" 2>/dev/null)
        if [ "$val" != "null" ] && [ -n "$val" ]; then
            # Replace {0}, {1}, etc with arguments
            local i=0
            for arg in "$@"; do
                val=$(echo "$val" | sed "s/{$i}/$arg/g")
                i=$((i + 1))
            done
            echo "$val"
            return
        fi
    fi
    echo "$key"
}

# ========== Exit function ==========
do_exit() {
    local code=$1
    if [ "$SILENT_MODE" != true ]; then
        echo ""
        read -p "$(t 'press_enter')"
    fi
    exit $code
}

# ========== Utility functions ==========
format_size() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" -lt 0 ] 2>/dev/null; then echo "Unknown"; return; fi
    if [ $bytes -lt 1024 ]; then echo "${bytes} B"; return; fi
    if [ $bytes -lt 1048576 ]; then echo "$(awk "BEGIN{printf \"%.2f\", $bytes/1024}") KB"; return; fi
    if [ $bytes -lt 1073741824 ]; then echo "$(awk "BEGIN{printf \"%.2f\", $bytes/1048576}") MB"; return; fi
    echo "$(awk "BEGIN{printf \"%.2f\", $bytes/1073741824}") GB"
}

# ========== Status file functions ==========
load_status() {
    if [ "$RESUME_ENABLED" = true ] && [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE" 2>/dev/null
    fi
}

save_status() {
    if [ "$RESUME_ENABLED" = true ]; then
        local dir=$(dirname "$STATUS_FILE")
        mkdir -p "$dir" 2>/dev/null
        echo "$1" > "$STATUS_FILE"
    fi
}

is_completed() {
    local ver="$1"
    local folder="$2"
    local filename="$3"
    local filesize="$4"

    if [ "$RESUME_ENABLED" != true ]; then return 1; fi

    local status=$(load_status)
    if [ -z "$status" ]; then return 1; fi

    local completed=$(echo "$status" | jq -r ".\"$ver\".\"$folder\".completed" 2>/dev/null)
    local saved_filename=$(echo "$status" | jq -r ".\"$ver\".\"$folder\".fileName" 2>/dev/null)
    local saved_filesize=$(echo "$status" | jq -r ".\"$ver\".\"$folder\".fileSize" 2>/dev/null)

    if [ "$completed" = "true" ] && [ "$saved_filename" = "$filename" ]; then
        local file_path="$DOWNLOAD_ROOT/$folder/$filename"
        if [ ! -f "$file_path" ]; then return 1; fi

        if [ -n "$saved_filesize" ] && [ "$saved_filesize" != "null" ] && [ "$saved_filesize" -gt 0 ] 2>/dev/null; then
            local actual_size=$(stat -c %s "$file_path" 2>/dev/null || stat -f %z "$file_path" 2>/dev/null)
            if [ -n "$actual_size" ] && [ "$actual_size" = "$saved_filesize" ]; then return 0; else return 1; fi
        fi

        if [ -n "$filesize" ] && [ "$filesize" -gt 0 ] 2>/dev/null; then
            local actual_size=$(stat -c %s "$file_path" 2>/dev/null || stat -f %z "$file_path" 2>/dev/null)
            if [ -n "$actual_size" ] && [ "$actual_size" = "$filesize" ]; then return 0; else return 1; fi
        fi

        return 0
    else
        return 1
    fi
}

mark_completed() {
    local ver="$1"
    local folder="$2"
    local filename="$3"
    local filesize="$4"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local status=$(load_status)
    if [ -z "$status" ]; then status="{}"; fi

    local new_entry="{\"completed\": true, \"fileName\": \"$filename\", \"fileSize\": $filesize, \"completedAt\": \"$timestamp\"}"
    local new_status=$(echo "$status" | jq --arg v "$ver" --arg f "$folder" --argjson e "$new_entry" \
        'if has($v) then .[$v][$f] = $e else .[$v] = {($f): $e} end')

    save_status "$new_status"
}

reset_status() {
    local ver="$1"
    local status=$(load_status)

    if [ -n "$status" ]; then
        local new_status=$(echo "$status" | jq "del(.\"$ver\")")
        save_status "$new_status"
        echo "$(t 'reset_done' "$ver")"
    fi
}

show_status() {
    local status=$(load_status)
    echo ""
    echo "=================================================="
    echo "           $(t 'download_status_title')"
    echo "=================================================="
    if [ -n "$status" ]; then
        local version_status=$(echo "$status" | jq -r ".\"$VERSION\"" 2>/dev/null)
        if [ "$version_status" != "null" ] && [ -n "$version_status" ]; then
            local total=$(echo "$version_status" | jq 'keys | length')
            local completed=$(echo "$version_status" | jq '[.[] | select(.completed == true)] | length')
            echo ""
            echo "  ✅ $(t 'completed_count' "$completed" "$total")"
            echo ""
            for key in $(echo "$version_status" | jq -r 'keys[]'); do
                local item=$(echo "$version_status" | jq -r ".\"$key\"")
                local is_completed=$(echo "$item" | jq -r '.completed')
                local filename=$(echo "$item" | jq -r '.fileName')
                local filesize=$(echo "$item" | jq -r '.fileSize')
                local completed_at=$(echo "$item" | jq -r '.completedAt')

                if [ "$is_completed" = "true" ]; then
                    echo "  ✅ $key"
                else
                    echo "  ⏳ $key"
                fi
                echo "      $(t 'file'): $filename"
                if [ "$filesize" != "null" ] && [ -n "$filesize" ]; then
                    echo "      $(t 'size'): $(format_size $filesize)"
                fi
                if [ "$completed_at" != "null" ] && [ -n "$completed_at" ]; then
                    echo "      $(t 'time'): $completed_at"
                fi
                echo ""
            done
        else
            echo "  $(t 'no_tasks_version' "$VERSION")"
        fi
    else
        echo "  $(t 'no_status_found')"
    fi
    echo "=================================================="
}

# ========== Parse arguments ==========
for arg in "$@"; do
    case "$arg" in
        --command|--command=)
            ;;
        --command=*)
            val="${arg#*=}"
            val_trimmed=$(echo "$val" | xargs)
            if [ -n "$val_trimmed" ]; then COMMAND="$val_trimmed"; fi
            ;;
        --version|--version=)
            ;;
        --version=*)
            val="${arg#*=}"
            val_trimmed=$(echo "$val" | xargs)
            if [ -n "$val_trimmed" ]; then VERSION="$val_trimmed"; fi
            ;;
        --lang|--lang=)
            ;;
        --lang=*)
            val="${arg#*=}"
            val_trimmed=$(echo "$val" | xargs)
            if [ -n "$val_trimmed" ]; then LANG_OVERRIDE="$val_trimmed"; fi
            ;;
        --silent)
            SILENT_MODE=true
            ;;
    esac
done

# Update paths after version is parsed
DOWNLOAD_ROOT="$SCRIPT_DIR/../$VERSION"
STATUS_FILE="$DOWNLOAD_ROOT/download_status.json"

# ========== Load i18n ==========
if [ -n "$LANG_OVERRIDE" ]; then
    load_i18n "$LANG_OVERRIDE"
    if [ -z "$I18N_DATA" ]; then
        # Requested lang not found, fallback to system
        LANG_OVERRIDE=$(detect_lang)
        load_i18n "$LANG_OVERRIDE"
    fi
else
    LANG_OVERRIDE=$(detect_lang)
    load_i18n "$LANG_OVERRIDE"
fi

# ========== Show config ==========
echo "=================================================="
echo "          $(t 'title' "$SCRIPT_VERSION")"
echo "=================================================="
echo
echo "📄 $(t 'config_file'):    $JSON_FILE"
echo "🏷️ $(t 'version_label'):        $VERSION"
echo "📁 $(t 'download_to'):    $DOWNLOAD_ROOT"
echo "📋 $(t 'status_file'):    $STATUS_FILE"
echo "🔄 $(t 'max_retries'):    $([ "$MAX_RETRIES" -eq -1 ] && echo "$(t 'infinite')" || echo "$MAX_RETRIES")"
echo "⏱️ $(t 'retry_delay'):    ${RETRY_DELAY}s"
echo "🔁 $(t 'resume'):    $([ "$RESUME_ENABLED" = true ] && echo "$(t 'enabled')" || echo "$(t 'disabled')")"
echo "✅ $(t 'verify'):    $(t 'file_size_check')"
echo

# ========== Dependency check ==========
if ! command -v jq &> /dev/null && [ ! -f "$SCRIPT_DIR/jq" ]; then
    echo "$(t 'jq_missing')"
    echo "$(t 'jq_install')"
    echo "$(t 'jq_install2')"
    echo "$(t 'jq_install3')"
    echo "$(t 'jq_install4')"
    do_exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "$(t 'curl_missing')"
    do_exit 1
fi

# ========== File check ==========
if [ ! -f "$JSON_FILE" ]; then
    echo "$(t 'json_not_found')"
    do_exit 1
fi

mkdir -p "$DOWNLOAD_ROOT"

# ========== Mutex ==========
LOCK_DIR="$DOWNLOAD_ROOT/.download.lock"

# Check for stale lock before attempting mkdir
if [ -d "$LOCK_DIR" ]; then
    old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$old_pid" ]; then
        pid_alive=false
        # Linux/macOS: use kill -0
        if kill -0 "$old_pid" 2>/dev/null; then
            pid_alive=true
        fi
        # Git Bash on Windows: use tasklist as fallback
        if [ "$pid_alive" = false ]; then
            if command -v tasklist &> /dev/null; then
                if tasklist //FI "PID eq $old_pid" 2>/dev/null | grep -q "$old_pid"; then
                    pid_alive=true
                fi
            fi
        fi
        if [ "$pid_alive" = false ]; then
            echo "[INFO] $(t 'stale_lock_cleaned' "$old_pid")"
            rm -rf "$LOCK_DIR"
        fi
    else
        # No PID file, lock is stale
        rm -rf "$LOCK_DIR"
    fi
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$(t 'another_instance')"
    echo "$(t 'another_instance_tip' "$LOCK_DIR")"
    do_exit 1
fi
echo "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

# ========== Handle commands ==========
if [ "$COMMAND" = "reset" ]; then
    reset_status "$VERSION"
    do_exit 0
fi

if [ "$COMMAND" = "status" ]; then
    show_status
    do_exit 0
fi

if [ "$COMMAND" != "download" ]; then
    echo "$(t 'unknown_command' "$COMMAND")"
    echo "$(t 'valid_commands')"
    do_exit 1
fi

# ========== Start download ==========
length=$(jq '. | length' "$JSON_FILE")
total_count=$length

echo "=================================================="
echo "$(t 'starting_download' "$VERSION")"
echo "$(t 'total_tasks' "$total_count")"
echo "=================================================="
echo

# ========== Download loop ==========
index=-1
for ((i=0; i<length; i++)); do
    echo "============================================"

    ((index++))
    echo "▶ $(t 'task_progress' "$((index + 1))" "$total_count")"

    download_type=$(jq -r ".[$i].\"Download type\"" "$JSON_FILE")
    raw_url=$(jq -r ".[$i].URL" "$JSON_FILE")

    if [ "$download_type" = "null" ] || [ "$raw_url" = "null" ] || [ -z "$download_type" ] || [ -z "$raw_url" ]; then
        echo "⚠ $(t 'skip_invalid')"
        ignore_count=$((ignore_count + 1))
        continue
    fi

    final_url=${raw_url//\{version\}/$VERSION}

    target_dir="$DOWNLOAD_ROOT/$download_type"
    mkdir -p "$target_dir"

    # ========== Get file info via HEAD ==========
    echo "🔗 $(t 'fetching_info')"
    head_info=$(curl -s -L -I --connect-timeout 30 --max-time 60 "$final_url" 2>/dev/null)

    filename=$(echo "$head_info" | grep -i content-disposition | head -n 1 \
        | sed -E 's/.*filename=//i' \
        | sed -E 's/[\"; ].*//g' \
        | sed -E 's/^.*\///g' \
        | tr -d '\r\n' \
        | xargs)

    if [ -z "$filename" ]; then
        filename=$(basename "$final_url")
    fi

    expected_size=$(echo "$head_info" | grep -i "^content-length:" | tail -n 1 \
        | sed -E 's/[^0-9]//g' \
        | tr -d '\r\n')

    if [ -n "$expected_size" ] && [ "$expected_size" -lt 1024 ] 2>/dev/null; then
        expected_size=-1
    fi

    if [ -z "$expected_size" ]; then
        expected_size=-1
    fi

    save_path="${target_dir}/${filename}"

    # ========== Check if already completed ==========
    if is_completed "$VERSION" "$download_type" "$filename" "$expected_size"; then
        if [ -f "$save_path" ]; then
            actual_size=$(stat -c %s "$save_path" 2>/dev/null || stat -f %z "$save_path" 2>/dev/null)
            size_str=$(format_size $actual_size)
            echo "⏭ $(t 'skip_completed' "${save_path#$DOWNLOAD_ROOT/}" "$size_str")"
            skip_count=$((skip_count + 1))
            success_count=$((success_count + 1))
            continue
        fi
    fi

    # Check if file exists but incomplete
    if [ -f "$save_path" ]; then
        actual_size=$(stat -c %s "$save_path" 2>/dev/null || stat -f %z "$save_path" 2>/dev/null)
        if [ "$expected_size" -gt 0 ] && [ "$actual_size" != "$expected_size" ] 2>/dev/null; then
            echo "⚠ $(t 'size_mismatch' "$(format_size $expected_size)" "$(format_size $actual_size)")"
            echo "ℹ $(t 'will_redownload')"
        fi
    fi

    # ========== Download with retry ==========
    download_success=false
    current_retry=0
    last_error=""

    while [ "$download_success" = false ]; do
        if [ $current_retry -gt 0 ]; then
            echo "⏳ $(t 'retry_waiting' "$current_retry" "$RETRY_DELAY")"
            sleep "$RETRY_DELAY"
        fi

        echo "📁 $(t 'folder'): $download_type"
        echo "🔗 $(t 'url'): $final_url"
        echo "💾 $(t 'save_to'): $save_path"
        if [ "$expected_size" -gt 0 ]; then
            echo "📊 $(t 'expected_size'): $(format_size $expected_size)"
        fi
        echo "📥 $(t 'downloading')"

        curl --progress-bar -L --connect-timeout 30 --max-time 600 -o "$save_path" "$final_url"
        curl_exit=$?

        if [ $curl_exit -eq 0 ]; then
            actual_size=$(stat -c %s "$save_path" 2>/dev/null || stat -f %z "$save_path" 2>/dev/null)

            if [ "$expected_size" -gt 0 ] && [ "$actual_size" != "$expected_size" ] 2>/dev/null; then
                echo ""
                echo "⚠ $(t 'size_mismatch_dl' "$(format_size $expected_size)" "$(format_size $actual_size)")"
                last_error="$(t 'size_mismatch_dl' "$(format_size $expected_size)" "$(format_size $actual_size)")"
                current_retry=$((current_retry + 1))

                if [ "$MAX_RETRIES" -ne -1 ] && [ $current_retry -ge "$MAX_RETRIES" ]; then
                    echo "❌ $(t 'max_retries_reached')"
                    fail_count=$((fail_count + 1))
                    failed_items+=("$(t 'folder')：$download_type | $(t 'url')：$final_url | $(t 'error')：$last_error | $(t 'retry_delay')：$current_retry")
                    break
                else
                    echo "$(t 'will_retry_n' "$((current_retry + 1))")"
                    continue
                fi
            fi

            download_success=true
            success_count=$((success_count + 1))
            mark_completed "$VERSION" "$download_type" "$filename" "$actual_size"
            size_str=$(format_size $actual_size)
            echo ""
            echo "✅ $(t 'downloaded' "${save_path#$DOWNLOAD_ROOT/}" "$size_str")"
        else
            last_error="$(t 'curl_failed' "$curl_exit")"
            current_retry=$((current_retry + 1))

            if [ "$MAX_RETRIES" -ne -1 ] && [ $current_retry -ge "$MAX_RETRIES" ]; then
                echo "❌ $(t 'max_retries_reached') ($MAX_RETRIES): $last_error"
                fail_count=$((fail_count + 1))
                failed_items+=("$(t 'folder')：$download_type | $(t 'url')：$final_url | $(t 'error')：$last_error | $(t 'retry_delay')：$current_retry")
                break
            else
                echo "⚠ $(t 'download_failed' "$last_error")"
                echo "$(t 'will_retry_n' "$((current_retry + 1))")"
            fi
        fi
    done
    echo
done

# ========== Final report ==========
echo
echo "============================================="
echo "                $(t 'report_title')"
echo "============================================="
echo "$(t 'total'):  $total_count"
echo "$(t 'success'):    $success_count"
echo "$(t 'failed'):    $fail_count"
echo "$(t 'skipped'):    $skip_count"
echo "$(t 'ignored'):    $ignore_count"
echo "============================================="
echo

if [ $fail_count -gt 0 ]; then
    echo "▶ $(t 'failed_list')"
    for item in "${failed_items[@]}"; do
        echo "  - $item"
    done
    echo
    echo "💡 $(t 'tip_rerun')"
    echo "💡 $(t 'tip_reset')"
    echo
fi

if [ $fail_count -eq 0 ] && [ $success_count -gt 0 ]; then
    echo "🎉 $(t 'all_done')"
elif [ $fail_count -gt 0 ]; then
    echo "⚠ $(t 'partial_failed')"
fi
