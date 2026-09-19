# PowerShell

## 编码：脚本一律只写 ASCII

PowerShell 5.1 会把**无 BOM 的 UTF-8 脚本按 ANSI 解析**，脚本里写中文会导致语法错误、窗口一闪即退。
所以交给 PowerShell 执行的脚本**只写 ASCII**；中文放到 Markdown 或 Python 里
（Python 3 读源码默认 UTF-8，不受影响，所以中文工具脚本可以写成 `.py`）。

## `sc.exe config` 在 PowerShell 里传参数会失败

`sc.exe config <服务> binPath= ...` 在 PowerShell 里会打印用法（等号被吃）。
改服务启动参数请直接改注册表：
`HKLM\SYSTEM\CurrentControlSet\Services\<服务名>\ImagePath`。

（改**启动类型**用 `Set-Service -StartupType Manual`，但需要管理员，走 UAC 脚本。）

## 给用户双击的脚本：加 `-WindowStyle Hidden`

隐藏控制台窗口，避免用户误点进「选择」模式卡住进程。

## 输出中文到控制台

Python 工具脚本里加 `sys.stdout.reconfigure(encoding="utf-8")`，否则中文可能抛编码异常。

## 扫目录时控制输出量

提权遍历用户目录时**先按扩展名和体积过滤**，别让脚本把二进制文件的内容打进会话
（曾经因为 grep 二进制把几十万 token 灌进对话，直接爆上下文）。

## 常用组合

## 从 Node/工具里拉起 PowerShell 时，安全模块可能加载失败

现象：`powershell -NoProfile -NonInteractive -File x.ps1` 里 `ConvertTo-SecureString` 报「找不到命令」，
改成 `Import-Module Microsoft.PowerShell.Security` 又报 `FormatXmlUpdateException`（TypeData 重复）。
原因：父进程注入的 `PSModulePath` 里混进了 PowerShell 7 的模块目录（Codex 运行时会注入），
PS 5.1 去加载同名模块就炸。

对策（选一，推荐第一种）：**别用这个模块**——直接用 .NET：

```powershell
Add-Type -AssemblyName System.Security            # 否则找不到 ProtectedData 类型
$blob = [System.Security.Cryptography.ProtectedData]::Protect(
    [System.Text.Encoding]::UTF8.GetBytes($plain), $null, 'CurrentUser')
$plain2 = [System.Text.Encoding]::UTF8.GetString(
    [System.Security.Cryptography.ProtectedData]::Unprotect($blob, $null, 'CurrentUser'))
```

另一种是收敛子进程的 `PSModulePath` 只留系统路径。
顺带：脚本里要输出中文就给文件加 UTF-8 BOM（无 BOM 会被 PS 5.1 按 ANSI 读，中文全乱）。

## Windows 上写 .cmd 与后台起服务的两个坑

- **`.cmd` 里写中文必须存成 GBK（编码 936）**：`cmd.exe` 不按 UTF-8 读 `.cmd`，无 BOM 的 UTF-8
  中文注释会把**后面的行一起吃掉**（报「不是内部或外部命令」）。要么全 ASCII，
  要么用 `[System.Text.Encoding]::GetEncoding(936)` 转存。（PowerShell 脚本的规矩相反：UTF-8 带 BOM。）
- **别在 WMI `Win32_Process Create` 里塞带嵌套引号的长命令行**：引号很容易被吃掉，
  进程起来了却什么都没执行。后台起服务用
  `Start-Process -FilePath … -ArgumentList … -WindowStyle Hidden -RedirectStandardOutput/-Error`，
  进程能活过当前会话，输出还落盘。

## 给原生命令传「空字符串」：别用 `''`，会被当成两个引号字符

PowerShell 5.1 调原生命令时，`& exe -N ''` 传过去的其实是**字面的两个单引号**（`''`），不是空字符串。
实例：`ssh-keygen -t ed25519 -N '' ...` 本意是"不设口令"，结果钥匙照样带口令（那把钥匙后来直接不可用）。
可靠做法：用 `cmd /c` 包一层，写 `-N ""`；或者干脆把命令写进 `.cmd` 脚本（记得纯 ASCII）再执行。

## 脚本里要引用中文目录：用字符码拼，别直接写中文

即使守着「脚本只写 ASCII」，也常需要落到中文目录（如 `产物\logs`）。
直接写中文路径会被按 ANSI 读成乱码（`产物` → `浜х墿`），`Add-Content` 直接报「找不到路径」。
做法：`$log = 'D:\AI\' + [char]0x4EA7 + [char]0x7269 + '\logs\x.txt'`（产=4EA7，物=7269）。

- 清空并删目录：`robocopy 空目录 目标 /MIR` + `rd /s /q`
- 找大文件：`.NET Directory.EnumerateFiles` 比 `Get-ChildItem -Recurse` 快很多
- 提权跑脚本：`Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$p -Verb RunAs -WindowStyle Hidden`

