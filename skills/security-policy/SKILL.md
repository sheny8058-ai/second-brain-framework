---
name: security-policy
description: 声明每个 Agent 的权限边界（网络、文件、凭据、命令），并在关键干预点拦截越权操作。当 Agent 要执行可能越界的操作时使用。触发条件：Agent 要访问外部网络、读写敏感路径、使用凭据、或执行系统命令。
---

# 安全策略声明

每个 Agent 有以下权限边界。执行任何可能越界的操作前，必须先查本策略。

## 干预点模型

策略在以下四个干预点生效，按操作类型触发对应的干预点（非全部串行通过）：

| 干预点 | 触发时机 | 检查内容 | 处置方式 |
|---|---|---|---|
| **pre_tool_call** | Agent 调用工具前 | 工具名、参数是否越权 | 允许 / 拒绝 / 需授权 |
| **input** | 数据写入前 | 路径、内容类型是否合规 | 允许 / 拒绝 / 脱敏 |
| **output** | 数据输出前 | 是否含凭据 / PII | 允许 / 脱敏 / 拒绝 |
| **post_tool_call** | 工具调用完成后 | 实际执行结果是否符合预期 | 记录审计 / 标记异常 |

**触发示例：**
- 读文件 → 触发 `pre_tool_call` + `input`
- 写文件 → 触发 `pre_tool_call` + `input`
- 输出结果 → 触发 `output`
- 执行命令 → 触发 `pre_tool_call` + `post_tool_call`

**核心原则：先拦截，再执行。** Agent 不得在干预点未通过时继续操作。

---

## 网络策略

| 允许访问 | 禁止访问 | 说明 |
|---|---|---|
| `127.0.0.1:3111`（agentmemory REST API） | 外部互联网 | 除非决策者明确授权 |
| `127.0.0.1:29896`（OpenClaw Gateway） | 未登记的内部服务 | 新服务需先登记到台账 |
| 本地模型（Ollama `127.0.0.1:11434`） | 云端 API（除非已登记） | 敏感数据走本地 |

**规则：**
- Agent 不得自行发起对外部互联网的请求
- 需要联网调研时，必须通过决策者授权的搜索工具
- 新增服务必须先写入权威源台账，再开放网络访问

---

## 文件策略

| 允许读写 | 只读 | 禁止访问 |
|---|---|---|
| `子项目/` 目录 | `治理/` 目录 | `语料/`（除非明确授权） |
| `templates/` 目录 | `复盘/` 目录 | `.env`、`.secret` 文件 |
| 决策者指定的工作目录 | `技能包/` 目录 | 其他 Agent 的私有目录 |

**规则：**
- 写入只进主拷贝（查权威源台账确认）
- 治理目录只读，修改必须走决策者批准
- 不得读取其他 Agent 的私有工作目录
- `.env`、`.secret` 等凭据文件对 Agent 不可见

---

## 凭据策略

| 凭据类型 | 管理方式 | Agent 可见性 |
|---|---|---|
| API Key（LLM、搜索等） | 由调度层在需要时注入 | 不可见 |
| 认证 Token（MCP、SSH 等） | 存在 `.secret` 文件，mode 0600 | 不可见 |
| 数据库密码 | 由调度层管理 | 不可见 |

**规则：**
- Agent 不得直接读取 `.env`、`.secret`、`*.key`、`*.pem` 文件
- 凭据由调度层（OpenClaw）在请求发出时注入，用后即弃
- Agent 输出中不得包含凭据内容（捕获过滤自动处理）
- 如需新增凭据，必须通过决策者授权，写入 `.env` 文件

---

## 命令策略

| 允许执行 | 需授权 | 禁止执行 |
|---|---|---|
| 读写文件、搜索、Grep | 安装新软件包 | `rm -rf`、`format`、`mkfs` |
| 运行已登记的脚本 | 修改系统配置 | `kill` 非自身进程 |
| Docker 操作（已登记容器） | 修改网络配置 | 修改其他 Agent 的容器 |
| Git 操作（已登记仓库） | 对外发布/上传 | force push 到 main/master |

**规则：**
- 破坏性命令（删除、格式化、kill）必须经决策者确认
- 对外操作（上传、发布、发送消息）必须经决策者确认
- 不得修改其他 Agent 的运行环境
- Git force push 到 main/master 被禁止

---

## 越权处理

当 Agent 发现操作可能越界时：

1. **停止执行**，不要尝试绕过
2. **报告决策者**，说明要做什么、为什么需要这个权限
3. **等待授权**，决策者批准后记录到台账
4. **执行操作**，完成后记录到审计日志

---

## 审计日志

所有越权请求（无论批准/拒绝）必须记录。支持两种格式：

### 格式 A：Markdown 表格（人工可读）

```markdown
## 越权请求记录

| 日期 | Agent | 请求内容 | 原因 | 决策 | 决策者 |
|---|---|---|---|---|---|
| YYYY-MM-DD | <Agent名> | <请求内容> | <原因> | 批准/拒绝 | <决策者> |
```

### 格式 B：JSON Lines（机器可读）

每行一条 JSON 记录，追加到 `治理/audit-log.jsonl`：

```json
{
  "timestamp": "2026-10-08T14:48:00Z",
  "agent": "hermes",
  "intervention_point": "pre_tool_call",
  "action": "read_file",
  "args": {"path": "/data/secret.env"},
  "decision": "deny",
  "policy": "block-credential-read",
  "reason": "凭据文件禁止访问",
  "approver": null
}
```

| 字段 | 说明 |
|---|---|
| `timestamp` | ISO 8601 时间戳 |
| `agent` | 触发请求的 Agent 名 |
| `intervention_point` | 触发的干预点（pre_tool_call / input / output / post_tool_call） |
| `action` | 工具名或操作名 |
| `args` | 操作参数 |
| `decision` | `allow` / `deny` / `pending` |
| `policy` | 触发的策略名 |
| `reason` | 拒绝/批准原因 |
| `approver` | 决策者名（`allow` 时填写；`deny` 或 `pending` 时留 `null`） |

**日志存储位置：** `治理/audit-log.jsonl`（每行一条 JSON，追加写入）

---

## 附录：机器可读策略模板（可选）

当未来接入运行时策略引擎时，可参考以下 YAML 格式。当前阶段仅供声明参考，不强制执行。

```yaml
version: 1
mode: advisory  # advisory=声明式, enforce=强制拦截
rules:
  - name: block-external-network
    match:
      intervention_point: pre_tool_call
      tool: http_request
      args:
        url: "!127.0.0.1:*"
    action: deny
    reason: "外部网络请求被禁止"

  - name: block-credential-read
    match:
      intervention_point: pre_tool_call
      tool: read_file
      args:
        path: "*.env|*.secret|*.key|*.pem"
    action: deny
    reason: "凭据文件禁止访问"

  - name: block-destructive-command
    match:
      intervention_point: pre_tool_call
      tool: execute_code
      args:
        command: "*rm -rf*|*format*|*mkfs*"
    action: deny
    reason: "破坏性命令被禁止"

  - name: redact-credentials-output
    match:
      intervention_point: output
      content_pattern: "sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36,}|password=|token="
    action: redact
    reason: "输出含凭据，已脱敏"
```

---

## 反模式

- **自行提权**：Agent 不得自行扩大权限范围
- **绕过策略**：不得通过间接方式（如让另一个 Agent 代理）绕过策略
- **凭据泄露**：不得在输出、日志、记忆中暴露凭据
- **静默越权**：越权操作不得静默执行，必须报告
- **跳过干预点**：不得在 pre_tool_call 未通过时直接执行
