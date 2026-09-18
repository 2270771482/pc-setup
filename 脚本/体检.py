# -*- coding: utf-8 -*-
"""主管理体检：只读检查，不修改机器和治理文件。"""

from __future__ import annotations

import datetime
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = Path(r"D:\AI")
STATE = ROOT / "状态.md"
DECISIONS = ROOT / "决策记录.md"
TASKS = ROOT / "任务清单.md"
TASK_DIR = ROOT / "任务"
CLAIM_DIR = ROOT / "进行中"
TASK_GENERATOR = ROOT / "脚本" / "生成任务清单.py"
STATE_LIMIT = 120
FIELD_RE = re.compile(r"^-\s*([^：:]+)[：:]\s*(.*)$")
TASK_ID_RE = re.compile(r"^T-\d{8}-\d{2,3}$")
VALID_STATUS = {"待处理", "等用户", "阻塞", "长期"}
SKIP_PARTS = {".git", "node_modules", "__pycache__"}

SECRET_PATTERNS = (
    re.compile(r"(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"https?://[^\s\"']+/(?:subscribe|api/v1/client/subscribe)\?[^\s\"']*(?:token|key|auth)=", re.I),
    re.compile(r"(?:OPENAI_API_KEY|ANTHROPIC_AUTH_TOKEN)\s*[\"']?\s*[:=]\s*[\"'](?!<|\$\{|%)[A-Za-z0-9_-]{16,}", re.I),
)

now = datetime.datetime.now()
print(f"=== 主管理体检 {now:%Y-%m-%d %H:%M} ===")


def line_count(path: Path) -> int | None:
    try:
        return len(path.read_text(encoding="utf-8").splitlines())
    except FileNotFoundError:
        return None


def read_record(path: Path) -> dict[str, str]:
    result: dict[str, str] = {"文件": path.name}
    try:
        source = path.read_text(encoding="utf-8")
    except (FileNotFoundError, UnicodeDecodeError):
        return result
    for raw in source.splitlines():
        line = raw.strip()
        if line.startswith("# ") and "标题" not in result:
            result["标题"] = line[2:].strip()
        match = FIELD_RE.match(line)
        if match:
            result[match.group(1).strip()] = match.group(2).strip()
    return result


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args], capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=30,
    )


def ignored(path: Path) -> bool:
    return any(part in SKIP_PARTS for part in path.parts)


def older_than(folder: Path, days: int, skip: tuple[str, ...] = ()) -> list[Path]:
    if not folder.exists():
        return []
    cutoff = now.timestamp() - days * 86400
    return [
        path for path in folder.rglob("*")
        if path.is_file() and path.name not in skip and not ignored(path)
        and path.stat().st_mtime < cutoff
    ]


def show_old(label: str, paths: list[Path], action: str) -> None:
    print(f"{label}：{len(paths)} 个{action}" if paths else f"{label}：0 个到期项")
    for path in paths[:20]:
        print(f"   - {path.relative_to(ROOT)}")
    if len(paths) > 20:
        print(f"   …另有 {len(paths) - 20} 个")


n = line_count(STATE)
if n is None:
    print("状态.md：不存在！")
else:
    warning = f"   <- 超过 {STATE_LIMIT} 行，该压实" if n > STATE_LIMIT else ""
    print(f"状态.md：{n} 行{warning}")

n = line_count(DECISIONS)
if n is None:
    print("决策记录.md：不存在！")
else:
    print(f"决策记录.md：{n} 行（索引应保持简短）")

print()
task_records: dict[str, dict[str, str]] = {}
task_errors: list[str] = []
required = ("ID", "状态", "优先级", "顺序", "最后更新", "完成标准", "下一步")
for path in sorted(TASK_DIR.glob("T-*.md")) if TASK_DIR.exists() else []:
    record = read_record(path)
    missing = [field for field in required if not record.get(field)]
    if missing:
        task_errors.append(f"{path.name} 缺字段：{'、'.join(missing)}")
        continue
    task_id = record["ID"]
    if not TASK_ID_RE.fullmatch(task_id):
        task_errors.append(f"{path.name} 的 ID 无效：{task_id}")
    if not path.name.startswith(task_id + "-"):
        task_errors.append(f"{path.name} 与 ID 不一致")
    if task_id in task_records:
        task_errors.append(f"任务 ID 重复：{task_id}")
    if record["状态"] not in VALID_STATUS:
        task_errors.append(f"{path.name} 的状态无效：{record['状态']}")
    task_records[task_id] = record

