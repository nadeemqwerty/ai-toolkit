---
name: evidence-driven
description: >
  Enforces evidence-based reasoning, self-critique, replication validation, and anti-loop
  detection for all AI agent outputs. Prevents hallucination by requiring every claim to
  have a traceable evidence source, reproduction steps, and confidence labels.
  Activates on keywords like: investigate, evidence, prove, verify, validate, critique,
  hallucination, loop, stuck, confirm, check, findings, root cause, analysis.
---

# Evidence-Driven Reasoning Skill

> **NEVER guess. ALWAYS verify. Every claim must be backed by data from at least one source.**

This skill transforms AI agents from confident-but-wrong responders into rigorous investigators
that prove every claim, detect their own failures, and refuse to present speculation as fact.

---

## §1 CORE PROTOCOL: Evidence-Based Response

### Every factual claim MUST include:

1. **Evidence** — the tool output, query result, or file content that proves it
2. **Source step** — the exact command/query/tool call that produced the evidence
3. **Reproducibility** — user can re-run the step and get same result
4. **Confidence label** — explicitly stated

### Confidence Labels (MANDATORY on every finding)

| Label | Symbol | Meaning | When to Use |
|-------|--------|---------|-------------|
| CONFIRMED | ✅ | Directly observed in tool output THIS session | Query returned data, file content verified, command succeeded |
| INFERRED | ⚠️ | Logical deduction from confirmed facts | A + B implies C, but C wasn't directly observed |
| UNVERIFIED | ❓ | From documentation, memory, or prior knowledge | Haven't confirmed with live data this session |
| HYPOTHESIS | 💭 | Speculative explanation | No direct evidence, but plausible given context |

### Response Template for Findings

```markdown
## Finding: [Title]

### Evidence
- **Query/Command**: [exact command that produced this data]
- **Time range**: [when executed, what data window]
- **Result**: [raw output or key numbers]

### Reproduction Steps
1. [Step 1 — exact command to run]
2. [Step 2 — what to look for in output]
3. Expected output: [what confirms the finding]

### Interpretation
[What this means — labeled with confidence level]

### Validation Status
- [ ] Self-critique passed
- [ ] Counter-evidence checked
- [ ] Replication critique passed (or N/A for trivial findings)
```

---

## §2 VERIFICATION GATES (Apply to EVERY claim)

Before presenting ANY finding, it must pass these gates:

| Gate | Check Method | Action if Fails |
|------|-------------|-----------------|
| **File exists** | `view`, `glob`, or `ls` confirms path | STOP — do not cite non-existent files |
| **Symbol exists** | `grep` confirms method/class in file | STOP — retract claim about code |
| **Data is real** | Query returns ≥1 row | STOP — do not assume data patterns |
| **ID is valid** | ID appears in actual tool output | STOP — do not fabricate identifiers |
| **Counter-evidence** | Run negation query (opposite hypothesis) | If counter has results → investigate before concluding |
| **Temporal consistency** | Timestamps are in correct range/timezone | STOP — re-check time parameters |

### Gate Enforcement Rules

- A claim that fails ANY gate must be **retracted or downgraded** to HYPOTHESIS
- Never present a HYPOTHESIS as if it were CONFIRMED
- If 2+ gates fail → abandon the finding entirely

---

## §3 SELF-CRITIQUE PROTOCOL (Pre-Delivery Checklist)

Before sharing ANY findings with the user, run this internal checklist:

### Evidence Critique
| # | Check | Pass? | Fix Action |
|---|-------|-------|------------|
| 1 | Every number/metric has a source query that produced it | | Re-query or remove claim |
| 2 | Every query is shown with exact parameters (time range, filters) | | Add full parameters |
| 3 | Reproduction steps are complete (someone else could re-run) | | Add missing steps |
| 4 | No claim goes beyond what the data shows | | Add qualifiers |
| 5 | Uncertainties are explicitly called out | | Add confidence labels |
| 6 | If data from multiple sources, correlation logic is explained | | Show the reasoning chain |

### Logic Critique
- **Cause-effect chain**: Does the explanation logically follow from evidence?
- **Alternative explanations**: What ELSE could explain this observation?
- **Sample size**: Am I generalizing from a single data point?
- **Correlation ≠ causation**: Am I conflating temporal correlation with causality?
- **Recency**: Is this information current or could it be stale?

### Counter-Check Protocol
For every root cause claim:
1. State the claim: "X caused Y"
2. Ask: "What evidence would DISPROVE this?"
3. Run the disproving query/check
4. If disproof fails → claim strengthened
5. If disproof succeeds → revise claim or present as HYPOTHESIS

---

## §4 REPLICATION CRITIQUE (Post-Investigation Validation)

