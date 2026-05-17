---
name: cross-session-planner
description: >
  Cross-session task tracker and intelligent backlog planner. Harvests pending tasks
  from ALL past Copilot CLI sessions, deduplicates, clusters into projects, scores
  priority, detects completion/staleness, and produces an actionable backlog.
  Activates on keywords like: pending tasks, backlog, what's pending, cross-session,
  plan my work, what should I do, task tracker, consolidate tasks, what's left,
  sprint planning, prioritize, club tasks, optimize tasks.
---

# Cross-Session Planner Skill

> **Mission**: Build a cross-session task index with provenance, confidence, stable identity,
> and human-readable rendering. Never lose track of work across sessions.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks about pending/remaining/incomplete tasks
- User says "what should I work on", "plan my work", "backlog"
- User asks to consolidate, club, or optimize tasks
- User asks "what's left" or "what did I miss"
- Start of a new work session (proactive backlog refresh)
- User says "sprint planning" or "prioritize"

---

## 📁 ARTIFACTS

| File | Purpose | Format |
|------|---------|--------|
| `~/.copilot/knowledge/backlog.json` | Canonical machine-readable task state | JSON |
| `~/.copilot/knowledge/backlog.md` | Human-readable backlog report | Markdown |

**Rule**: `backlog.json` is the source of truth. `backlog.md` is a rendered view.

---

## 🔄 EXECUTION PIPELINE

Execute these stages in order. Each stage feeds into the next.

### Stage 1: COLLECT SOURCES

Query the `session_store` database for all raw material:

```sql
-- 1a. All checkpoints with pending work (richest source)
SELECT c.session_id, s.summary, s.updated_at, c.checkpoint_number,
       c.title, c.next_steps, c.work_done
FROM checkpoints c
JOIN sessions s ON c.session_id = s.id
WHERE c.next_steps IS NOT NULL AND c.next_steps != ''
ORDER BY s.updated_at DESC
LIMIT 50;

-- 1b. Latest checkpoint per session only (dedup within sessions)
SELECT c.session_id, s.summary, s.updated_at, c.checkpoint_number,
       c.title, c.next_steps, c.work_done
FROM checkpoints c
JOIN sessions s ON c.session_id = s.id
WHERE c.checkpoint_number = (
  SELECT MAX(c2.checkpoint_number) FROM checkpoints c2
  WHERE c2.session_id = c.session_id
)
AND c.next_steps IS NOT NULL AND c.next_steps != ''
ORDER BY s.updated_at DESC;

-- 1c. FTS5 augmentation for work-oriented language
SELECT content, session_id, source_type FROM search_index
WHERE search_index MATCH 'pending OR blocked OR "next step" OR remaining OR TODO OR "need to" OR "follow up" OR handoff'
AND source_type IN ('checkpoint_next_steps', 'checkpoint_work_done')
ORDER BY rank LIMIT 30;

-- 1d. Recent user requests (intent discovery)
SELECT s.id, s.summary, s.updated_at, substr(t.user_message, 1, 300) as ask
FROM sessions s JOIN turns t ON t.session_id = s.id AND t.turn_index = 0
WHERE s.updated_at >= date('now', '-30 days')
ORDER BY s.updated_at DESC LIMIT 30;

-- 1e. Session files touched (for context)
SELECT sf.session_id, sf.file_path, sf.tool_name, COUNT(*) as edits
FROM session_files sf
JOIN sessions s ON sf.session_id = s.id
WHERE s.updated_at >= date('now', '-30 days')
GROUP BY sf.session_id, sf.file_path
ORDER BY edits DESC LIMIT 50;

-- 1f. PRs, commits, issues referenced
SELECT sr.session_id, sr.ref_type, sr.ref_value, s.updated_at
FROM session_refs sr
JOIN sessions s ON sr.session_id = s.id
ORDER BY s.updated_at DESC LIMIT 50;
```

### Stage 2: EXTRACT CANDIDATES