claims: dict[str, dict[str, str]] = {}
legacy_claims: list[Path] = []
state_lock: Path | None = None
if CLAIM_DIR.exists():
    for path in CLAIM_DIR.glob("*.md"):
        if path.name == "README.md":
            continue
        if TASK_ID_RE.fullmatch(path.stem):
            claims[path.stem] = read_record(path)
        elif path.stem == "共享-状态":
            state_lock = path
        else:
            legacy_claims.append(path)

# 已被认领的任务不再计入「等用户/长期」，否则同一条会被算两次（出现过「其他 -1」）
claimed_ids = {task_id for task_id in claims if task_id in task_records}
waiting = [
    record
    for record in task_records.values()
    if record.get("状态") == "等用户" and record["ID"] not in claimed_ids
]
long_term = [
    record
    for record in task_records.values()
    if record.get("状态") == "长期" and record["ID"] not in claimed_ids
]
active = [task_records[task_id] for task_id in claimed_ids]
other = len(task_records) - len(active) - len(waiting) - len(long_term)
print(
    f"任务：共 {len(task_records)} 条 —— 进行中 {len(active)}、等用户 {len(waiting)}、"
    f"长期 {len(long_term)}、其他 {other}"
)
for record in active:
    owner = claims[record["ID"]].get("会话", "未写会话")
    note = "（状态是等用户，锁不该长占）" if record.get("状态") == "等用户" else ""
    print(f"   [在做] {record['ID']} {record.get('标题', record['文件'])}（{owner}）{note}")
for record in waiting:
    print(f"   [等你] {record['ID']} {record.get('标题', record['文件'])}：{record['下一步']}")
for error in task_errors:
    print(f"   ！{error}")
for task_id in sorted(set(claims) - set(task_records)):
    print(f"   ！孤立认领卡：{task_id}.md（没有对应任务文件）")
for path in legacy_claims:
    print(f"   ！旧格式认领卡：{path.name}")
if state_lock:
    print("   [共享锁] 状态.md 正在被一个会话更新")

if TASK_GENERATOR.exists():
    check = subprocess.run(
        [sys.executable, str(TASK_GENERATOR), "--check"], capture_output=True,
        text=True, encoding="utf-8", errors="replace", timeout=30,
    )
    if check.returncode == 0:
        print("任务清单.md：与任务文件一致")
    else:
        print("   ！任务清单.md 需要重新生成")
else:
    print("   ！缺少任务清单生成脚本")

# 取消状态与引用的一致性：用户已经否决的事，不能再以任务形式冒出来
REF_RE = re.compile(r"T-\d{8}-\d{2,3}")
if STATE.exists():
    state_text = STATE.read_text(encoding="utf-8")
    cancelled_section = re.search(r"##\s*已取消[^\n]*\n(.*?)(?=\n##\s|\Z)", state_text, re.S)
    cancelled_ids = set(REF_RE.findall(cancelled_section.group(1))) if cancelled_section else set()
    referenced = set(REF_RE.findall(state_text))
    stale_files = sorted(cancelled_ids & set(task_records))
    dangling = sorted(referenced - set(task_records) - cancelled_ids)
    if stale_files:
        print("   ！这些任务用户已否决，任务文件却还在（删掉它，否则会一直在清单里冒出来）：")
        for tid in stale_files:
            print(f"     - {tid}")
    if dangling:
        print("   ！状态.md 引用了不存在的任务文件（引用过期：改成「已取消」或删掉指向）：")
        for tid in dangling:
            print(f"     - {tid}")
    if not stale_files and not dangling:
        print("已取消与引用：一致（没有已否决却没删的任务文件，也没有悬空引用）")