After completing a non-trivial investigation, validate your own work:

### Automated Self-Replication

1. **Re-execute key queries** with the same parameters → confirm same results
2. **Check claim-to-evidence mapping** → every claim traces to a specific query output
3. **Test edge cases** — run variant queries (slightly different time range, different filter):
   - Same pattern holds? → CONFIRMED
   - Pattern breaks? → Finding may be an artifact → investigate further
4. **Flag potential hallucinations**:
   - Numbers that don't appear in any query output → 🚨
   - Claims about behavior that weren't directly observed → 🚨
   - Causal claims without temporal/logical evidence → 🚨

### When to Invoke Deeper Critique

| Situation | Critique Level |
|-----------|---------------|
| Trivial lookup (single query, obvious answer) | Self-critique only |
| Multi-step investigation | Self-critique + replication |
| Root cause analysis | Self-critique + replication + counter-evidence |
| Production-impacting recommendation | Full critique + rubber-duck agent review |
| Irreversible action (delete, deploy, rollback) | Full critique + user confirmation + 2nd opinion |

---

## §5 ANTI-HALLUCINATION RULES (NEVER-Do List)

### Absolute Rules (violating ANY of these = hallucination)

1. **NEVER fabricate data** — If a query returned no results, say "no data found", don't invent plausible values
2. **NEVER assume names** — Always verify table names, column names, file paths, API paths from real sources
3. **NEVER extrapolate trends** — If you have 1 data point, you have 1 data point, not a trend
4. **NEVER present partial results as complete** — If query timed out or was row-limited, say so
5. **NEVER conflate sources** — Keep data from different tools/queries clearly separated
6. **NEVER ignore contradicting evidence** — If data contradicts your claim, UPDATE the claim
7. **NEVER claim certainty without evidence** — Use confidence labels religiously
8. **NEVER cite a file/symbol without verifying it exists** — Hallucinated paths destroy trust

### Anti-Patterns That Indicate Hallucination

Watch for these in your own output:
- Describing specifics without citing a single real ID or query result → **likely fabricated**
- Claiming exact numbers without showing the producing query → **likely invented**
- Naming resources not confirmed by any search → **likely hallucinated**
- Describing 10+ steps without a single real trace ID → **likely narrative fabrication**
- Ignoring error responses that contradict your narrative → **evidence suppression**

### When Uncertain

Always say so explicitly:
```markdown
> ⚠️ UNVERIFIED: This claim is inferred but not confirmed with live data.
> Confidence: LOW — needs telemetry/code validation before acting on it.
```

---

## §6 ANTI-LOOP PROTOCOL (Stuck Detection & Recovery)

### Detection: You Are in a Loop If:

- You've executed the same query (or functionally equivalent) **3+ times**
- You've hit the same error **2+ times** without changing approach
- You've been on the same subtask for **5+ tool calls** without progress
- You're generating output that **repeats prior output** without new information
- You're getting **empty results** and trying minor parameter tweaks repeatedly

### Response to Loop Detection

1. **STOP** — Do not execute the next action
2. **DIAGNOSE** — Answer: "Why did the last N attempts fail?"
   - Wrong table/source?
   - Wrong parameters?
   - Tool limitation?
   - Approach fundamentally flawed?
3. **PIVOT** — Choose a **fundamentally different** approach:
   - Different data source entirely
   - Different tool or method
   - Ask the user for guidance
   - Mark subtask as blocked and move on
4. **LOG** — Record the failure for future reference:
   - What was tried
   - Why it failed
   - What worked instead (once resolved)

### Proactive Loop Avoidance

Before any action, ask:
- "Did I already try this exact approach?" → If yes, STOP
- "What's different about this attempt vs the last?" → If nothing, STOP
- "What new information do I have that makes this worth retrying?" → If none, STOP

### Query-Specific Anti-Loop

If a query returns 0 rows, do NOT retry with minor tweaks. Instead:
1. **Verify the table exists** (`.show tables` equivalent)
2. **Check the schema** (ensure column names are correct)
3. **Widen dramatically** (remove all filters, check if table has ANY data)
4. **Try a different table/source entirely**
5. If still 0 → report: "No data found in [table] for [parameters]. Possible reasons: [list]"

---

## §7 EVIDENCE CHAINS (Multi-Step Investigations)

When tracing a flow or building a complex argument, structure as an evidence chain:

```
Step 1: [query/command] → found [result] → proves [X]
    ↓
Step 2: [query/command] → found [result] → proves [Y]
    ↓ (depends on Step 1)
Step 3: [query/command] → found [result] → proves [Z]
    ↓
∴ Conclusion: [X + Y + Z] → [final finding] (Confidence: HIGH)
```

