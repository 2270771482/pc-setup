# Docker Desktop

## 数据目录搬到 D 盘（目录联接）

`%LOCALAPPDATA%\Docker` 里的 `*.sock` 在 C 盘会僵死（见 `Windows-文件与磁盘.md`），
导致 Docker 每次启动都报
`initializing Ingest server: ... rename sailor-ingest.sock -> .stale: The file cannot be accessed by the system`。

做法（Docker 仍走自己的原路径，它不知道被搬了）：

```powershell
# 先优雅停止 Docker，再执行
mklink /J "%LOCALAPPDATA%\Docker" "D:\Virtual\Docker\AppData"
mklink /J "%LOCALAPPDATA%\docker-secrets-engine" "D:\Virtual\Docker\secrets-engine"
```

脚本：`脚本\docker-relocate-to-d.ps1`（旧目录只改名不删，可重复执行）。
搬到 D 盘后启停循环完全正常，磁盘映像落在 `D:\Virtual\Docker\AppData\wsl\disk\docker_data.vhdx`。

**注意**：`docker-secrets-engine` 这个目录也在 `%LOCALAPPDATA%` 下（不在 Docker 目录里），
第一次排查时漏了它，导致修好又坏——两处都要处理。

## 启停用官方命令，别强杀

```powershell
docker desktop status        # 看状态（还有 start / stop / restart）
docker desktop stop          # 优雅停止
```

（Docker Desktop 4.37+ 自带这些子命令。）

## 启动失败的排查顺序

1. 确认所有 docker 相关进程都没了（`Docker Desktop`、`com.docker.backend`、`com.docker.build`、
   `docker-agent`、`docker-offload`、`docker-scout`）
2. 检查那两个目录联接还在不在（Docker 升级或「重置」可能重建它们）
3. 检查 `%LOCALAPPDATA%\Docker\run` 与 `docker-secrets-engine` 里有没有删不掉的 `*.sock` 残留
4. 实在不行：把整个数据目录改名挪走让它重建（容器镜像为空时零损失）

## 环境干净时重建成本极低

Docker 里没有容器/镜像时，注销 WSL 发行版、删数据目录、重建，全都没有损失。
判断"能不能推倒重来"先看 `docker ps -a`、`docker images`、`docker volume ls`。
