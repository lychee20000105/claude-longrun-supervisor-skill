# Changelog


## v0.4.2 - 2026-06-19

- Initialized GitHub Releases / docs/releases/ as the public version archive.
- Added append-only documentation policy: future project copy should stack by version instead of replacing original upload content.
- Documentation-only update; source code was not intentionally changed.
## 0.4.2 - 2026-06-19

- Rebuilt `README.md` in UTF-8 to fix Chinese text that had been written as literal question marks.
- Added README notes documenting the encoding root cause and prevention method.
- Added `.gitattributes` for text file consistency.
- Added a hard `Supervisor Non-Execution Boundary`: Codex supervisors must not directly read source code, large diffs, test logs, runtime logs, or stack traces when this Skill is active.
- Added explicit `codex://threads/...` handoff behavior: receiving Codex threads inherit goal mode and must delegate code/log/diff inspection to Claude CLI discovery/audit workers.

## 0.4.1 - 2026-06-19

- Added Codex-specific guidance: when Codex is the upper-layer supervisor and goal tools are available, fixed-duration long-running local tasks should default to goal mode.
- README now explains how Codex goal mode maps to the supervisor/Claude CLI division of labor.

## 0.4.0 - 2026-06-19

- Open-sourced the `claude-longrun-supervisor` Skill.
- Added public README positioning: zero project environment setup, one Skill for multi-agent collaboration.
- Current Skill supports decomposed long-run supervision, JSON plan parsing, dependency-aware parallel Claude CLI workers, audit rounds, heartbeat/status/progress files, and final reports.
