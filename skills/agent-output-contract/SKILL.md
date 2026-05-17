---
name: agent-output-contract
description: >
  Output contract for orchestrated agent runs. Every agent invoked by an orchestrator
  MUST end its session by writing a structured status.json so downstream scripts and
  dashboards can chain work, surface evidence, and aggregate progress.
  Activates on keywords like: orchestrate, task-id, status.json, handoff, agent-output,
  state contract.
---

# Agent Output Contract

> Every orchestrated agent run MUST produce a structured status file before ending.
> This is the only signal the orchestrator has that the agent finished.

---

## 📁 State Directory Structure

```
~/.copilot/state/<taskId>/
  ├── status.json     ← MUST write this before ending
  ├── evidence/       ← Drop raw artifacts here
  └── handoff.json    ← Write if chaining to another agent
```

The `taskId` is provided in your prompt as `TASK_ID=<id>` or via environment variable.

---

## 📋 status.json Schema (REQUIRED)

```json
{
  "taskId":      "<string, required>",
  "agent":       "<your agent name>",
  "status":      "done | running | failed | blocked | needs-input",
  "startedAt":   "<ISO-8601 UTC>",
  "completedAt": "<ISO-8601 UTC>",
  "summary":     "<one-paragraph human summary>",
  "known":       ["<verified fact 1>", "<verified fact 2>"],
  "missing":     ["<what data was unavailable>"],
  "needed":      ["<what input/decision is required>"],
  "estimated":   ["<reasonable inference, clearly labeled>"],
  "nextAction":  "agent:<name> | task:<taskId> | done | needs-user",
  "evidence":    ["evidence/query-1.json", "evidence/kubectl.txt"]
}
```

### Status Values

| Status | Meaning | When to Use |
|--------|---------|-------------|
| `done` | Task fully completed | No follow-up needed |
| `running` | Partial progress, checkpointing | Long-running, saving state |
| `failed` | Irrecoverable error | Cannot proceed without intervention |
| `blocked` | Waiting on external dependency | Deploy, infra, person |
| `needs-input` | Waiting on user clarification | Ambiguous requirements |

### Field Rules

- `known` / `missing` / `needed` / `estimated` → arrays of short strings, one fact per entry
- `evidence` paths are RELATIVE to the state directory
- `nextAction` tells the orchestrator what to do next
- All timestamps in UTC ISO-8601

---

## 📦 Evidence Directory

Save non-trivial outputs to `evidence/`:
- Query results (JSON/CSV)
- Command outputs (text)
- Diff patches
- Log excerpts

Reference them by relative path in the `evidence` array.

---

## 🔗 Handoff (Optional — for Agent Chaining)

If `nextAction` starts with `agent:`, write `handoff.json`:

```json
{
  "fromAgent":    "<your name>",
  "toAgent":      "<next agent>",
  "context":      "<why the next agent is needed>",
  "inputs":       { "key": "value" },
  "evidenceRefs": ["evidence/relevant-file.json"]
}
```

---

## 🚫 Hard Rules

1. **Never end without writing status.json** — orchestrator needs this signal
2. **Never invent evidence paths** — only list files you actually created
3. **Use UTC ISO-8601 timestamps** — no locale-dependent strings
4. **Keep arrays short and atomic** — one fact per entry
5. **Validate JSON before writing** — bad JSON breaks the pipeline

---

## 💡 Usage Example (PowerShell)

```powershell
$taskId = $env:TASK_ID  # or from prompt
$stateDir = "$env:USERPROFILE\.copilot\state\$taskId"
New-Item -ItemType Directory -Path "$stateDir\evidence" -Force | Out-Null

# Save evidence
$queryResult | ConvertTo-Json | Set-Content "$stateDir\evidence\latency-data.json"

# Write status
@{
  taskId      = $taskId
  agent       = "my-agent"
  status      = "done"
  startedAt   = $startTime
  completedAt = (Get-Date).ToUniversalTime().ToString("o")
  summary     = "Investigated latency spike; root cause identified."
  known       = @("p99 latency 2.3s at 14:32 UTC", "deployment merged at 14:25")
  missing     = @("trace-level logs for pod X")
  needed      = @()
  estimated   = @("Root cause likely deploy 12345 (correlation)")
  nextAction  = "done"
  evidence    = @("evidence/latency-data.json")
} | ConvertTo-Json -Depth 4 | Set-Content "$stateDir\status.json" -Encoding UTF8
```

---

## 🔍 Self-Critique (Before Writing status.json)

| Check | Fix |
|-------|-----|
| Every `known` item has supporting evidence file | Add evidence or move to `estimated` |
| Every `estimated` item is clearly labeled as inference | Don't put guesses in `known` |
| `evidence` array only contains files that exist | Remove phantom entries |
| `summary` is one paragraph, not a wall of text | Condense |
| `status` accurately reflects outcome | Don't claim `done` if blocked |
