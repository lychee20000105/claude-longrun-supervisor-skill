# Claude Longrun Supervisor Skill

> 零环境搭建，一个 Skill 实现多 Agent 协作：上层监督者只做判断和决策，Claude CLI 负责拆解、执行、审计和长时间本地任务跑批。

`claude-longrun-supervisor` 是一个 Codex/OpenAI Agent Skill，用来把“12 小时不间断本地工作”这类需求变成可复用、可审计、可恢复的多 Agent 工作流。

它的核心思想很简单：

- **上层监督者**：用更强模型做方向判断、计划审查、风险决策和最终验收。
- **任务拆解 Agent**：把目标拆成 30 分钟以内的 Claude CLI 子任务。
- **Claude CLI Worker**：执行脏活累活，例如读代码、改文件、跑测试、查日志、整理报告。
- **Claude CLI Audit**：审查 worker 输出、diff、测试结果和剩余风险。
- **Skill 脚本**：负责状态文件、心跳、并行计划、进程启动、审计节奏和最终报告。

## 亮点

- **零环境搭建**：不需要 `npm install`、不需要 `pip install`、不需要服务端。复制 Skill 后即可使用内置 PowerShell 脚本。
- **一个 Skill 实现多 Agent 协作**：拆解、并行 worker、审计、最终总结都在同一个 Skill 里约定和执行。
- **Codex 默认 goal mode**：如果上层监督者是 Codex，并且运行环境支持 goal 工具，固定时长长跑任务默认启用 goal mode。
- **Codex 不亲自读代码**：Codex 只读状态、manifest、worker 输出、审计报告和最终总结；需要读代码、diff、日志时，必须派 Claude CLI discovery/audit worker。
- **适合长时间本地任务**：默认支持 12h，也可配置任意小时数。
- **自适应状态检查**：健康长跑默认 20 分钟检查一次，安静稳定时放宽到 30 分钟，只有新 bug、失败轮次、空输出、审计/收尾/疑似卡死时才切到 5 分钟快检。
- **默认 30 分钟子任务粒度**：适合把大任务切成可控 worker。
- **默认并行无固定上限**：只受 Claude CLI、本机资源和写入范围冲突限制。
- **写入范围冲突保护**：并行任务如果写入路径重叠，脚本默认拒绝启动。
- **到点不硬杀活跃任务**：进入 draining，不再开新轮，等待当前轮结束后做 final audit。
- **最终报告固定生成**：包括时长、批次、修改、测试、风险、回滚点和下一步。

## 适用场景

- 长时间修复代码、跑测试、查日志、补文档。
- 需要多个 Claude CLI worker 并行处理不同模块。
- 想让 Codex/OpenClaw/其他 Agent 只负责决策，把脏活交给 Claude CLI。
- 需要固定产出 `final-summary.md`、审计报告、进度文件和恢复提示。
- 需要将一次成功的长跑经验沉淀为可复用流程。

## 前置条件

这是“零项目环境搭建”，不是“零工具依赖”。你只需要本机已有：

- Windows PowerShell 5+ 或 PowerShell 7+
- 已安装并登录的 Claude CLI
- Codex/Agent 运行环境能读取这个 Skill

无需为本项目安装 Node/Python 包。

## 安装

把仓库克隆或复制到 Codex Skills 目录：

```powershell
git clone https://github.com/lychee20000105/claude-longrun-supervisor-skill.git "$env:USERPROFILE\.codex\skills\claude-longrun-supervisor"
```

如果你用的是其他 Agent 系统，只要它支持读取 `SKILL.md`，也可以把本仓库作为普通工作流模板使用。

## Codex 使用建议

如果上层监督者是 Codex，并且运行环境支持 goal 工具，固定时长的长时间本地任务应该默认启用 goal mode：

- 启动 Claude CLI worker 前先为本次长跑目标创建一个 goal。
- Codex 只围绕这个 goal 做状态判断、审计判断和最终验收。
- Claude CLI 继续负责拆解、执行、读代码、跑测试、审计报告等脏活累活。
- Codex 不直接打开源码、diff、测试日志或大段项目文件；如果需要这些证据，新增 Claude CLI discovery/audit worker 去读并生成报告。
- 当任务交给另一个 Codex 线程，例如 `codex://threads/...`，接收线程也必须遵守同样规则：先 goal mode，再读状态/报告，不亲自下场读代码。
- 到点 draining、final audit、用户汇报摘要完成后，再把 goal 标记为 complete。

## 自适应巡检策略

真实 12 小时长跑里，监督者不能过于死板地每 5 分钟打扰一次。当前版本默认按任务风险自适应调整：

- **20 分钟**：默认健康轮询间隔，适合 worker 正常运行、状态有进展的阶段。
- **30 分钟**：长时间安静且没有失败信号时的低噪音巡检间隔。
- **5 分钟**：仅用于用户刚反馈 bug、worker 失败/空输出、审计/收尾/final audit、或疑似卡死等高风险阶段。
- **状态持久化**：脚本会写入 `checkPolicy` 和 `nextSuggestedSupervisorCheckAt`，方便 Codex/自动化线程按建议时间再检查，而不是机械刷屏。

## 最推荐入口：完整自动化长跑

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\claude-longrun-supervisor\scripts\start_decomposed_longrun_supervisor.ps1" `
  -Repo "C:\path\to\repo" `
  -Objective "修复并验证这个本地任务，持续推进直到时间到点" `
  -Hours 12
