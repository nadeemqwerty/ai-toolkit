---
name: memory-compaction
description: >
  Session memory compaction skill for compressing long conversations into durable,
  reusable knowledge and handoff context. Activates on keywords like: summarize
  session, compact memory, save context, checkpoint, handoff, session summary.
---

# Memory Compaction Skill

> **When context gets long, compress it into durable knowledge: discoveries, decisions,
> pending work, and reusable patterns.**

This skill helps an agent summarize a long session into a structured artifact that preserves
what matters across future sessions.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks to summarize or checkpoint the session
- User asks for a handoff
- Context window is large and key learnings risk being lost
- Work is paused and should be resumable later
- User asks to save context or durable knowledge

---

## 🎯 PURPOSE

Capture the minimum durable knowledge needed to resume effectively later:
- what was learned
- what decisions were made and why
- what remains unfinished
- what reusable patterns emerged
- which files changed and for what reason

---

## 🔄 WORKFLOW

### Step 1: Identify key discoveries
Capture facts learned during the session that were not known at the start.
Each discovery should include evidence or source context.

### Step 2: Identify decisions made
Record:
- the decision
- alternatives considered if relevant
- the rationale behind the chosen path

### Step 3: Identify pending work
List incomplete tasks with enough context to resume without replaying the whole session.

### Step 4: Identify patterns observed
Extract reusable insights such as:
- workflow patterns
- debugging strategies
- repo conventions
- API usage patterns

### Step 5: Write structured summary
Persist the summary in the appropriate knowledge or handoff file used by the environment.

---

## 🧠 WHAT TO PRESERVE

### Preserve aggressively
- newly discovered repo structure
- working commands or queries
- decisions with tradeoffs
- blockers and dependencies
- validated hypotheses
- resumed-task context

### Compress aggressively
- repetitive command output
- dead-end explorations once explained
- trivial formatting changes
- conversational filler

---

## 🧱 OUTPUT FORMAT

```markdown
## Session Summary: <date> — <topic>

### Key Discoveries
- <fact learned> (evidence: <where/how verified>)

### Decisions Made
- <decision>: <rationale>

### Pending Work
- [ ] <task> — <context needed to resume>

### Patterns Observed
- <pattern>: <when to apply>

### Files Changed
- `path/file`: <what and why>
```

---

## ✅ COMPACTION RULES

- Prefer durable facts over transient narrative
- Preserve rationale, not just outcomes
- Pending work must be actionable without replaying the session
- Include evidence source for discoveries whenever possible
- If a decision changed mid-session, record the final decision and why the earlier path was rejected
- Keep summaries short enough to reload quickly, but rich enough to resume confidently