Parse `next_steps` fields into individual task candidates.

**Extraction rules:**
- Lines starting with `- `, `* `, `[ ] `, `- [ ] ` → task items
- Lines starting with `1. `, `2. ` etc. → task items
- Bold text sections (e.g., `**PR #2090691...**`) → task item
- Section headers (e.g., `**Immediate:**`) → task group label (not a task)
- Ignore lines that are pure context/explanation (no action verb)

**Action verb indicators** (line contains at least one):
`fix, implement, create, update, add, remove, investigate, check, verify,
monitor, deploy, merge, review, test, write, build, run, push, commit,
configure, migrate, enable, disable, rollout, trigger, file, address,
complete, resolve, validate, upgrade, apply, submit, track, plan`

**For each candidate, extract:**
```json
{
  "raw_text": "<original line>",
  "normalized_title": "<cleaned, lowercase, no PR numbers>",
  "entities": {
    "pr_ids": [2099042, 2099480],
    "pipeline_ids": [54583, 55818],
    "branches": ["user/feature-branch-name"],
    "services": ["web-api", "data-pipeline"],
    "repos": ["backend-api"],
    "regions": ["us-east-1", "eu-west-1"],
    "people": ["Alice"]
  },
  "source": {
    "session_id": "...",
    "checkpoint_number": 5,
    "field": "next_steps",
    "session_date": "2026-05-11"
  }
}
```

### Stage 3: NORMALIZE & GENERATE IDs

For each candidate:
1. Normalize title: lowercase, remove dates, remove PR/build numbers, strip whitespace
2. Generate stable ID: `sha256(normalized_title + project)[:12]`
3. Extract project/theme from context clues

**Project detection keywords:**
| Keywords in text | Project | Scope |
|-----------------|---------|-------|
| java 17, j17, java17_upgrade, --add-opens, JVM | `java-17-migration` | work |
| vulnerability, vuln, CVE, security, remediation | `vulnerability-remediation` | work |
| release, deploy, rollout, pipeline | `release-management` | work |
| CI/CD, build, pipeline, official build | `build-pipeline-health` | work |
| PR #XXXX, review, merge, approval | `pr-management` | work |
| orchestration, agency, trigger-agent, state dir | `agency-platform` | work |
| docs, documentation, wiki, runbook | `documentation` | work |
| dashboard, UI, web, frontend | `tooling` | work |
| ingestion, ETL, data processing, streaming | `data-services` | work |
| helm, k8s, kubectl, deployment, infra | `infrastructure` | work |
| side project A, hobby app, personal tool | `personal-project-a` | personal |
| side project B, mobile app, weekend hack | `personal-project-b` | personal |
| personal GitHub, side project | `personal-misc` | personal |

**Scope filtering (MANDATORY):**
- When agent context = `personal-agent` → show ONLY `personal` scope tasks
- When agent context = anything else (work agents) → show ONLY `work` scope tasks
- Detection: check session system prompt for "personal" keyword, or check `cwd` for personal repos path

### Stage 4: DEDUPLICATE

Multi-signal deduplication (NOT just word overlap):

**Signals (weighted):**
| Signal | Weight | Match Rule |
|--------|--------|------------|
| Same PR ID mentioned | 0.4 | Exact match on any PR number |
| Same pipeline ID | 0.3 | Exact match |
| Same branch name | 0.5 | Exact match |
| Same project + similar title (>60% word overlap) | 0.4 | Fuzzy |
| Same service + same action verb | 0.2 | Exact |
| Same session origin | 0.1 | Only boosts existing similarity |

**Dedup confidence thresholds:**
- Score ≥ 0.7 → **merge** (same task, combine sources)
- Score 0.4–0.69 → **link** (related but distinct, cross-reference)
- Score < 0.4 → **separate** (independent tasks)

**When merging:**
- Keep the most recent and most detailed description
- Combine all source references
- Union all entities
- Keep the highest priority score

### Stage 5: INFER STATUS

Conservative status model — never over-claim completion:

