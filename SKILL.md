---
name: claude-longrun-supervisor
description: Use when a user or supervising agent requests a fixed-duration long-running local task such as 2h/6h/12h continuous bug fixing, regression testing, codebase auditing, documentation, data cleanup, or repeated local verification. The supervisor can be Codex, OpenClaw, another agent, automation, or a human, but Claude CLI is the fixed local worker. Provides a round-based workflow for decomposition subagents, parallel Claude CLI workers, audit rounds, heartbeat/status files, commits, rollback-aware system configuration changes, and final reports.
---

# Claude Long-Run Supervisor

Use this skill to run a fixed-duration local task through Claude CLI workers while the upper-layer supervisor keeps decision authority.

## Design Principle

Separate judgment from labor.

- Use a stronger upper-layer supervisor for decisions, direction, risk control, acceptance, and user reporting.
- Use Claude CLI as the fixed local worker for execution-heavy work: reading files, searching code, running commands, installing dependencies, testing, editing files, writing logs, and drafting reports.
- Use decomposition and audit subagents so the supervisor does not do dirty work directly.
- Let Claude CLI absorb repetitive local labor because its execution and tool-use ability is strong.
- Keep final authority with the supervisor. Claude CLI can execute and audit, but it does not decide final acceptance.

## Role Model

### Upper-Layer Supervisor

The supervisor may be Codex, OpenClaw, another agent, automation, or a human operator.

The supervisor must only do:

- Set direction and goals.
- Generate prompts for decomposition, execution, and audit.
- Review structured decomposition reports, audit reports, and final summaries.
- Decide continue, split, parallelize, return for rework, switch mode, drain, stop, accept, or report.
- Perform only tiny spot checks when reports conflict or risks are high.

The supervisor must not do:

- Large-scale code reading.
- Repeated grep/search/test runs.
- Large diff review.
- Long log summarization.
- Dependency installation.
- Build/test matrix execution.
- Manual detailed audit work.

Delegate those to Claude CLI.

### Decomposition Subagent

Always send every supervisor direction to a decomposition subagent before execution.

The decomposition subagent must:

- Convert direction into Claude CLI worker tasks.
- Keep each task as a small target, normally planned for 30 minutes or less.
- Mark parallelizable and serial tasks.
- Assign read and write scopes.
- Prevent write-scope overlap between parallel workers.
- Define output files and acceptance criteria.
- Identify risks and dependencies.
- Avoid executing the task.

### Claude CLI Worker

Claude CLI is the fixed execution worker.

Claude CLI may:

- Run with high local permissions.
- Read and edit local files.
- Install dependencies.
- Search the web.
- Run expensive tests, builds, lint, and scripts.
- Modify system-level configuration when rollback records are created first.
- Commit local Git changes when rules are satisfied.
- Write version notes, changelogs, progress logs, and reports.

Claude CLI must:

- Follow the current round task only.
- Keep changes local unless explicitly authorized otherwise.
- Write results to files, not only stdout.
- Document every modification in the same round.
- Provide commands, evidence, pass/fail counts, and remaining risks.

### Claude CLI Audit Round

Every audit is also dirty work. Run it through Claude CLI.

Use an audit round to:

- Read recent outputs.
- Read diffs and modified files.
- Review test logs.
- Check documentation completeness.
- Check safety boundaries.
- Summarize risks.
- Recommend continue, rework, split, parallelize, switch mode, drain, or stop.

The supervisor reads the audit report and decides.

## Default Directory Selection

Choose the output directory in this order:

1. If the project already has `docs/maintenance/`, use it.
2. Else if this is a project repository, create `.longrun/`.
3. Else for temporary or projectless work, use `work/longrun/` in the current workspace.

Use this structure:

```text
<output-root>/
├── longrun-status.json
├── longrun-heartbeat.md
├── longrun-progress.md
├── resume-prompt.md
├── final-summary.md
├── system-config-changes.md
├── rounds/
│   ├── round001-breakdown.md
│   ├── round001-A-task.md
│   ├── round001-A-output.md
│   ├── round001-B-task.md
│   └── round001-B-output.md
├── audits/
│   └── round003-audit.md
├── test-results/
│   └── round001-checks.md
└── logs/
    ├── supervisor.log
    ├── watchdog.log
    └── round001-A-stderr.log
```


