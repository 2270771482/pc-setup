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