| Status | Criteria | Confidence |
|--------|----------|------------|
| `confirmed_done` | Appears in `work_done` of a LATER checkpoint with high similarity, OR referenced PR is merged/completed, OR explicit "✅ Done" | HIGH |
| `possibly_done` | Disappeared from `next_steps` in a later checkpoint of same session, but no `work_done` evidence | LOW |
| `blocked` | Contains "blocked", "waiting on", "needs approval", "depends on" | MEDIUM |
| `open` | Still in latest `next_steps` of its source session, or no contrary evidence | HIGH |
| `stale` | Not mentioned in any session for 30+ days AND no blocking indicator | MEDIUM |

**Staleness bands** (do NOT downrank security/release tasks by age alone):
- `fresh`: seen within 7 days
- `aging`: 8–30 days
- `stale`: 31–90 days
- `archival`: 90+ days

**Protected categories** (never auto-mark as stale):
- Security/vulnerability tasks
- Release/deployment tasks
- Tasks with explicit "blocked" status
- Tasks referencing open PRs

### Stage 6: CLUSTER INTO PROJECTS

Group tasks by their detected project (from Stage 3). Each project gets:
- Project name
- Task count (open/blocked/done)
- Last activity date
- Overall health indicator

### Stage 7: SCORE PRIORITY

Each task gets a priority score (0–100) with explainable breakdown:

| Factor | Max Points | Calculation |
|--------|-----------|-------------|
| Recency | 25 | 25 × (1 - days_since_last_seen / 30), min 0 |
| Frequency | 20 | 20 × min(session_count / 5, 1) |
| Blocking status | 20 | 20 if task is blocking other work; 15 if blocked itself |
| Explicit urgency | 15 | 15 if marked "immediate", 10 if "high priority", 5 if "lower priority" |
| Entity density | 10 | 10 × min(entity_count / 5, 1) — more specific = more actionable |
| User asked recently | 10 | 10 if user asked about this in last 3 sessions |

**Show breakdown** in output:
```
Priority: 84/100
  Recency: +22 (seen 2 days ago)
  Frequency: +16 (in 4 sessions)
  Blocking: +20 (blocks J17 rollout)
  Urgency: +15 (marked "immediate")
  Specificity: +8 (PR, branch, region named)
  User interest: +3
```

### Stage 8: LOAD PREVIOUS STATE

Before rendering, load `~/.copilot/knowledge/backlog.json` if it exists.

Compare current results against previous state to detect:
- **New tasks**: in current but not in previous
- **Completed tasks**: in previous but now confirmed_done
- **Status changes**: task moved from open→blocked, etc.
- **Stale tasks**: newly stale since last run
- **Priority shifts**: significant priority change (>15 points)

### Stage 9: RENDER OUTPUT

#### backlog.json schema:
```json
{
  "generated_at": "2026-05-14T10:30:00Z",
  "stats": {
    "total_tasks": 25,
    "open": 15,
    "blocked": 4,
    "possibly_done": 3,
    "confirmed_done": 2,
    "stale": 1,
    "projects": 6
  },
  "projects": [
    {
      "id": "java-17-migration",
      "name": "Java 17 Migration",
      "task_count": 5,
      "open_count": 3,
      "last_activity": "2026-05-13",
      "health": "active"
    }
  ],
  "tasks": [
    {
      "id": "a1b2c3d4e5f6",
      "title": "Commit 11 Helm template changes (--add-opens flags)",
      "project": "java-17-migration",
      "status": "open",
      "status_confidence": "HIGH",
      "priority": 84,
      "priority_breakdown": {
        "recency": 22,
        "frequency": 16,
        "blocking": 20,
        "urgency": 15,
        "specificity": 8,
        "user_interest": 3
      },
      "staleness": "fresh",
      "entities": {
        "services": ["web-api", "data-pipeline"],
        "repos": ["backend-api"]
      },
      "sources": [
        {
          "session_id": "5bcf7332-...",
          "checkpoint_number": 45,
          "field": "next_steps",
          "session_date": "2026-05-07",
          "snippet": "Commit the 11 Helm template changes..."
        }
      ],
      "dependencies": [],
      "related_tasks": ["b2c3d4e5f6g7"],
      "created_at": "2026-05-07",
      "last_seen_at": "2026-05-13"
    }
  ],
  "changes_since_last_run": {
    "new_tasks": ["id1", "id2"],
    "completed": ["id3"],
    "status_changes": [{"id": "id4", "from": "open", "to": "blocked"}],
    "newly_stale": ["id5"],
    "priority_shifts": [{"id": "id6", "from": 45, "to": 72}]
  },
  "user_annotations": {}
}
```