## Codex Goal Mode

When the upper-layer supervisor is Codex and the runtime exposes goal tools, default to goal mode for fixed-duration long-running local tasks.

Codex should:

- Create one goal for the concrete long-run objective before launching decomposition or Claude CLI workers.
- Treat the goal as the supervision container for status decisions, audit decisions, and final completion.
- Keep the goal active while Claude CLI workers are still producing useful output.
- Mark the goal `complete` only after draining, final audit, and final user-facing summary are finished.
- Mark the goal `blocked` only when the same blocking condition repeats for the runtime's required threshold and no useful Claude CLI work can continue.
- Avoid using goal mode for casual discussion, one-off explanations, or non-execution brainstorming.

This rule is Codex-specific. Other supervisors may use their own equivalent objective/session tracking mechanism.

## State Machine

Use these states:

```text
planning -> running -> auditing -> draining -> final_audit -> completed
```

- `planning`: create scope, output root, safety rules, and initial decomposition request.
- `running`: launch Claude CLI worker rounds.
- `auditing`: launch Claude CLI audit rounds at required points.
- `draining`: total time is reached; do not start new rounds; let the current active round finish unless stuck.
- `final_audit`: collect evidence, stop task-owned helpers, and generate reports.
- `completed`: final summary and user-facing summary exist.

## Timing Rules

- Require an explicit total duration from the user, such as `2h`, `6h`, or `12h`.
- Plan each worker task for 30 minutes or less, but do not treat 30 minutes as a hard kill line.
- Check status every 5 minutes.
- If Claude CLI is clearly active, let it continue.
- Stop a round only when it is clearly stuck, uselessly idle, fatal, spinning without a prompt, or invalid.
- When total duration is reached, enter `draining`: do not start new rounds; wait for the current round to finish naturally unless it is stuck.

## Activity and Stuck Criteria

Treat Claude CLI as active when any of these are true:

- Output file is changing.
- stderr is changing.
- CPU or IO activity exists.
- New files are being produced.
- A test/build command is still running.
- A child process is active.
- Claude CLI is visibly executing tool work.

Treat a round as stuck or invalid when any of these are true:

- It exceeds the task plan by a long time and has no CPU/IO/output/file activity.
- stderr shows fatal/error and the process does not exit.
- Output already contains completion/summary/next-step text but the process keeps running uselessly.
- A promptless `claude -p` or `--max-turns` process spins without a task.
- An audit round judges the current round invalid.

## Decomposition Flow

Never send a broad direction directly to a Claude CLI worker. Always decompose first.

Supervisor direction example:

```text
Continue validating the schedule add flow.
```

Send a decomposition prompt:

```text
You are the decomposition subagent. Convert the supervisor direction into Claude CLI worker tasks.
Do not execute tasks.
Each task must include goal, scope, allowed reads, allowed writes, forbidden actions, output file, acceptance criteria, risk, dependencies, and whether it can run in parallel.
Avoid overlapping write scopes between parallel tasks.
```

Approve, revise, or reject the decomposition before launching workers.

## Parallel Worker Rules

Do not set a fixed worker count. Allow as many parallel Claude CLI workers as the decomposition and local limits safely allow.

Parallel workers must:

- Have independent output files.
- Have non-overlapping write scopes.
- Avoid shared ports, shared dev servers, shared migrations, and shared config writes.
- Avoid modifying the same file.
- Declare dependencies.
- Use a machine-readable plan when automation is expected: see `references/parallel-plan-schema.md`.

If workers propose edits to the same file, stop parallel edits for that area and run a merge/audit round.

For automated fan-out, require this sequence:

1. Decomposition subagent writes a JSON plan following `references/parallel-plan-schema.md`.
2. Supervisor reads the plan and decides whether write scopes are safe.
3. `scripts/parse_decomposition_plan.ps1` normalizes the plan if it came from a Markdown decomposition report.
4. `scripts/start_parallel_round.ps1` launches Claude CLI workers for ready tasks, respecting dependencies and write-scope conflicts.
5. Supervisor reads the manifest and worker outputs, then launches a Claude CLI audit round.

