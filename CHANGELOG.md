# Changelog

## 0.4.1 - 2026-06-19

- Added Codex-specific guidance: when Codex is the upper-layer supervisor and goal tools are available, fixed-duration long-running local tasks should default to goal mode.
- README now explains how Codex goal mode maps to the supervisor/Claude CLI division of labor.

## 0.4.0 - 2026-06-19

- Open-sourced the `claude-longrun-supervisor` Skill.
- Added public README positioning: zero project environment setup, one Skill for multi-agent collaboration.
- Current Skill supports decomposed long-run supervision, JSON plan parsing, dependency-aware parallel Claude CLI workers, audit rounds, heartbeat/status/progress files, and final reports.