#### backlog.md format:
```markdown
# 📋 Cross-Session Backlog
> Generated: 2026-05-14 10:30 UTC | Tasks: 25 (15 open, 4 blocked, 3 possibly done)
> Changes since last run: 2 new, 1 completed, 1 newly stale

## 🔄 Changes Since Last Run
- ✅ **Completed**: [task title] (was in PR-management)
- 🆕 **New**: [task title] (found in session from today)
- ⏳ **Newly stale**: [task title] (not seen in 32 days)

---

## 🔴 Java 17 Migration (3 open, 1 blocked)
_Last activity: 2026-05-13 | Health: active_

| # | Task | Status | Priority | Last Seen | Source |
|---|------|--------|----------|-----------|--------|
| 1 | Commit 11 Helm template changes | 🟢 open | 84 | May 13 | 2 sessions |
| 2 | Apply --add-opens to operation-job | 🟢 open | 72 | May 7 | 1 session |
| 3 | Investigate FD leak (J17 higher OpenFdCount) | 🟡 blocked | 68 | May 7 | 1 session |

<details><summary>Priority breakdown for #1</summary>
Recency: +22, Frequency: +16, Blocking: +20, Urgency: +15, Specificity: +8, Interest: +3
</details>

---

## 🟡 Vulnerability Remediation (4 open)
...

## ⚪ Stale Tasks (>30 days)
| Task | Last Seen | Project | Action |
|------|-----------|---------|--------|
| ... | Apr 10 | ... | Archive? Revisit? |
```

### Stage 10: GENERATE RESUME PROMPTS

For each project (not each individual task), generate a **▶ Resume Prompt** block that can be
copy-pasted into a new session to instantly restore all context.

**Resume prompt template:**
```markdown
<details><summary>▶ Resume Prompt — [Project Name]</summary>

\```
Read ~/.copilot/knowledge/backlog.md and [relevant knowledge files] first.

## Resume: [Project Name] — [One-line goal]

### Context from prior sessions:
- [Key fact 1 with specific IDs, branches, PR numbers]
- [Key fact 2 — what was tried, what succeeded, what failed]
- [Key fact 3 — current state of artifacts, builds, deployments]
- Prior sessions: [session_id_1, session_id_2]

### Files previously touched:
- [file_path_1] (what was changed)
- [file_path_2]

### Tasks (ordered by dependency):
1. [First thing to check/verify — always start with state verification]
2. [Next action]
3. [Final action]
\```

</details>
```

**Resume prompt rules:**
1. **Always start with knowledge file reads** — `backlog.md` + project-specific files
2. **Include specific IDs** — PR numbers, pipeline IDs, build numbers, branch names, commit SHAs
3. **Include what was tried and failed** — prevents repeating past mistakes
4. **Include file paths** — from `session_files` table for that session
5. **Include prior session IDs** — so the agent can query session_store for deeper context
6. **First task should always be state verification** — check current git/PR/build status before acting
7. **Keep it copy-paste ready** — no placeholders, no "fill in X"
8. **One prompt per project** — covers all tasks in that project group