## Claude CLI Command

Default command:

```powershell
claude -p --permission-mode bypassPermissions --output-format text "<round task>"
```

Do not use `--max-budget-usd` by default.

Use model or provider settings only when the local Claude CLI setup supports them and the supervisor explicitly chooses them.

## Status Check Every 5 Minutes

Every 5 minutes, check:

- Supervisor process is alive.
- Claude CLI worker PIDs are alive.
- Heartbeat file updates.
- Output files exist.
- stderr has no fatal errors.
- Worker process tree is not spinning uselessly.
- Total duration and drain state.

Write a short heartbeat update.

## Audit Cadence

Run a Claude CLI audit round:

- Every 3 worker rounds.
- Immediately after any code change.
- Immediately after config changes.
- Immediately after version/changelog changes.
- Immediately after test failure.
- Immediately after high-risk findings.
- Immediately after dependency installation.
- Immediately after system-level config modification.

Audit reports must include:

```text
# Audit Report

## Scope
- Rounds:
- Modified files:
- Commands:
- Test logs:

## Modification Reasonableness
- Conclusion:
- Evidence:

## Validation Sufficiency
- Covered:
- Missing:
- Weak evidence:

## Documentation Completeness
- Code changes documented:
- Version/changelog updated:
- Progress updated:
- Resume prompt updated:

## Risks
- Regression:
- Safety:
- Scope creep:
- Conflict:

## Decision Recommendation
- Continue / Rework / Split / Parallelize / Switch mode / Drain / Stop:
- Reason:
- Next worker tasks:
```

The supervisor reads only the audit report and decides.

## Mode Switching

If 5 consecutive worker rounds find no new bug, no code change, no test failure, and no high-risk issue, switch to regression/documentation mode.

Regression/documentation mode focuses on:

- Boundary tests.
- Regression checks.
- Page/route/config completeness.
- Documentation consistency.
- Version notes.
- Resume prompt.
- Final summary draft.
- Remaining risk inventory.
- Manual verification checklist.

If a new issue appears, switch back to fix/verify mode.

## Safety Boundaries

Claude CLI may run with high local permissions, but it is not the final authority.

Default allowed:

- Local code edits.
- Local tests/build/lint.
- Dependency install.
- Web search.
- Local documentation.
- Local version/changelog updates.
- Local Git commits.
- System-level config changes with rollback records.

Default forbidden unless explicitly authorized by the user:

- Upload.
- Deploy.
- Publish.
- Push to remote Git.
- Permanent deletion.
- Direct production data changes.
- Writing secrets, API keys, tokens, passwords, or AppSecret into memory, logs, commits, or replies.
- Account changes.
- Permission changes.
- `git reset --hard`.
- `git clean -fd`.
- Destructive database operations.

## Dependency Installation

Claude CLI may install dependencies.

Require each install to record:

- Command.
- Package(s).
- Project/global scope.
- Reason.
- Files changed, such as lockfiles.
- Validation result.
- Rollback method when practical.

Prefer project-local dependencies. Global installs are allowed only when useful and must be documented.

## Web Search

Claude CLI may search the web.

Require:

- Prefer official documentation and primary sources.
- Record search purpose and sources used.
- Do not execute downloaded scripts without reviewing and documenting risk.
- Do not store secrets from web or accounts.

## System-Level Config Changes

Before modifying system-level config, Claude CLI must record a rollback point in `system-config-changes.md`.

Record:

- Config name.
- Config path or command namespace.
- Old value, or why it could not be read.
- New value.
- Reason.
- Exact change command.
- Rollback command.
- Impact scope.
- Validation command/result.

System-level config includes global env vars, PATH, global package manager config, global Git config, CLI config, services, scheduled tasks, ports/firewall, IDE/tool settings, and anything persistent outside the project.

## Git Rules

Git commit is allowed. Git push is forbidden by default.

Before long-run starts:

- Record initial `git status`.
- Mark pre-existing changes.

Before commit:

