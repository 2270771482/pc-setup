# -*- coding: utf-8 -*-
"""把私密文件快照发布到私有仓 pc-setup-private。

用法：python D:\\AI\\脚本\\发布私有仓.py

做三件事：把 状态.md / 决策记录 / 任务.md / 文档\凭据恢复.md 复制进 private，
在 private 里提交，然后推到私有仓。没有变化时不提交也不推。
"""
from __future__ import annotations

import datetime
import os
import shutil
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = r"D:\AI"
PRIV = os.path.join(ROOT, "private")
ITEMS = ["状态.md", "决策记录", "任务.md", os.path.join("文档", "凭据恢复.md")]


def git(*args: str) -> subprocess.CompletedProcess[str]:
    # private\ 这个目录是会话（沙箱账户）建出来的，git 会以「仓库属于别人」为由拒绝操作，
    # 这里只对本仓库显式放行，不改用户的全局 git 配置。
    return subprocess.run(
        ["git", "-c", "safe.directory=" + PRIV, *args], cwd=PRIV, capture_output=True, text=True,
        encoding="utf-8", errors="replace",
    )


def main() -> int:
    if not os.path.isdir(os.path.join(PRIV, ".git")):
        print("private 还不是 git 仓库：" + PRIV)
        return 1

    for name in ITEMS:
        src = os.path.join(ROOT, name)
        dst = os.path.join(PRIV, name)
        if os.path.isdir(src):
            if os.path.isdir(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__"))
            print("复制目录 " + name)
        elif os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            print("复制文件 " + name)
        else:
            print("跳过（不存在）" + name)

    git("add", "-A")
    status = git("status", "--porcelain")
    if not status.stdout.strip():
        print("没有变化，无需提交")
        return 0

    msg = "快照 " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    commit = git("-c", "user.name=wuyanxv", "-c", "user.email=2270771472@qq.com",
                 "commit", "-q", "-m", msg)
    if commit.returncode != 0:
        print("提交失败：" + (commit.stderr.strip() or commit.stdout.strip()))
        return 1

    push = git("push", "origin", "HEAD:main")
    print((push.stdout or push.stderr).strip() or "已推送")
    return 0 if push.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