**Data sources for resume prompts:**
- `session_store.checkpoints.work_done` — what was accomplished (don't redo)
- `session_store.checkpoints.next_steps` — what was planned (do this)
- `session_store.session_files` — files touched (context for the agent)
- `session_store.sessions.summary` — session intent
- `backlog.json` task entities — PR IDs, branches, pipelines

### Stage 11: PERSIST STATE

1. Write `~/.copilot/knowledge/backlog.json` (machine state)
2. Write `~/.copilot/knowledge/backlog.md` (human view)
3. Report changes to user

**User annotation support**: Users can add HTML comments in `backlog.md`:
```html
<!-- planner:ignore -->         → Skip this task in future runs
<!-- planner:status=done -->    → Override status to confirmed_done
<!-- planner:project=XYZ -->    → Override project assignment
<!-- planner:priority=95 -->    → Override priority score
```

When loading previous state, parse these annotations and preserve them.

---

## 🧠 SMART PLANNING MODE

When the user asks "plan my work" or "what should I do next", go beyond listing tasks:

### Daily Plan Generation
1. Filter to `open` + `fresh` tasks with priority > 50
2. Estimate session count (each session ≈ 1-3 tasks)
3. Order by: blocked tasks first (unblock others), then by priority
4. Group into suggested session themes:
   ```
   Suggested work plan:
   
   Session 1 (focus: Java 17 Migration):
     → Commit Helm template changes (priority 84)
     → Apply --add-opens to operation-job (priority 72)
   
   Session 2 (focus: Pipeline Health):
     → Investigate AB Deploy NonProd failures (priority 78)
     → Check AB Post-Deploy Validation (priority 65)
   
   Session 3 (focus: Vulnerability):
     → File security exceptions for Jetty/keycloak/log4j (priority 71)
   ```

### Dependency-Aware Ordering
- If task A blocks task B → A must come first
- If tasks share the same branch/PR → group together
- If tasks are in the same repo → suggest same session

### Optimization Suggestions
- "Tasks X and Y both touch PR #2099042 → handle in one session"
- "Task Z has been open 25 days with no progress → deprioritize or archive?"
- "3 tasks are blocked on Tanmay's approval → escalate or find alternative reviewer?"

---

## ⚠️ RULES

1. **Never invent tasks** — every task must trace to a `session_store` query result
2. **Never auto-mark as done without strong evidence** — use `possibly_done` when uncertain
3. **Always show source provenance** — session ID, checkpoint, date
4. **Ask before persisting** — show preview, then ask "Should I save this backlog?"
5. **Preserve user annotations** — never overwrite `<!-- planner:... -->` directives
6. **Explain priority scores** — always show breakdown, never just a number
7. **Show confidence levels** — for status inference, dedup decisions, dependency claims
8. **Diff against previous run** — always highlight what changed
9. **Protected categories never go stale** — security, release, blocked tasks
10. **Scope isolation (CRITICAL)** — Personal/side-project tasks MUST ONLY appear when invoked from the **personal-agent** context. All other agents (work agents) MUST exclude personal tasks from their backlog view. Detection: filter out tasks whose `source.session_summary` or `entities.repos` match personal project keywords. Conversely, when running inside the personal agent, EXCLUDE all work tasks from the backlog.

---

## 🔗 SKILL ROUTING

| Situation | Route To |
|-----------|----------|
| Task involves code changes | `architect-first` for planning |
| Task involves queries/data | Read relevant knowledge docs first |
| Task involves PR review | `code-reviewer` skill |
| Task involves testing | `test-writer` skill |
| Task involves deployment | Your deployment skill/agent |
| Task involves vulnerability | Your security skill/agent |
| Task involves documentation | Your docs skill/agent |

---

## 📊 METRICS (self-monitoring)

Track across runs (append to backlog.json):
```json
"run_history": [
  {
    "date": "2026-05-14",
    "total": 25,
    "new": 2,
    "completed": 1,
    "velocity": 1.5
  }
]
```

Velocity = tasks completed per week (rolling 4-week average).
If velocity drops to 0 for 2+ weeks → flag: "No tasks completing. Review backlog for blockers or stale items."
