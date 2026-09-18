# Codex CLI（非交互调用）

## `--approve-for-me` 与 `-s` 互斥

`codex exec` 里 `--approve-for-me` 的定义就是「**在 workspace-write 沙箱里**自动审批」，
所以它自带沙箱策略，**不能再叠 `-s workspace-write`**，否则直接报：

```
error: the argument '--sandbox <SANDBOX_MODE>' cannot be used with '--approve-for-me'
```

正确写法是二选一：

- 要自动审批：`codex exec --json --skip-git-repo-check -C <工作区> --approve-for-me -`
- 要自己指定沙箱：`codex exec --json --skip-git-repo-check -C <工作区> -s workspace-write -`

**不要**为了让它「什么都能干」去加 `--dangerously-bypass-approvals-and-sandbox`——那等于把整台机器交出去。

## 哪些参数是真实存在的

用 `codex exec --help` / `codex exec resume --help` 逐条核对，别凭记忆。
实测存在且机器人会用到的：`--json`、`--skip-git-repo-check`、`-C/--cd`、`-s/--sandbox`、
`--approve-for-me`、`--ephemeral`、`-m/--model`、`-c key=value`、`-o/--output-last-message`。
`codex exec resume` 同样支持 `--json` 与 `--skip-git-repo-check`，续聊时沙箱/审批设置随原会话走。

## 非交互调用的最小自检

改完调用参数后，先跑一次「两轮」探针再交给用户用：第一轮让它记住一个暗号，
第二轮（带 `threadId` 调 `exec resume`）追问暗号，能答对才说明参数与续聊都通。
样例见 `D:\Projects\Feishu-Codex\scripts\probe-codex.js`（跑完会把测试会话 archive 掉）。

## 输出里的敏感串

CLI 报错里可能带 `cli_xxxx` 形式的 App ID，往聊天里回显前先做一次替换
（Feishu-Codex 里就是 `message.replace(/cli_[A-Za-z0-9_-]+/g, '[app-id]')`）。

## 需要「让用户点同意」就用 app-server，不要用 exec

`codex exec` 是非交互的，只有「自动审批」和「完全绕过」两种极端，没有中间态。
要让用户（哪怕在手机上）逐条确认，得跑 `codex app-server`（实验接口），用它的协议：

- 传输：**stdio 上的 JSONL**，一行一个 JSON-RPC 消息（`initialize` 要先发，`clientInfo` 必填）
- 起会话：`thread/start`（参数含 `cwd`、`sandbox: workspace-write`、`approvalPolicy: on-request`、
  `approvalsReviewer: user`——最后这个默认就是问用户）；旧会话用 `thread/resume`
- 发消息：`turn/start`（`{threadId, input:[{type:'text',text}]}`）、打断用 `turn/interrupt`
- 收输出：通知 `item/agentMessage/delta`（增量文本）、`turn/completed`（含 `turn.status`）
- **审批请求**（服务端 → 客户端，需要你回一个 response）：
  - `item/commandExecution/requestApproval` → 回 `{decision:'accept'|'acceptForSession'|'decline'|'cancel'}`
  - `item/fileChange/requestApproval` → 同上
  - `item/permissions/requestApproval` → 回 `{permissions: <原样回传 params.permissions>, scope:'turn'}` 表示同意，
    回 `{permissions:{}, scope:'turn'}` 表示不同意
  - 老接口 `execCommandApproval` / `applyPatchApproval` 用 `{decision:'approved'|'denied'|'abort'}`
- 协议 schema 可以自己导出核对：`codex app-server generate-json-schema --out <目录>`
  （Feishu-Codex 的副本在 `D:\Projects\Feishu-Codex\docs\app-server-schema`）

实测：审批请求里带 `command`、`cwd`、`reason`（中文原因），直接转发给用户即可；
用户回「允许」后命令真的执行、回「拒绝」后命令不执行且模型会明确说被拒绝。

## 联网搜索：`--search` 是顶层参数，`exec` 里用 `-c web_search="live"`

`codex exec --search ...` 会报 `tip: to pass '--search' as a value, use '-- --search'`——因为
`--search`（Enable live web search）**只挂在 `codex` 顶层**。在 `exec` 里开实时搜索要写成：

```powershell
codex exec --json -c web_search="live" "你的问题"
```

**看有没有真的搜**：输出里应有 `{"type":"item.completed","item":{"type":"web_search",...,"action":{"type":"search","queries":[...]}}}`。
2026-09-18 实测：走自定义提供方（DeepSeek 中转）**也能出真实搜索**，不是只有官方通道才行。

## 插件：配置里 `enabled = true` ≠ 装好了

只在 `config.toml` 里写 `[plugins."chrome@openai-bundled"] enabled = true`，加载器会报：

```
failed to load plugin: plugin is not installed plugin="chrome@openai-bundled"
```

正确做法（CLI 自带插件管理）：

```powershell
codex plugin list                       # 看 STATUS，要显示 installed, enabled
codex plugin add chrome@openai-bundled   # 从已配置的 marketplace 安装到 ~\.codex\plugins\cache\
codex plugin remove <插件>               # 卸载
codex plugin marketplace list            # 看有哪些 marketplace
```

`chrome` / `computer-use` 这类插件还需要**浏览器侧的 ChatGPT 扩展**才真的能用。本机只装了 Edge，
扩展 ID：Chrome 商店 `hehggadaopoacecdllhhajmbjkdcmajg`、Edge 商店 `odlomjlbamekndcpllcnffbgeohgkmjh`。
自查脚本在插件目录里：`scripts\installed-browsers.js`（本机装了哪些浏览器）、
`scripts\check-extension-installed.js`（扩展装没装）。

## 会话沙箱里跑 codex 要先给 home

沙箱账户没有家目录，直接跑 `codex ...` 会 `Error finding codex home` / `attempt to write a readonly database`。
两个办法：提权（以用户身份跑），或临时设
`$env:USERPROFILE='C:\Users\22707'; $env:HOME='C:\Users\22707'; $env:CODEX_HOME='C:\Users\22707\.codex'`
——但写 `state_5.sqlite` 仍会失败，**验证插件/搜索这类要写状态的，直接提权**。
