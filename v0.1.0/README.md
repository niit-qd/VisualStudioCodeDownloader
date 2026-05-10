# VisualStudioCodeDownloader

Visual Studio Code 全平台离线下载器，支持断点续传、文件校验、并发互斥。

---

## 功能特性

- **全平台支持**：Windows（PowerShell / BAT）、Linux、macOS（Shell）
- **断点续传**：已完成的任务自动跳过，中断后重新运行只下载未完成的任务
- **文件完整性校验**：通过 `Content-Length` 验证下载文件大小，大小不匹配自动重新下载
- **下载进度显示**：实时百分比进度条
- **无限重试**：下载失败自动重试，间隔 3 秒
- **并发互斥**：同一版本目录下，PS1 和 SH 脚本互斥，防止重复下载
- **残留锁处理**：脚本异常退出后残留锁目录，可手动删除或重新运行
- **版本隔离**：不同版本各自独立 workspace，互不干扰
- **退出暂停**：默认退出时等待用户确认，`--silent` 模式直接退出
- **国际化（i18n）**：自动检测系统语言（中文/英文），支持 `--lang` 参数强制指定

---

## 文件说明

```
VisualStudioCodeDownloader/
├── data.json              # [需手动提供] 下载任务配置（URL 模板列表）
├── download.ps1           # PowerShell 脚本（Windows）
├── download.bat           # BAT 包装脚本（调用 PS1）
├── download.sh            # Shell 脚本（Linux / macOS / Windows Git Bash）
├── i18n/                  # 国际化语言包目录
│   ├── en.json            # 英文
│   └── zh.json            # 中文
├── jq                     # JSON 解析工具（Shell 脚本依赖，已自带）
├── README.md              # 使用文档
└── PROJECT_SPEC.md        # 项目重建说明文档（供 AI/开发者重建项目）
```

### 版本目录（Workspace）

每个版本会创建一个独立的 workspace 目录，所有运行时数据都存放在其中：

```
latest/                              # 版本目录（workspace）
├── .download.lock/                  # 互斥锁目录（mkdir 原子锁）
│   └── pid                          # 锁持有者的进程 PID
├── download_status.json             # 下载状态记录
├── Windows x64 System installer/
│   └── VSCodeSetup-x64-1.119.0.exe
├── macOS Apple silicon/
│   └── VSCode-darwin-arm64.zip
├── Linux x64/
│   └── code-stable-x64-xxx.tar.gz
└── ...                              # 共 26 个平台/格式
```

---

## 使用方法

### 下载最新版本（默认命令）

```bash
# Shell（Linux / macOS / Git Bash）
./download.sh

# Windows PowerShell
.\download.ps1

# Windows BAT（双击或命令行）
download.bat
```

### 下载指定版本

```bash
# Shell
./download.sh --version=1.119.0

# PowerShell
.\download.ps1 --version=1.119.0

# BAT
download.bat --version=1.119.0
```

### 静默模式（不暂停等待）

```bash
# Shell
./download.sh --silent
./download.sh --version=1.119.0 --silent

# PowerShell
.\download.ps1 --silent
.\download.ps1 --version=1.119.0 --silent
```

### 查看下载状态

```bash
# Shell
./download.sh --command=status

# PowerShell
.\download.ps1 --command=status
```

### 重置下载状态（清除记录，重新下载全部）

```bash
# Shell
./download.sh --command=reset

# PowerShell
.\download.ps1 --command=reset
```

### 参数组合

```bash
# 指定版本 + 指定命令
./download.sh --version=1.119.0 --command=status

# 指定版本 + 静默模式
./download.sh --version=1.119.0 --silent

# 指定版本 + 命令 + 静默模式
./download.sh --version=1.119.0 --command=download --silent

# 强制使用中文
./download.sh --lang=zh

# 强制使用英文
./download.sh --lang=en --version=1.119.0 --silent
```

---

## 命令行参数

| 参数 | 说明 |
|------|------|
| `--version=<版本号>` | 可选，默认 `latest`，指定要下载的 VSCode 版本号 |
| `--command=<命令>` | 可选，默认 `download`，指定要执行的命令，见下表 |
| `--lang=<语言>` | 可选，强制指定语言（`en`/`zh`），默认自动检测系统语言 |
| `--silent` | 可选，静默模式，退出时不暂停等待用户确认 |

### 命令列表

| 命令 | 说明 |
|------|------|
| `download` | 执行下载任务（默认命令） |
| `status` | 查看当前版本的下载状态记录 |
| `reset` | 重置当前版本的下载状态（清除记录，下次运行重新下载全部） |

---

## 下载任务配置

编辑 `data.json` 可自定义下载任务。每项包含两个字段：

| 字段 | 说明 | 示例 |
|------|------|------|
| `Download type` | 目标子文件夹名称 | `Windows x64 System installer` |
| `URL` | 下载 URL 模板，`{version}` 会被替换为实际版本号 | `https://update.code.visualstudio.com/{version}/win32-x64/stable` |

当前内置 26 个下载任务，覆盖：

- **Windows**：x64 / Arm64，System installer / User installer / zip / CLI
- **macOS**：Intel / Apple silicon / Universal，主程序 / CLI
- **Linux**：x64 / Arm32 / Arm64，tar.gz / deb / rpm / snap / CLI

### 新增或删除任务

直接编辑 `data.json`，新增或删除 JSON 数组中的条目即可。脚本只会下载 `data.json` 中列出的任务，不会受历史下载记录影响。

---

## 下载状态记录

`download_status.json` 存放在版本目录中，记录每个任务的完成状态：

```json
{
  "latest": {
    "Windows x64 System installer": {
      "completed": true,
      "fileName": "VSCodeSetup-x64-1.119.0.exe",
      "fileSize": 157145600,
      "completedAt": "2026-05-10 18:30:00"
    }
  }
}
```

| 字段 | 说明 |
|------|------|
| `completed` | 是否下载完成 |
| `fileName` | 下载文件名 |
| `fileSize` | 文件大小（字节），用于完整性校验 |
| `completedAt` | 完成时间 |

---

## 互斥锁机制

同一版本目录下，多个脚本实例不能同时运行（包括 PS1 和 SH 之间）。

- **实现方式**：`mkdir` 原子操作创建锁目录（`.download.lock/`），跨平台通用
- **不同版本**：各自独立，可以同时下载不同版本
- **异常处理**：脚本正常退出时自动清理锁目录；异常退出后残留的锁目录需手动删除
- **手动清理**：删除版本目录下的 `.download.lock/` 目录即可

---

## 依赖

| 依赖 | Shell 脚本 | PowerShell 脚本 | 说明 |
|------|-----------|----------------|------|
| `curl` | 必需 | 必需 | 下载工具 |
| `jq` | 必需 | 不需要 | JSON 解析（脚本目录自带 `jq`） |

---

## 版本号说明

下载链接来自 [Previous release versions](https://code.visualstudio.com/docs/supporting/faq#_previous-release-versions)。

- `latest`：最新稳定版
- `1.119.0`：具体版本号（需从下载链接中确认完整版本号）

---

## 网络超时配置

| 参数 | 值 | 说明 |
|------|-----|------|
| HEAD 请求超时 | 30 秒 | 获取文件名和大小 |
| 连接超时 | 30 秒 | curl 建立连接 |
| 下载总超时 | 600 秒（10 分钟） | 单个文件下载 |
| 重试间隔 | 3 秒 | 失败后等待 |
| 最大重试次数 | 无限 | 持续重试直到成功 |