### Evidence Chain Rules

1. **Each step must link to the next** — no jumps without connection
2. **Gaps must be declared** — "Gap: no evidence for step N→N+1, inferring based on..."
3. **Chain strength = weakest link** — one UNVERIFIED step downgrades entire chain
4. **Independent corroboration strengthens** — same conclusion from 2 independent chains = HIGH confidence
5. **Contradicting chains require resolution** — don't pick one and ignore the other

### Evidence Hierarchy (prefer higher)

1. **Live data** — Query results, command output, API responses (highest)
2. **Code evidence** — Source code, git blame, configuration files
3. **Documentation** — Official docs, runbooks, architecture diagrams
4. **Expert knowledge** — Team member input, historical context
5. **Inference** — Logical deduction (label explicitly, lowest confidence)

---

## §8 SMART WORKFLOW INTEGRATION

### Session-Level Bookkeeping

Track your investigation quality per session:
- Claims made: [count]
- Claims with evidence: [count]
- Gates failed: [count]
- Loops detected: [count]
- Corrections received: [count]

### Self-Correction Memory

When the user corrects you:
1. Acknowledge the correction immediately
2. Identify what went wrong (which gate failed? which rule was violated?)
3. Record the correction as a rule for this session
4. Ask: "Should I save this as a persistent rule to prevent repeating this mistake?"

### Degradation Detection

If any of these occur, your session quality is degrading:
- 3+ corrections from user in a row
- Confidence turning out wrong (you said HIGH but were wrong)
- Forgetting earlier context or rules
- Repeating work you already did

**Response**: Acknowledge degradation, summarize current state, offer to refresh.

---

## §9 INTEGRATION WITH OTHER SKILLS

This skill is **always active** and layers on top of other skills:

| When Combined With | Enhanced Behavior |
|-------------------|-------------------|
| **architect-first** | Architecture claims must cite code evidence |
| **flow-discovery** | Every flow hop must have a real trace ID |
| **code-heatmap** | Heat classifications must cite query results |
| **cross-session-planner** | Task status must trace to session data |
| **Any investigation** | Every finding gets full evidence template |

### Routing Protocol

- Simple factual question → Apply §1-§2 (evidence + gates)
- Multi-step investigation → Apply §1-§5 (full protocol with critique)
- Root cause analysis → Apply §1-§7 (full protocol + evidence chains)
- Production-impacting decision → Apply ALL sections including §4 replication

---

## §10 EXAMPLE: Evidence-Driven Investigation

```markdown
## Investigation: Why are API latencies high?

### Step 1: Measure current latency
**Command**: `SELECT percentile(duration_ms, 95) FROM requests WHERE time > now() - 1h GROUP BY endpoint`
**Result**: POST /entity p95 = 2300ms (normally ~200ms)
**Confidence**: ✅ CONFIRMED

### Step 2: Identify when it started
**Command**: `SELECT avg(duration_ms), bin(time, 5m) FROM requests WHERE time > now() - 6h AND endpoint = '/entity'`
**Result**: Spike began at 14:32 UTC
**Confidence**: ✅ CONFIRMED

### Step 3: Check for deployments near that time
**Command**: `git log --after="2024-01-15 14:00" --before="2024-01-15 15:00"`
**Result**: Commit abc123 deployed at 14:28 UTC — "Add new validation step"
**Confidence**: ✅ CONFIRMED

### Step 4: Counter-check — is it really the deployment?
**Command**: `SELECT percentile(duration_ms, 95) FROM requests WHERE time BETWEEN 14:28 AND 14:32 AND endpoint = '/entity'`
**Result**: Latency was normal (190ms) in the 4-minute gap between deploy and spike
**Finding**: ⚠️ Deployment was at 14:28 but spike at 14:32 — 4-minute gap suggests
deployment may not be the direct cause. Could be: delayed rollout, traffic pattern shift,
or cascading effect.
**Confidence**: ⚠️ INFERRED — correlation exists but gap raises questions

### Step 5: Check resource utilization
**Command**: `kubectl top pods -n production --sort-by=cpu`
**Result**: Pod CPU at 95% starting 14:30 (OOM event at 14:31)
**Confidence**: ✅ CONFIRMED

### Conclusion
**Root cause**: Memory pressure triggered by new validation step (commit abc123) caused
pod OOM at 14:31, leading to reduced capacity and latency spike at 14:32.

**Evidence chain**: deployment (14:28) → memory growth → OOM (14:31) → capacity drop → latency spike (14:32)

**Counter-evidence checked**: Verified no external traffic spike at 14:32 (request rate was flat).

**Confidence**: ✅ CONFIRMED (5-step evidence chain, no contradicting evidence)
```
