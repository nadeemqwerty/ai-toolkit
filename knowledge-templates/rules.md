# Operational Rules — Anti-Hallucination & Evidence-First

> **Purpose**: Ground every agent action in evidence. Prevent hallucination. Learn from mistakes.
> **Read priority**: Sections 1-3 are ALWAYS relevant. Section 4+ is reference.

---

## §0 — CORE PRINCIPLES (ALWAYS ACTIVE)

### Rule 0.1: Think Before Coding
- State assumptions explicitly before implementing
- If ambiguous → ask, don't guess
- Present tradeoffs when multiple approaches exist
- Stop when confused — name what's unclear

### Rule 0.2: Simplicity First
- Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked
- No abstractions for single-use code
- If 200 lines could be 50 → rewrite

### Rule 0.3: Surgical Changes
- Touch only what you must — every changed line traces to the requirement
- Don't "improve" adjacent code unprompted
- Match existing style even if you'd do differently
- Remove only orphans YOUR changes created

### Rule 0.4: Goal-Driven Execution
- Transform tasks into verifiable success criteria
- Write verification FIRST, confirm it fails, then implement
- Loop until verified (max 3 iterations, then reassess)
- "Done" = verification passes, not "I wrote the code"

---

## §1 — ANTI-HALLUCINATION PROTOCOL (ALWAYS ACTIVE)

### Evidence-Based Response Protocol

**Every factual claim MUST include:**
1. **Evidence** — the tool output that proves it
2. **Source step** — the exact command that produced the evidence
3. **Reproducibility** — user can re-run and get same result

### Verification Gates (apply to EVERY claim)
| Gate | Action if Fails |
|------|-----------------|
| File exists | STOP — do not cite non-existent files |
| Symbol exists | STOP — retract claim |
| Query returns data | STOP — don't assume patterns |
| Counter-evidence checked | Investigate before concluding |

### NEVER-Do List
1. Never cite a file without verifying it exists
2. Never write queries without checking schema first
3. Never assume table/column names
4. Never claim code flow without runtime evidence
5. Never fabricate identifiers
6. Never deliver findings without the evidence-producing step
7. Never state root cause without counter-checking alternatives

---

## §2 — SKILL ROUTING (Match keywords to specialists)

When a request matches skill keywords, route to the skill FIRST:
- Don't attempt manual work that a skill handles
- Skills have validated patterns and prevent common mistakes
- When in doubt, check if a skill exists before improvising

---

## §3 — KUSTO / QUERY RULES (if using telemetry)

Customize this section for YOUR telemetry system:

- Always discover schema before querying (`.show table X | getschema` equivalent)
- Always use explicit time filters (never query unbounded)
- Start narrow, widen if empty (don't start with `take 1000000`)
- Cross-correlate IDs carefully (understand join semantics)

---

## §4 — LESSONS LEARNED

<!-- Append new rules below this line as you learn them -->

### Template for New Rules:
```
### [YYYY-MM-DD] Rule: [Short title]
- **Context**: When doing [X]
- **Wrong approach**: [What failed]
- **Correct approach**: [What works]
- **Why**: [Root cause of the failure]
```
