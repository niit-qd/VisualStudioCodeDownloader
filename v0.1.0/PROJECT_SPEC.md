# VisualStudioCodeDownloader - 项目重建说明

> 本文档供 TRAE (SOLO) 或开发者根据描述从零重建项目。
> `data.json` 为下载来源配置文件，需开发者手动提供，不需要 AI 生成。

---

## 项目概述

Visual Studio Code 全平台离线下载器。通过读取 `data.json` 配置文件中的下载任务列表，自动下载 VSCode 各平台安装包到版本目录中。

---

## 项目结构

```
VisualStudioCodeDownloader/
├── data.json              # [不生成] 下载任务配置，由开发者提供
├── download.ps1           # PowerShell 脚本（Windows）
├── download.bat           # BAT 包装脚本（调用 PS1，双击可用）
├── download.sh            # Shell 脚本（Linux / macOS / Windows Git Bash）
├── i18n/                  # 国际化语言包目录
│   ├── en.json            # 英文语言包
│   └── zh.json            # 中文语言包
├── jq                     # [不生成] jq 可执行文件，跨平台 JSON 解析工具
├── README.md              # 使用文档
└── PROJECT_SPEC.md        # 本文档
```

运行后生成的版本目录（workspace）：

```
{版本号}/                              # 如 latest/ 或 1.119.0/
├── .download.lock/                  # 互斥锁目录
│   └── pid                          # 锁持有者进程 PID
├── download_status.json             # 下载状态记录
├── {Download type}/                 # 每个任务一个子文件夹
│   └── {实际文件名}
└── ...
```

---

## 核心功能需求

### 1. 下载任务读取

- 从 `data.json`（与脚本同目录）读取 JSON 数组
- 每项包含 `Download type`（子文件夹名）和 `URL`（下载链接模板）
- URL 中的 `{version}` 占位符替换为实际版本号
- 版本号通过第一个位置参数传入，默认 `latest`

### 2. 文件名获取

- 通过 HTTP HEAD 请求获取 `Content-Disposition` 头中的文件名
- 解析 `filename=` 后的值，支持 URL 编码
- HEAD 失败时回退到 URL 末尾的文件名
- HEAD 请求超时 30 秒

### 3. 文件大小校验

- 从 HEAD 响应获取 `Content-Length` 作为预期大小
- **重定向处理**：取最后一个 `Content-Length`（`tail -n 1`），因为 302 重定向会产生多个响应
- **合理性校验**：如果预期大小 < 1KB，视为不可靠数据，设为 -1 不参与校验
- 下载完成后对比实际文件大小与预期大小，不匹配则重试

### 4. 断点续传

- 状态文件 `download_status.json` 存放在**版本目录**中（非脚本目录）
- 每个任务记录：`completed`、`fileName`、`fileSize`、`completedAt`
- 跳过逻辑：状态记录完成 + 文件存在 + 文件大小匹配 → 跳过
- 文件缺失或大小不匹配 → 重新下载
- `data.json` 变更（增删任务）不影响已有记录，脚本只遍历 `data.json` 中的任务

### 5. 下载执行

- 使用 `curl` 下载，显示实时进度条
  - PS1：`curl.exe -# -L`（`-#` 进度条，`-L` 跟随重定向）
  - SH：`curl --progress-bar -L`
- **不要捕获 curl 的 stderr 输出**，否则进度条不显示
- 连接超时 30 秒，总超时 600 秒
- 失败后无限重试，间隔 3 秒

### 6. 并发互斥

- 使用 `mkdir` 原子操作创建锁目录（`.download.lock/`），跨平台通用
- 锁目录位于版本目录内，不同版本互不干扰
- PS1 和 SH 共用同一锁目录，互相排斥
- 正常退出时自动清理锁目录（PS1 用 `Register-EngineEvent`，SH 用 `trap`）
- 异常退出后残留锁目录，提示用户手动删除
- **不做 PID 存活检测**（Git Bash 的 `kill -0` 不可靠检测 Windows 进程）

### 7. 退出暂停

- 默认所有退出点（包括正常结束）都暂停等待用户确认
- PS1：`Press Enter to exit...`
- SH：`按回车键退出...`
- `--silent` 参数启用静默模式，直接退出不暂停

### 8. 命令行参数

| 参数 | 行为 |
|------|------|
| `--version=<版本号>` | 可选，默认 `latest`，指定要下载的 VSCode 版本号 |
| `--silent` | 可选，静默模式，退出时不暂停等待用户确认 |
| `--lang=<语言>` | 可选，强制指定语言（`en`/`zh`），默认自动检测系统语言。指定语言不存在时回退到系统语言 |
| `--command=download` | 执行下载任务（默认命令） |
| `--command=status` | 读取并打印 `download_status.json`，然后退出 |
| `--command=reset` | 清除当前版本的状态记录，然后退出 |

**参数解析逻辑**：
- 遍历所有参数，`--command=*` 提取命令值，`--version=*` 提取版本号，`--lang=*` 提取语言，`--silent` 设置静默模式
- `--command`、`--version`、`--lang` 后面没有等号或值为空时使用默认值
- 默认命令为 `download`，默认版本为 `latest`
- 未知命令报错并列出有效命令

