# -*- coding: utf-8 -*-
"""提交并推送私密仓 pc-setup-private。

用法：python D:\\AI\\脚本\\发布私有仓.py

2026-11-18 起，`状态.md` / `任务.md` / `决策记录\\` / `凭据恢复.md` 都**直接住在**
`D:\\个人\\private`（唯一事实源），不再是"从 D:\\AI 复制过去的快照"，
所以这个脚本不再复制文件，只负责：看有没有改动 → 提交 → 推送。
没有变化时它什么都不做。
"""
from __future__ import annotations

import datetime
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

PRIV = r"D:\AI\private"

# 这里的东西是唯一事实源，不该被"从别处复制"覆盖；列出来只是为了在报错时提示
EXPECTED = ["状态.md", "任务.md", "决策记录", "凭据恢复.md"]


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

    missing = [n for n in EXPECTED if not os.path.exists(os.path.join(PRIV, n))]
    if missing:
        print("警告：private 里缺少 " + "、".join(missing) + "（不阻止提交）")

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
