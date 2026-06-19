---
name: claude-longrun-supervisor
description: Use when a user or supervising agent requests a fixed-duration long-running local task such as 2h/6h/12h continuous bug fixing, regression testing, codebase auditing, documentation, data cleanup, or repeated local verification. The supervisor can be Codex, OpenClaw, another agent, automation, or a human, but Claude CLI is the fixed local worker. Optimized for low supervisor-token use through compact decision packets, digest-first review, bounded worker prompts, heartbeat/status files, audit rounds, and optional GitHub publication evidence.
---

# Claude Long-Run Supervisor

Run fixed-duration local work by keeping Codex/OpenClaw as the decision supervisor and Claude CLI as the execution worker.

## Default Mode: Token Floor

The skill body is intentionally short. Do not load `references/full-runbook-pre-0.6.0.md` unless debugging the skill itself or reconstructing old behavior.

Supervisor rule: spend decision tokens only. Claude CLI spends execution tokens.

1. Read only the compact decision packet first:
   - `token-budget-summary.json`
   - `longrun-status.json`
   - latest `Supervisor Digest`
   - or run `scripts/read_decision_packet.ps1 -OutputRoot <path>`.
2. Do not read raw logs, full diffs, full worker output, full release pages, or long reports unless the packet says `decisionNeeded != none`, validation failed, publish is blocked, safety risk exists, or the user asks for evidence.
3. If compact evidence is missing, make Claude summarize its own artifacts; do not manually inspect everything as supervisor.
4. User-facing chat during a run only reports new user-visible bugs, blocked/failed publish, final audit, or explicit user questions.

This follows Claude Code cost guidance: manage context proactively, delegate verbose operations to subagents, keep prompts focused, reduce unused MCP/tool overhead, and use compact summaries at task boundaries.

## Quick Start

Prefer the decomposed runner for non-trivial work:

```powershell
$skill = 'C:\Users\Administrator\.codex\skills\claude-longrun-supervisor'
& "$skill\scripts\start_decomposed_longrun_supervisor.ps1" `
  -Repo 'C:\path\to\repo' `
  -Objective 'Fix and verify the described issue' `
  -Hours 6
```

Use the sequential runner only for narrow tasks:

```powershell
& "$skill\scripts\start_longrun_supervisor.ps1" `
  -Repo 'C:\path\to\repo' `
  -Objective 'Run focused regression and repair failures' `
  -Hours 2
```

Read a compact packet without opening logs:

```powershell
& "$skill\scripts\read_decision_packet.ps1" -OutputRoot 'C:\path\to\repo\.longrun'
```

## Roles

- Supervisor: set objective, start/stop/drain, read compact packet, decide continue/rework/accept/report.
- Decomposition worker: split objective into bounded Claude CLI tasks with non-overlapping write scopes.
- Claude CLI worker: inspect files, run commands, edit, validate, and write compact evidence.
- Audit worker: review changes, validation, safety, and next decision; output a digest first.

The supervisor must not do large code reading, repeated grep/test runs, dependency setup, long log review, or large diff review. Delegate that work.

## Required Artifacts

Output root defaults: `docs/maintenance/` if present, else `.longrun/` in Git repos, else `work/longrun/`.

Required files:

- `token-budget-summary.json`: primary supervisor packet, `latestDigest <= 1200 chars`.
- `longrun-status.json`: state, round/batch, worker PIDs, next suggested check.
- `longrun-heartbeat.md`: human-readable heartbeat.
- `longrun-progress.md`: durable progress notes.
- `resume-prompt.md`: compact restart prompt.
- `rounds/`, `batches/`, `audits/`, `logs/`, `test-results/`: worker artifacts.
- `final-summary.md`: maintainer-facing final report.

Every worker/audit stdout must begin with:

```md
## Supervisor Digest
- Decision needed: none|supervisor|user
- Changed files: ...
- Validation: pass/fail + commands
- Publish: not attempted|pushed|blocked
- Blockers: ...
- Next: continue|rework|audit|drain|stop
```

## Decision Loop

1. Start or resume the runner.
2. Wait until `nextSuggestedSupervisorCheckAt` or `nextCheckAfterSeconds`.
3. Read the decision packet only.
4. Decide:
   - `continue`: no blocker and useful work remains.
   - `audit`: after important change, failure, or every configured audit cadence.
   - `rework`: audit finds a concrete issue.
   - `parallelize`: decomposition produced safe non-overlapping scopes.
   - `drain`: deadline reached or no more useful work.
   - `stop/accept`: final audit and final summary are sufficient.
5. Only open detailed artifacts when the packet justifies it.

## Safety Boundaries

Allowed by default for local long runs: local file edits in scope, dependency install, web search, expensive tests/builds, rollback-documented system config changes, local Git commits.

Forbidden unless separately authorized: push, deploy, publish, permanent deletion, production data mutation, secrets logging, destructive Git reset/clean.

Permanent deletion still requires the user's two-step explicit confirmation policy.

## Scripts

- `scripts/start_decomposed_longrun_supervisor.ps1`: decomposition + parallel batch loop; preferred default.
- `scripts/start_longrun_supervisor.ps1`: sequential round loop.
- `scripts/start_parallel_round.ps1`: launch tasks from a parsed decomposition plan.
- `scripts/parse_decomposition_plan.ps1`: extract JSON task plan from decomposition output.
- `scripts/run_round.ps1`: launch one Claude CLI prompt and capture output/stderr/PID.
- `scripts/watchdog.ps1`: observe state without aggressive killing.
- `scripts/final_audit.ps1`: deterministic `final-summary.md` from local artifacts.
- `scripts/read_decision_packet.ps1`: compact supervisor-facing status packet.

Detailed historical runbook: `references/full-runbook-pre-0.6.0.md`.

## Version

Current version: `0.6.0`.

### 0.6.0 - 2026-06-20

Token-floor architecture update after observing that the skill itself and supervisor review path still consumed too many Codex tokens.

Design rationale:

- Keep `SKILL.md` small because it is loaded whenever the skill triggers.
- Move the previous full runbook into `references/full-runbook-pre-0.6.0.md` for rare fallback/debug reads.
- Make compact decision packets the only default supervisor review surface.
- Add `read_decision_packet.ps1` so Codex/OpenClaw can inspect state with one bounded command.
- Tighten worker prompts so outputs start with `Supervisor Digest` and workers read summaries before raw artifacts.
- Reduce context recirculation by passing paths, counts, and digests instead of full prior manifests or long outputs.

External research incorporated:

- Claude Code docs recommend proactive context management, `/compact` instructions, focused prompts, subagents for verbose operations, and offloading log processing to hooks/skills.
- Claude Code best practices warn that large conversations, file reads, and command outputs fill context quickly and recommend aggressive context management plus subagents for investigation.

Validation required:

- PowerShell parser validation for all bundled `.ps1` scripts.
- `skill-creator/scripts/quick_validate.py` for the skill folder.
- Git diff review confirming `SKILL.md` is materially smaller while old detail remains available in references.

### Earlier versions

Full notes for `0.1.0` through `0.5.0` are preserved in `references/full-runbook-pre-0.6.0.md` and repository `CHANGELOG.md`.