print()
if (ROOT / ".git").exists():
    status = git("status", "--porcelain")
    changed = [line for line in status.stdout.splitlines() if line.strip()]
    print(f"git：{len(changed)} 个文件未提交")

    tracked = [line.strip().replace("\\", "/") for line in git("ls-files").stdout.splitlines() if line.strip()]
    risky = []
    for name in tracked:
        lower = name.lower()
        if (
            lower == "状态.md" or lower.startswith("决策记录/")
            or lower == "文档/重装清单.md" or lower.startswith("private/")
            or lower.endswith(".kdbx")
        ):
            risky.append(name)
    if risky:
        print("   ！这些私密路径已被 Git 跟踪，公开前必须处理：")
        for name in risky:
            print(f"     - {name}")

    staged = [line.strip() for line in git("diff", "--cached", "--name-only").stdout.splitlines() if line.strip()]
    staged_hits: list[str] = []
    for name in staged:
        shown = git("show", f":{name}")
        if shown.returncode == 0 and any(pattern.search(shown.stdout) for pattern in SECRET_PATTERNS):
            staged_hits.append(name)
    if staged_hits:
        print("   ！暂存区疑似含密钥或订阅地址（不显示内容）：")
        for name in staged_hits:
            print(f"     - {name}")
else:
    print("git：尚未建仓；通用体检正常运行，Git 专项检查会在建仓后自动启用")

print()
secret_hits: list[tuple[Path, int]] = []
text_suffixes = {".md", ".txt", ".json", ".toml", ".yaml", ".yml", ".ps1", ".py", ".js", ".cjs", ".cmd"}
for path in ROOT.rglob("*"):
    if not path.is_file() or ignored(path) or path.suffix.lower() not in text_suffixes:
        continue
    try:
        source = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    for number, line in enumerate(source.splitlines(), start=1):
        if any(pattern.search(line) for pattern in SECRET_PATTERNS):
            secret_hits.append((path, number))
if secret_hits:
    print("疑似明文凭据（仅列位置，不显示内容）：")
    for path, number in secret_hits[:30]:
        print(f"   - {path.relative_to(ROOT)}:{number}")
else:
    print("疑似明文凭据：未发现")

legacy_re = re.compile(r"D:\\AI\\(?:Scripts|Tools|Docs|Generations|Prompts)(?:\\|\s|$)", re.I)
legacy_refs: list[tuple[Path, int]] = []
for path in (ROOT / "AGENTS.md", ROOT / "README.md", ROOT / "安装规划.md", ROOT / "状态.md"):
    if not path.exists():
        continue
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if legacy_re.search(line):
            legacy_refs.append((path, number))
if legacy_refs:
    print("陈旧英文目录引用：")
    for path, number in legacy_refs:
        print(f"   - {path.relative_to(ROOT)}:{number}")
else:
    print("陈旧英文目录引用：未发现")

print()
for drive in ("C:\\", "D:\\"):
    try:
        total, _, free = shutil.disk_usage(drive)
        print(f"{drive} 可用 {free / 1024 ** 3:.1f} GB / 共 {total / 1024 ** 3:.1f} GB")
    except OSError:
        pass

vault = Path(r"D:\Documents\密码.kdbx")
print(f"KeePassXC 密码库：{'存在' if vault.exists() else '不存在！'}（本项只检查文件，不检查备份）")

print()
show_old("认领卡", older_than(CLAIM_DIR, 1, skip=("README.md",)), "超过 24 小时，需问用户是否继续")
show_old("日志", older_than(ROOT / "产物" / "logs", 30), "超过 30 天，需问用户是否清理")
show_old("收件箱", older_than(ROOT / "收件箱", 30, skip=("README.md",)), "超过 30 天，需问用户如何处理")
show_old("文档", older_than(ROOT / "文档", 90), "超过 90 天，需提醒用户确认去留")

print()
for path in (STATE, DECISIONS, TASKS):
    if path.exists():
        age = (now - datetime.datetime.fromtimestamp(path.stat().st_mtime)).days
        print(f"{path.name}：最后更新 {age} 天前")

print()
print("（体检只读；未建立 Git 也可以运行）")
