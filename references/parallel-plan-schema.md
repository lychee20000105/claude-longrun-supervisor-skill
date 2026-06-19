# Parallel Plan Schema

Use this JSON object when a decomposition subagent produces parallel Claude CLI worker tasks.

```json
{
  "objective": "Original objective",
  "notes": "Any sequencing or risk notes for the supervisor",
  "tasks": [
    {
      "id": "task-001",
      "title": "Short task title",
      "prompt": "Complete worker prompt. Include exact scope, deliverables, validation, and reporting requirements.",
      "write_scopes": ["src/module-a/", "tests/module-a/"],
      "depends_on": [],
      "max_minutes": 30
    },
    {
      "id": "task-002",
      "title": "Read-only audit",
      "prompt": "Review recent changes and write an audit report only.",
      "write_scopes": [],
      "depends_on": ["task-001"],
      "max_minutes": 30
    }
  ]
}
```

Rules:

- `tasks` is required and must not be empty.
- Every task needs a stable unique `id`.
- Every task needs `title` and `prompt`.
- `write_scopes` must be as narrow as possible.
- Empty `write_scopes` means read-only unless the prompt explicitly allows writing reports.
- `depends_on` must reference task IDs in the same plan.
- Parallel tasks must not overlap write scopes unless a supervisor explicitly accepts the risk.
- Use `max_minutes: 30` unless a narrower subtask needs less time.