- Ensure the change is valid and documented.
- Ensure relevant tests/checks ran.
- Ensure no unrelated user changes are included.
- Ensure no secrets or private data are included.
- Prefer focused commits at meaningful milestones.

Allowed:

- `git commit` for accepted local milestones.
- `git revert <commit>` to undo an AI-created bad commit.

Forbidden by default:

- `git push`.
- `git reset --hard`.
- `git clean -fd`.

## Whoever Modifies Documents

Whoever modifies files must document the modification in the same round.

Claude CLI must record:

- Files changed.
- Reason.
- What changed.
- Commands run.
- Results.
- Risks.
- Next steps.

If the project has version files, changelog, diary, or maintenance logs, update them in the same round according to project rules.

## Bundled Executable Scripts

Prefer the bundled scripts when the user asks for a repeatable local long-run loop. They are helpers, not a replacement for supervisor judgment.

### `scripts/start_decomposed_longrun_supervisor.ps1`

Starts the fuller automated loop: Claude CLI decomposition subagent, JSON plan parsing, parallel Claude CLI workers, Claude CLI audit, repeated until the duration ends.

Typical command:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\start_decomposed_longrun_supervisor.ps1" `
  -Repo "C:\path\to\repo" `
  -Objective "Fix and verify the local task until the time budget is reached" `
  -Hours 12
```

Main behavior:

- Selects output root using the standard priority: `docs/maintenance/`, `.longrun/`, then `work/longrun/`.
- Writes `decomposed-longrun-status.json`, `decomposed-longrun-heartbeat.md`, and `decomposed-longrun-progress.md`.
- Creates `decompositions/`, `decomposed-batches/`, `audits/`, and `logs/` folders.
- Runs a Claude CLI decomposition round for each batch.
- Parses the decomposition output into a JSON parallel plan.
- Launches dependency-aware parallel Claude CLI workers through `start_parallel_round.ps1`.
- Runs Claude CLI audit rounds after batches using `-AuditEveryBatches`.
- Stops launching new batches at the deadline, then runs `final_audit.ps1`.

Use this as the preferred executable script when the user wants the full strategy automated. A high-quality upper-layer supervisor should still periodically read the status, manifests, audits, and final report before making business or release decisions.

### `scripts/start_longrun_supervisor.ps1`

Starts a local Claude CLI long-run loop for one objective.

Typical command:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\start_longrun_supervisor.ps1" `
  -Repo "C:\path\to\repo" `
  -Objective "Fix and verify the local task until the time budget is reached" `
  -Hours 12
```

Main behavior:

- Selects output root using the standard priority: `docs/maintenance/`, `.longrun/`, then `work/longrun/`.
- Writes `longrun-status.json`, `longrun-heartbeat.md`, `longrun-progress.md`, and `resume-prompt.md`.
- Creates `rounds/`, `audits/`, `test-results/`, and `logs/` folders.
- Starts Claude CLI worker rounds with high local permissions by default.
- Checks status every 5 minutes.
- Triggers an audit round every 3 worker rounds and after detected changes or failures.
- Enters draining at total duration end and waits for the active round to finish.
- Calls `final_audit.ps1` to create `final-summary.md`.

Default orchestration note:

- This script remains the conservative sequential duration loop.
- Use `parse_decomposition_plan.ps1` and `start_parallel_round.ps1` when a supervisor wants automated parallel fan-out for a specific round.

### `scripts/parse_decomposition_plan.ps1`

Extracts a machine-readable JSON plan from a Markdown decomposition report and normalizes it.

Typical command:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\parse_decomposition_plan.ps1" `
  -InputFile "C:\path\to\decomposition-output.md" `
  -OutputFile "C:\path\to\parallel-plan.json"
```

The parser accepts:

- A fenced `json` code block.
- A `<!-- LONGRUN_PLAN_JSON --> ... <!-- /LONGRUN_PLAN_JSON -->` block.
- A plain JSON object in the decomposition output.

It validates required fields, task IDs, dependency references, prompts, and default `max_minutes`.

### `scripts/start_parallel_round.ps1`

Launches multiple Claude CLI workers from a normalized JSON plan.