```

如果确实需要固定间隔，可显式追加 `-FixedStatusCheck`；否则建议保持默认自适应参数：`-StatusCheckMinutes 20 -FastStatusCheckMinutes 5 -QuietStatusCheckMinutes 30`。

这个脚本会自动串起：

1. Claude CLI 拆解任务。
2. 解析 JSON 并行计划。
3. 并行启动 Claude CLI workers。
4. 跑 Claude CLI 审计轮。
5. 持续写状态/心跳/进度。
6. 到点后 draining。
7. 生成最终报告。

## 可组合脚本

| 脚本 | 作用 |
| --- | --- |
| `scripts/start_decomposed_longrun_supervisor.ps1` | 完整自动化主循环：拆解 → 并行执行 → 审计 → 最终报告 |
| `scripts/start_longrun_supervisor.ps1` | 保守串行主循环，适合低风险稳定跑批 |
| `scripts/parse_decomposition_plan.ps1` | 从拆解报告中提取并校验 JSON 并行计划 |
| `scripts/start_parallel_round.ps1` | 根据 JSON 计划并行启动 Claude CLI workers |
| `scripts/run_round.ps1` | 启动单个 Claude CLI prompt |
| `scripts/watchdog.ps1` | 观察长跑状态，不轻易杀进程 |
| `scripts/final_audit.ps1` | 汇总 artifacts，生成 `final-summary.md` |

`watchdog.ps1` 也默认使用自适应间隔：`-CheckSeconds 1200 -FastCheckSeconds 300 -QuietCheckSeconds 1800`。需要固定间隔时再追加 `-FixedCheck`。

## 输出目录

默认优先级：

1. 项目已有 `docs/maintenance/`：写入这里。
2. 项目是 Git 仓库但没有维护目录：创建 `.longrun/`。
3. 临时/非项目目录：写入当前工作区 `work/longrun/`。

常见输出：

- `decomposed-longrun-status.json`
- `decomposed-longrun-heartbeat.md`
- `decomposed-longrun-progress.md`
- `decompositions/`
- `decomposed-batches/`
- `audits/`
- `logs/`
- `final-summary.md`

## 并行计划格式

拆解 Agent 会输出类似 JSON：

```json
{
  "objective": "Fix and verify the requested task",
  "notes": "task-003 audits task-001 and task-002",
  "tasks": [
    {
      "id": "task-001",
      "title": "Implement scoped fix",
      "prompt": "Implement the scoped fix and document every modified file, command, validation result, risk, and next step.",
      "write_scopes": ["src/feature-a/", "tests/feature-a/"],
      "depends_on": [],
      "max_minutes": 30
    },
    {
      "id": "task-002",
      "title": "Update docs",
      "prompt": "Update only related docs and document changes.",
      "write_scopes": ["docs/feature-a/"],
      "depends_on": [],
      "max_minutes": 30
    },
    {
      "id": "task-003",
      "title": "Audit changes",
      "prompt": "Audit worker outputs, diffs, tests, logs, and write a report. Do not modify implementation files.",
      "write_scopes": ["docs/maintenance/"],
      "depends_on": ["task-001", "task-002"],
      "max_minutes": 30
    }
  ]
}
```

完整规范见 `references/parallel-plan-schema.md`。

## 安全边界

默认允许：

- 本地代码修改
- 自动安装依赖
- 联网搜索
- 耗时测试/构建
- 系统级配置修改，但必须记录回滚点
- 本地 Git commit

默认禁止：

- `git push`
- 部署/发布
- 永久删除
- 写入或泄露密钥
- 生产数据操作
- `git reset --hard`
- `git clean -fd`

这些边界写在 `SKILL.md`，可以按团队规则修改。

## 乱码修复与防护方法

本仓库曾出现 GitHub README 中文显示成 `????` 的问题。根因不是 GitHub 渲染，而是文件内容在生成阶段已经被非 UTF-8 管道写成了真实问号。

修复和防护方法：

- 不要通过会降级到本地 ANSI/OEM 代码页的管道写中文，例如把中文 here-string 直接管道给 Python stdin。
- 在 Windows 上生成中文 Markdown 时，优先使用 `.NET` 直写 UTF-8：`[System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))`。
- 提交前检查是否存在异常问号：统计 `README.md` 中连续 `????`，或在浏览器/GitHub 页面回读。
- 仓库使用 `.gitattributes` 固定 Markdown 和 PowerShell 文件为文本文件，避免换行/编码处理混乱。
- 如果已经变成 `????`，无法“转码恢复”，必须从原文重建内容。

## Skill 版本

当前 Skill 版本见 `SKILL.md` 的 `## Version`。本仓库要求所有 Skill 更新都同步版本号和详细变更说明。

## License

MIT

## 版本档案 / Release History

本项目后续更新默认保留历史文案，不覆盖原始上传内容。每个有意义的版本都会优先通过以下位置叠加记录：

- GitHub Releases：https://github.com/lychee20000105/claude-longrun-supervisor-skill/releases
- CHANGELOG.md
- docs/releases/

README 只保留当前版本入口和必要说明；历史版本细节按版本向上叠加，方便像 release 页面一样查看完整演进记录。
