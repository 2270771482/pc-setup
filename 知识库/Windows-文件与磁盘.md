# Windows：文件与磁盘

## AF_UNIX socket 文件会「僵死」

- 现象：`*.sock` / `engine.sock` 这类文件删不掉也改不了名，报「系统无法访问此文件」（`File.Delete`、`del`、`Rename-Item` 全失败）
- 关键发现：**同样操作在 D 盘完全正常，在 C 盘的某些目录会僵死**；优雅停止和重启系统都清不掉
- 判断：这是 reparse point 层面的问题，不是权限问题（权限问题会报"拒绝访问"）
- 绕法：把**整个目录**改名挪走（目录级重命名可以成功），让程序重建一个新目录
- 受害者实例：Docker Desktop（见 `Docker.md`）

## 删大量小文件：robocopy 镜像法

`takeown` + `icacls` + `Remove-Item` 删 `C:\Windows.old`（9 万多个文件）会卡十几分钟还删不干净。
改用「robocopy 空目录 /MIR 镜像过去 + `rd /s /q`」几秒搞定：

```powershell
robocopy "C:\空目录" "目标目录" /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1
rd /s /q "目标目录"
```

## 权限/所有权

- `takeown /f <路径> /r /d y` 拿所有权，`icacls <路径> /grant *S-1-5-32-544:F /t /c /q` 授权
- **`icacls` 授权用 SID 写**（`*S-1-5-32-544` 是 Administrators），中文系统下写英文组名会失败

## 删数据前先打包

删任何数据目录（数据库、旧配置）之前先压一份到 `D:\Backups`，确认存在再删。
删库不可逆，一份几十 MB 的保险成本可以忽略。实例：PostgreSQL 旧数据目录。

## 已知文件夹（文档/下载）重定向

- 用 `SHSetKnownFolderPath` + 注册表双保险：`HKCU\...\Explorer\User Shell Folders` 为准，
  `Shell Folders` 是解析后的副本（存在才更新，别创建半个）
- 验证方法：`SHGetKnownFolderPath` 回读，或看目标目录里有没有 `desktop.ini`
- 脚本：`脚本\restore-known-folders.ps1`（可重复执行）
- 会被谁改回去：OneDrive 打开「备份文件夹」时