Typical command:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\start_parallel_round.ps1" `
  -Repo "C:\path\to\repo" `
  -PlanFile "C:\path\to\parallel-plan.json" `
  -OutputRoot "C:\path\to\docs\maintenance"
```

Main behavior:

- Creates a timestamped `parallel-*` output folder.
- Writes one prompt per task.
- Starts ready tasks whose dependencies are complete.
- Allows unlimited parallel workers by default when safe; set `-MaxParallelWorkers` only when local resources require throttling.
- Blocks overlapping write scopes unless `-AllowOverlappingWriteScopes` is explicitly passed after supervisor review.
- Writes `manifest.json` with remaining/running/completed tasks and per-worker artifact paths.
- Supports `-NoBypassPermissions` for lower-risk runs.

Use this script for implementation or audit batches after the decomposition subagent has produced a reviewed plan.

### `scripts/run_round.ps1`

Runs exactly one Claude CLI worker or audit prompt from a prompt file and writes stdout/stderr to files.

Typical command:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\run_round.ps1" `
  -Repo "C:\path\to\repo" `
  -PromptFile "C:\path\to\prompt.md" `
  -OutputFile "C:\path\to\round-output.md" `
  -StderrFile "C:\path\to\round-stderr.log" `
  -PidFile "C:\path\to\round.pid"
```

Use this for:

- Manual parallel workers after decomposition.
- Extra audit workers.
- Focused retry rounds.
- Running Claude without bypass permissions by adding `-NoBypassPermissions`.

### `scripts/watchdog.ps1`

Watches an existing output root and records lightweight status observations.

Typical command:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\watchdog.ps1" `
  -OutputRoot "C:\path\to\docs\maintenance" `
  -CheckSeconds 300
```

The watchdog is intentionally conservative. It observes state and appends logs; it does not kill an active Claude CLI worker merely because the wall clock is long.

### `scripts/final_audit.ps1`

Creates a deterministic local `final-summary.md` from available run artifacts.

Typical command:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>\scripts\final_audit.ps1" `
  -Repo "C:\path\to\repo" `
  -OutputRoot "C:\path\to\docs\maintenance" `
  -Objective "Original long-run objective"