### 9. 国际化（i18n）

- 语言包目录 `i18n/` 与脚本同目录，每个语言一个独立 JSON 文件（如 `en.json`、`zh.json`）
- 脚本只读取当前语言对应的文件，不加载其他语言，减少内存占用
- **语言检测优先级**：`--lang` 参数 > 系统语言 > 默认 `en`
- PS1 检测方式：`[System.Threading.Thread]::CurrentThread.CurrentCulture.Name`，匹配 `^zh` 则中文
- SH 检测方式：读取 `$LC_ALL` / `$LC_MESSAGES` / `$LANG`，匹配 `zh_*` 则中文
- 所有用户可见文案通过 `t()` / `T()` 函数获取，支持 `{0}` `{1}` 占位符替换
- 新增语言只需在 `i18n/` 目录下添加新的 `{lang}.json` 文件

---

## 脚本实现要点

### download.ps1（PowerShell）

- 使用 `Invoke-WebRequest -Method Head -TimeoutSec 30` 获取文件信息
- 使用 `curl.exe`（非 PowerShell 的 `Invoke-WebRequest`）下载，以获得进度条
- 使用 `ConvertFrom-Json` / `ConvertTo-Json` 处理状态文件
- 使用 `Register-EngineEvent -SourceIdentifier PowerShell.Exiting` 注册退出清理
- 使用 `New-Item -ItemType Directory` 创建锁目录，`-ErrorAction Stop` 检测冲突
- 退出统一调用 `Do-Exit` 函数

### download.sh（Shell）

- 脚本开头获取脚本目录：`SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`
- 将脚本目录加入 PATH：`PATH="$SCRIPT_DIR:$PATH"`（确保找到本地 `jq`）
- `JSON_FILE`、`DOWNLOAD_ROOT` 等路径都基于 `$SCRIPT_DIR`
- 使用 `awk` 做浮点计算（不使用 `bc`，Windows 没有）
- 使用 `stat -c %s`（Linux）或 `stat -f %z`（macOS）获取文件大小，注意格式参数和选项之间有空格
- 依赖检查：`command -v jq` 失败时额外检查 `$SCRIPT_DIR/jq` 文件是否存在
- 锁目录用 `mkdir` + `trap 'rm -rf "$LOCK_DIR"' EXIT`
- 退出统一调用 `do_exit` 函数

### download.bat（BAT 包装）

- 设置 UTF-8 编码：`chcp 65001 >nul`
- 解析参数后调用 `powershell -ExecutionPolicy Bypass -File "download.ps1"`
- 支持 `--command=*`、`--silent`、版本号参数透传
- 默认命令为 `download`
- 末尾 `pause` 等待用户确认

---

## 跨平台注意事项

| 问题 | 解决方案 |
|------|----------|
| 浮点计算 | 用 `awk` 替代 `bc` |
| 文件大小获取 | `stat -c %s \|\| stat -f %z`（注意空格） |
| jq 查找 | `command -v jq` + 检查 `$SCRIPT_DIR/jq` |
| 进程检测 | 不做 PID 存活检测（不可靠） |
| 文件锁 | 用 `mkdir` 原子操作替代 `flock`（Git Bash 无 flock） |
| 脚本目录 | 用 `$(dirname "$0")` 获取，不用相对路径 |
| Content-Length | 取 `tail -n 1`（重定向产生多个响应），`< 1KB` 视为无效 |
| curl 进度 | 不捕获 stderr（`2>&1` 会吞掉进度条） |

---

## data.json 格式说明

> 此文件由开发者手动提供和维护，AI 不需要生成。

```json
[
    {
        "Download type": "Windows x64 System installer",
        "URL": "https://update.code.visualstudio.com/{version}/win32-x64/stable"
    },
    {
        "Download type": "Windows x64 User installer",
        "URL": "https://update.code.visualstudio.com/{version}/win32-x64-user/stable"
    }
]
```

- `Download type`：作为子文件夹名，也是状态记录中的 key
- `URL`：`{version}` 会被替换为实际版本号
- 下载 URL 来自 `https://update.code.visualstudio.com/{version}/{platform}/stable`
- 当前共 26 个下载任务，覆盖 Windows / macOS / Linux 各平台和格式

---

## 输出显示规范

### 跳过已完成任务

显示相对于版本目录的相对路径和文件大小：
```
⏭ 已完成，跳过: Windows x64 System installer/VSCodeSetup-x64-1.119.0.exe (149.85 MB)
```

### 下载任务信息

显示目录、URL、保存路径、预期大小：
```
📁 目录: Windows x64 zip
🔗 URL: https://update.code.visualstudio.com/latest/win32-x64-archive/stable
💾 保存到: ../latest/Windows x64 zip/VSCode-win32-x64-1.119.0.zip
📊 预期大小: 213.02 MB
📥 下载中...
```

### 下载完成

```
✅ 下载完成: Windows x64 zip/VSCode-win32-x64-1.119.0.zip (213.02 MB)
```

### 最终统计报告

```
=============================================
                下载统计报告
=============================================
总任务数：  26
成功数：    26
失败数：    0
跳过数：    20
忽略数：    0
=============================================
```
