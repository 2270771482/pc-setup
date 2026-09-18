# -*- coding: utf-8 -*-
"""从任务文件和认领卡生成 D:\\AI\\任务清单.md。"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = Path(r"D:\AI")
TASK_DIR = ROOT / "任务"
CLAIM_DIR = ROOT / "进行中"
OUTPUT = ROOT / "任务清单.md"
ID_RE = re.compile(r"^T-\d{8}-\d{2,3}$")
FIELD_RE = re.compile(r"^-\s*([^：:]+)[：:]\s*(.*)$")
REQUIRED = ("ID", "状态", "优先级", "顺序", "最后更新", "完成标准", "下一步")
VALID_STATUS = {"待处理", "等用户", "阻塞", "长期"}


def read_record(path: Path) -> dict[str, str]:
    result: dict[str, str] = {"文件": path.name}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("# ") and "标题" not in result:
            result["标题"] = line[2:].strip()
        match = FIELD_RE.match(line)
        if match:
            result[match.group(1).strip()] = match.group(2).strip()
    return result


def load_tasks() -> tuple[list[dict[str, str]], list[str]]:
    tasks: list[dict[str, str]] = []
    errors: list[str] = []
    if not TASK_DIR.exists():
        return tasks, ["任务目录不存在"]

    seen: set[str] = set()
    for path in sorted(TASK_DIR.glob("T-*.md")):
        item = read_record(path)
        missing = [name for name in REQUIRED if not item.get(name)]
        if missing:
            errors.append(f"{path.name} 缺字段：{'、'.join(missing)}")
            continue
        task_id = item["ID"]
        if not ID_RE.fullmatch(task_id):
            errors.append(f"{path.name} 的 ID 无效：{task_id}")
        if not path.name.startswith(task_id + "-"):
            errors.append(f"{path.name} 与 ID {task_id} 不一致")
        if task_id in seen:
            errors.append(f"任务 ID 重复：{task_id}")
        seen.add(task_id)
        if item["状态"] not in VALID_STATUS:
            errors.append(f"{path.name} 的状态无效：{item['状态']}")
        try:
            item["顺序值"] = str(int(item["顺序"]))
        except ValueError:
            errors.append(f"{path.name} 的顺序不是整数：{item['顺序']}")
            item["顺序值"] = "9999"
        tasks.append(item)
    tasks.sort(key=lambda item: (int(item["顺序值"]), item["ID"]))
    return tasks, errors


def load_claim(task_id: str) -> dict[str, str] | None:
    path = CLAIM_DIR / f"{task_id}.md"
    return read_record(path) if path.exists() else None


def safe_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render() -> tuple[str, list[str]]:
    tasks, errors = load_tasks()
    lines = [
        "# 任务清单",
        "",
        "本页由 `脚本\\生成任务清单.py` 根据 `任务\\` 和 `进行中\\` 自动生成；**不要手改**。",
        "任务文件是事实源，认领卡是锁；总览即使短暂过期也不会造成任务互相覆盖。",
        "",
        "| ID | 任务 | 状态 | 处理者 | 优先级 | 最后更新 | 下一步 |",
        "|---|---|---|---|---|---|---|",
    ]
    for item in tasks:
        claim = load_claim(item["ID"])
        owner = claim.get("会话", "（未认领）") if claim else "（未认领）"
        state = "进行中" if claim else item["状态"]
        lines.append(
            "| " + " | ".join(
                safe_cell(value)
                for value in (
                    item["ID"], item.get("标题", item["文件"]), state, owner,
                    item["优先级"], item["最后更新"], item["下一步"],
                )
            ) + " |"
        )
    if not tasks:
        lines.append("| — | 暂无任务 | — | — | — | — | — |")

    lines.extend([
        "",
        "## 使用规则",
        "",
        "- 用户从本页挑任务；会话随后创建同 ID 的认领卡，再动手。",
        "- 新任务直接新增一个任务文件，不要编辑别人的任务文件。",
        "- 完成任务后删除自己的任务文件与认领卡；历史看决策记录和 Git。",
        "- `长期` 任务排在末尾，只在指标越界或用户主动提出时提醒。",
        "",
    ])
    return "\n".join(lines), errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只检查总览是否最新，不写文件")
    args = parser.parse_args()
    content, errors = render()
    for error in errors:
        print(f"错误：{error}")
    if errors:
        return 2
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current.replace("\r\n", "\n") != content:
            print("任务清单.md 不是最新生成结果")
            return 1
        print("任务清单.md 已是最新")
        return 0
    OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"已生成：{OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