## 改完环境变量，已打开的终端不会自动更新

改用户或系统 PATH 只影响之后新建的进程；Windows Terminal、VS Code、Codex 里已有的终端
（甚至新开的标签页）可能继续用旧 PATH。让当前窗口立即生效：

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')
```

改完先 `Get-Command <命令>` 验证，再继续执行。Windows PowerShell 5.1 默认 Restricted 时，
带 `.ps1` 的 shim 仍可能被拦，优先试同名 `.cmd`（如 `pnpm.cmd`）。

如果旧进程连刷新都不方便，可在它已有的 PATH 目录里放同名 `.cmd` 转发 shim；用户可写的
`%LOCALAPPDATA%\Microsoft\WindowsApps` 常已在 PATH 中。shim 里用绝对路径调用真正的程序，
不要依赖当前 PATH。

若 shim 已执行但 Node 报 `Cannot find module`，说明目标运行时不在旧进程可访问范围内；
把运行时复制到 shim 同目录，并改成 `%~dp0<runtime>\...` 的相对调用，做成自包含。

## 别拿保留字当函数名：`Data`、`Filter`、`Process` 都会被解析器抢走

写了个 `function Data([object]$e) { ... }` 来拆事件 XML，脚本直接报
`Data 节缺少自己的语句块 (MissingStatementBlockForDataSection)` ——
因为 **`data` 是 PowerShell 的保留关键字**（`data { ... }` 数据段），
定义和调用处都被解析成数据段，整脚本挂掉。

同类保留字别用：`data`、`filter`、`process`、`begin`、`end`、`param`、`function`……
命名加个动词前缀就躲开了（`GetEvData`）。**改完先用 `-NoProfile -File` 空跑一遍验证语法**，
别等到提权跑完才发现解析错误——那次用户白点了两次 UAC。

## 两条终端不是同一个 PowerShell（用户问过："为什么你自己跑就没这么多事"）

2026-09-19 实测对比（**这不是权限差异，两边都是普通用户 22707、都没提权**）：

| | 我这边（Codex 派生的命令） | 用户右键「在终端中打开」 |
|---|---|---|
| 程序 | `pwsh` **7.6.5 (Core)** | `powershell.exe` **5.1.26100**（系统自带） |
| 位置 | `C:\Users\22707\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe`（**Codex 自带，不是系统安装**） | `C:\Windows\System32\WindowsPowerShell\v1.0\` |
| PATH | Codex 启动那一刻的快照，头部塞满它自带的运行时（poppler、libheif…） | 用户/系统 PATH 的当前值 |
| 沙箱 | 默认可写范围只有 `D:\AI`，碰别处要申请提权 | 无沙箱 |
| 加载 | `-NoProfile` 式、非交互，输出被捕获 | 交互、可读写自己的目录 |

Windows Terminal 的默认配置文件就是 **Windows PowerShell（5.1）**，所以用户看到的是 5.1 的行为：
`.cmd` 按 GBK 读、没有 `??`/`-Parallel` 一类新语法、`ConvertFrom-Json` 老版本行为不同。
**判断"这条命令该按哪个版本写"时，先看是谁在跑。**

**2026-09-19 已按用户要求统一**：装了系统级 PowerShell 7 并把它设成 Windows Terminal 的默认配置档。
装的时候踩到的点，重装时会再遇到：

- **装之前先开代理**。`winget install --id Microsoft.PowerShell --exact` 会从 GitHub 拉包，
  国内直连报 `InternetOpenUrl() failed. 0x80072efd`。Clash Verge 起来（系统代理）之后一次就过。
- winget 给的 `--proxy http://127.0.0.1:7897` 这种写法**我们的 winget 1.29 不认**（会直接打印帮助），
  靠系统代理即可，别再试这个参数。
- **winget 装的是 Store/MSIX 版，不是 MSI**：落点是
  `C:\Program Files\WindowsApps\Microsoft.PowerShell_<版本>_x64__8wekyb3d8bbwe`，
  `pwsh` 通过别名 `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe` 暴露。
  所以**别去 `C:\Program Files\PowerShell\7\pwsh.exe` 找**（那是 MSI 版的位置，装 MSIX 时不存在）。
- **Windows Terminal 的配置档要自己加**（别指望自动生成）：在
  `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` 的
  `profiles.list` 里加一条，**GUID 用 `{574e775e-4f2a-5b96-ac1e-a2962a402336}`**
  （这是 WT 给 PowerShell Core 预留的动态配置档 GUID，用同一个会覆盖它、不会出现两个重名条目），
  commandline 写 `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`；再把 `defaultProfile` 指过去。
  改前备份；**WT 在运行时可能回写设置，改之前先确认 `Get-Process WindowsTerminal` 是空的**；
  写回要用**无 BOM 的 UTF-8**（`[IO.File]::WriteAllText($p,$s,(New-Object Text.UTF8Encoding($false)))`）。
