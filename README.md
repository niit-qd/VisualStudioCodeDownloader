# VisualStudioCodeDownloader
Visual Studio Code Downloader

---

### 描述
提供一个分目录自动下载`Visual Studio Code`版本的脚本。

下载链接来自于[Previous release versions](https://code.visualstudio.com/docs/supporting/faq#_previous-release-versions)
本脚本会使用该处的版本链接表格组合为json数据[data.json](data.json)。
参考：[在线 HTML 表格 转 JSON 数组](https://tableconvert.com/zh-cn/html-to-json)
版本号。

---

### 脚本

可以修改脚本中的具体参数直接执行。


- shell
  [download.sh](download.sh)
- bat with powershell
  [download.bat](download.bat)
  [download.ps1](download.ps1)

---

### 参数

版本号：[updates](https://code.visualstudio.com/updates)
真正的版本号，需要从页面给出的下载来连接中找出。
示例：
- `latest`：最新版本。官方未做介绍，验证得知。
- `1.117.0`：具体的版本。页面显示的是`1.117`，需要查看链接中的字段来得知真正版本号。

---

### 示例

1. shell
    ``` shell
    # version=latest
    version=1.117.0
    ./download.sh $version
    ```
    注意：需要提前安装`jq`命令，并配置到`PATH`中。
2. bat with powershell
    ``` bat
    @REM version=latest
    version=1.117.0
    download.bat
    ```

---

### 其他

有点懒，本脚本主代码片段来源于[豆包](https://www.doubao.com/chat)。^_^