```

The script summarizes artifacts, Git state, `git diff --check`, and manual verification items. If a final Claude audit exists, include or cite it in the final user-facing summary.

## Bundled Reference Templates

Use `references/` files when building prompts or reviewing outputs:

- `decomposition-template.md`: required task decomposition structure for the decomposition subagent.
- `parallel-plan-schema.md`: JSON contract used by automated parallel fan-out scripts.
- `audit-template.md`: required audit report structure for Claude CLI audit rounds.
- `final-summary-template.md`: required maintainer-facing final report structure.

## Final Audit

When draining finishes, run a final audit.

Verify:

- Total duration reached.
- State is `completed`.
- No task-owned Claude CLI worker remains.
- Round outputs exist.
- Audit reports exist.
- Test results exist.
- Final changed files are documented.
- Versions and changelogs are consistent.
- Git commits are listed if created.
- Dependency installs are listed.
- Web sources are listed.
- System config changes and rollback commands are listed.
- Remaining risks are clear.
- Manual verification checklist is clear.

## Final Reports

Always generate:

- `final-summary.md`: detailed report for maintainers.
- User-facing summary: concise status, changes, validation, remaining risks, and next steps.

Final summary must include:

- Total duration.
- Round count.
- Parallel worker count or task count.
- Modified files.
- Dependency installs.
- Web searches/sources.
- System config changes.
- Test/build/lint commands.
- Pass/fail counts.
- Version changes.
- Git commits.
- Rollback points.
- Remaining risks.
- Manual verification checklist.
- Deployment/push status.

## Version

Current version: `0.4.1`

### 0.4.1 - 2026-06-19

Codex goal-mode default added.

Design rationale:

- When Codex is the upper-layer supervisor, fixed-duration long-running work should be tracked as an explicit goal so progress, completion, and blocking decisions are not lost across long supervision loops.
- Goal mode matches the intended separation of responsibilities: Codex owns the objective and decisions, while Claude CLI performs decomposition-heavy, execution-heavy, and audit-heavy labor.

Behavioral changes:

- Codex supervisors should create a goal before launching long-run decomposition or Claude CLI workers when goal tools are available.
- Codex should close the goal only after draining, final audit, and final user-facing summary.
- Goal mode is not required for casual discussion or non-execution planning.

Validation:

- `quick_validate.py` should pass for the skill folder.

### 0.4.0 - 2026-06-19

Full decomposed long-run supervisor loop added.

Design rationale:

- Complete the intended automation chain so the supervisor can launch one script that delegates task splitting, execution, and audit work to Claude CLI.
- Keep the upper-layer supervisor focused on reading state, manifests, audits, and final summaries rather than doing code-reading or task breakdown manually.
- Preserve the prior sequential and parallel scripts as smaller composable building blocks while adding a higher-level orchestration option.
- Make long-running local tasks easier to restart and inspect through separate status, heartbeat, progress, decomposition, batch, audit, and log artifacts.

Added resources:

- `scripts/start_decomposed_longrun_supervisor.ps1`: duration-based loop that runs Claude CLI decomposition, parses JSON plans, launches parallel worker batches, runs audit rounds, drains at the deadline, and generates a final audit.

Behavioral changes:

- The preferred full automation entrypoint is now `start_decomposed_longrun_supervisor.ps1`.
- `start_longrun_supervisor.ps1` remains available as the conservative sequential fallback.
- Every batch produces decomposition output, normalized plan JSON, a parallel manifest, optional audit output, and progress entries.
- `-MaxParallelWorkers 0` still means no script-level cap; `-AuditEveryBatches 1` audits every batch by default.

Known limitations:

- The script can automate the workflow, but it cannot replace a strong supervisor's judgment for release, deployment, production data, or business decisions.
- If decomposition output is malformed, the script stops at `decomposition_failed` instead of guessing a plan.
- Semantic conflicts still depend on the decomposition subagent declaring shared resources accurately.

Validation:

- PowerShell parser validation should pass for all bundled `.ps1` scripts.
- Static validation should cover JSON plan parsing and write-scope conflict detection.
- `quick_validate.py` from `skill-creator` should pass for the skill folder.

### 0.3.0 - 2026-06-19

Automated parallel fan-out support added.

Design rationale:

- Implement the user's preferred pattern more completely: decomposition is delegated, Claude CLI does execution-heavy parallel work, and the upper-layer supervisor mainly reviews plans/manifests and decides.
- Keep parallelism unlimited by default while making write-scope conflict detection the safety gate.
- Avoid forcing all long-run work through the sequential duration loop; allow a supervisor to launch safe parallel batches inside or alongside a long-run session.
- Make decomposition output machine-readable so different upper-layer agents can reuse the same contract.

Added resources:

- `scripts/parse_decomposition_plan.ps1`: extracts and validates JSON plans from decomposition reports.
- `scripts/start_parallel_round.ps1`: launches dependency-aware Claude CLI worker batches from a JSON plan and writes a manifest.
- `references/parallel-plan-schema.md`: canonical JSON schema and rules for decomposition subagents.

Updated resources:

- `references/decomposition-template.md`: now requires both human-readable reasoning and a fenced JSON plan.
- `SKILL.md`: now documents the automated fan-out sequence, parser script, parallel launcher, manifest behavior, conflict detection, and current orchestration boundaries.

Behavioral changes:

- Parallel workers can now be launched automatically from reviewed decomposition plans.
- Overlapping write scopes are rejected by default before worker launch.
- Dependency ordering is enforced by the parallel launcher.
- `-MaxParallelWorkers 0` means no fixed script-level cap; use a positive value only for local resource throttling.

Known limitations:

- `start_longrun_supervisor.ps1` is still the conservative sequential duration loop; it does not internally call the decomposition parser or parallel launcher yet.
- Parallel merge/audit decisions still belong to the upper-layer supervisor after reading `manifest.json` and worker outputs.
- Write-scope conflict detection is path-prefix based and cannot understand semantic conflicts such as shared ports, databases, global configs, or generated files unless the decomposition subagent declares them.

Validation:

- PowerShell parser validation should pass for all bundled `.ps1` scripts.
- `quick_validate.py` from `skill-creator` should pass for the skill folder.

### 0.2.0 - 2026-06-19

Bundled executable scripts and reference templates added.

Design rationale:

- Move the workflow from pure policy into repeatable local execution helpers.
- Keep the upper-layer supervisor focused on judgment while scripts handle common bookkeeping, prompts, heartbeat, rounds, audits, and summary generation.
- Preserve the user preference that Claude CLI performs execution-heavy work and audit-heavy work.
- Keep the first executable implementation conservative and sequential to avoid unsafe write-scope collisions before a future parallel fan-out wrapper is added.

Added resources:

- `scripts/start_longrun_supervisor.ps1`: starts a duration-based Claude CLI long-run loop, writes state files, launches worker rounds, triggers audit rounds, drains at the deadline, and calls final audit.
- `scripts/run_round.ps1`: launches one Claude CLI prompt with stdout/stderr/PID artifacts; can be used for manual parallel workers or focused audits.
- `scripts/watchdog.ps1`: observes an existing long-run output root every 5 minutes by default and logs status without aggressively killing active workers.
- `scripts/final_audit.ps1`: creates `final-summary.md` from local artifacts, Git status, and `git diff --check`.
- `references/decomposition-template.md`: standard decomposition output contract.
- `references/audit-template.md`: standard audit output contract.
- `references/final-summary-template.md`: standard final summary contract.

Behavioral changes:

- The skill now documents executable script entry points, parameters, and intended use.
- The script path supports `-NoBypassPermissions` for lower-risk runs while keeping high-permission Claude CLI as the default for this user's long-run pattern.
- Final reporting is now backed by a deterministic local script even if the final Claude audit is incomplete.

Known limitations:

- `start_longrun_supervisor.ps1` is sequential in version `0.2.0`; it does not automatically parse decomposition output into parallel worker launches.
- True automatic parallel fan-out should be implemented as a future architecture upgrade after defining conflict detection, write-scope locks, and worker-result merge rules.
- Smoke validation is limited to static parsing and skill validation unless a real Claude CLI long-run is started by the supervisor.

Validation:

- PowerShell parser validation should pass for all bundled `.ps1` scripts.
- `quick_validate.py` from `skill-creator` should pass for the skill folder.

### 0.1.0 - 2026-06-19

Initial skill draft created from the 12-hour cloud mini program bugfix supervision workflow.

Design rationale:

- Capture the proven pattern of using a stronger upper-layer supervisor for judgment while fixed Claude CLI workers do execution-heavy local work.
- Make decomposition subagents mandatory so the supervisor gives direction instead of hand-writing detailed worker tasks.
- Make Claude CLI audit rounds mandatory so code reading, diff review, and log review remain worker labor.
- Support long-running local tasks beyond one project, including code repair, regression checks, documentation, data cleanup, dependency setup, web research, builds, and system configuration.
- Preserve safety through state files, heartbeat, round outputs, audit reports, rollback records, Git rules, and final summaries.

Key decisions recorded:

- Fixed execution worker: Claude CLI.
- Supervisor can be Codex, OpenClaw, another agent, automation, or human.
- Default output root selection: `docs/maintenance/`, `.longrun/`, then `work/longrun/`.
- Status check cadence: every 5 minutes.
- Audit cadence: every 3 worker rounds and immediately after important changes/failures.
- Round duration: plan for 30 minutes but do not hard-kill active Claude CLI work.
- Total duration end: enter draining and wait for the current active round to finish.
- Parallelism: no fixed worker cap; rely on decomposition and write-scope safety.
- Automation permissions: allow high-permission local Claude CLI work, dependency install, web search, expensive tests/builds, system config changes with rollback, and local Git commits.
- Default forbidden: push, deploy, publish, permanent deletion, production data mutation, secrets logging, destructive Git resets/cleans.

Validation:

- Drafted as a SKILL.md-only first version.
- Includes required version notes per updated skill-creator policy.
- Scripts and templates remain future bundled resources, not yet implemented in this initial version.

Remaining risks:

- No bundled supervisor/watchdog scripts yet.
- No forward-test on a fresh long-running task yet.
- Needs future validation with `quick_validate.py` when available in the local skill-creator resources.
