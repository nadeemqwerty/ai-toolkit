---
name: architect-first
description: >
  Orchestration skill that enforces requirement clarification, architecture-first design,
  and POC validation BEFORE implementation. Prevents coding without clear understanding.
  Activates on keywords like: implement, build, create feature, design, architecture,
  new service, refactor, migrate, "how should we", POC, prototype, spike.
---

# Architect-First Workflow Skill

> **NEVER implement without understanding. NEVER design without requirements. NEVER ship without validation.**

This skill enforces a phased workflow that prevents the #1 AI failure mode: coding before thinking.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks to implement something non-trivial (>1 file, >50 lines, new feature)
- User asks "how should we..." or "design..." or "architect..."
- Task involves cross-service changes
- Task involves unfamiliar code areas
- User says "build", "create", "implement", "refactor", "migrate"

**DO NOT activate for:**
- Simple bug fixes with clear reproduction
- Config changes (version bumps, value updates)
- Documentation-only changes
- Single-line fixes where problem and solution are obvious

---

## 📋 MANDATORY PHASES

### Phase 0: RISK DECOMPOSITION

Before anything else, identify the riskiest piece:

| Risk Factor | Score 1-5 | Example |
|-------------|-----------|---------|
| Technical unknowns | 5 = never done before | New integration pattern |
| Blast radius | 5 = multi-service | Shared interface change |
| Reversibility | 5 = irreversible | Database schema migration |
| Dependencies | 5 = external team needed | Cross-team API contract |
| Data sensitivity | 5 = production data | Auth/billing changes |

**Rule**: If any factor scores 4-5, that becomes Phase 3 (POC) focus.

---

### Phase 1: REQUIREMENTS (The "Researcher" Role)

**Goal**: Understand WHAT before HOW.

1. **Parse the request** — what is the user actually asking for?
2. **Ask clarifying questions**:
   - Scope: What's in? What's explicitly out?
   - Constraints: Performance? Compatibility? Feature flags?
   - Dependencies: Other teams? Other PRs? Timeline?
   - Success criteria: How do we know it's done?
3. **Gather evidence**:
   - Current code: search for existing implementations
   - Prior decisions: check for documented choices
   - Team patterns: find similar implementations in the codebase
4. **Output**: Clear problem statement + constraints list

**Anti-patterns to block:**
- ❌ "I'll just start coding and figure it out"
- ❌ Assumptions about requirements without asking
- ❌ Starting with "I think the user wants..."

---

### Phase 2: ARCHITECTURE (The "Architect" Role)

**Goal**: Design the solution. Identify risks. Get agreement.

1. **Propose approach** — what changes, where, how
2. **Identify risks** — what could break, blast radius, reversibility
3. **Consider alternatives** — present 2+ approaches:

| Aspect | Minimal | Clean Architecture | Pragmatic |
|--------|---------|-------------------|-----------|
| Files changed | Few | Many | Moderate |
| Blast radius | Small | Large | Medium |
| Reversibility | Easy | Hard | Easy |
| Test effort | Low | High | Medium |
| When to use | Patches | New features | Default |

4. **Get user agreement** before proceeding
5. **Document decision** if significant

---

### Phase 3: POC / VALIDATION (The "Senior Developer" Role)

**When POC is required** (ANY of these):
- Change touches >1 repository
- Introduces new dependency
- Adds new network call path
- Modifies shared interface used by >2 consumers
- User explicitly asks for POC

**POC approach:**
1. Implement smallest slice that proves the approach works
2. Validate — build succeeds, test passes, expected output produced
3. Ask user — "POC validates. Ready for full implementation?"

**When POC can be skipped:**
- Well-understood patterns (like existing ones in codebase)
- User explicitly says "skip POC"
- Change is purely mechanical

---

### Phase 4: IMPLEMENTATION (The "Developer" Role)

1. **Break into atomic commits** — each compiles independently
2. **Follow team standards** — match existing code style
3. **Add meaningful comments** — WHY, not WHAT:
   ```java
   // ✅ GOOD: Retry with backoff because API returns 429 under burst writes
   retryWithBackoff(request, MAX_RETRIES);

   // ❌ BAD: retry the request
   retryWithBackoff(request, MAX_RETRIES);
   ```
4. **Verify at each step** — build passes, tests pass
5. **Track progress** — update task tracking as you go

---

### Phase 5: DOCUMENTATION

- PR description with context (what, why, how, testing)
- Code comments for non-obvious logic
- Update runbooks if operational behavior changes
- Link work items

---

## 🔀 PHASE GATES

```
Requirements → Architecture → [POC if needed] → Implementation → Documentation
     ↑              ↑                                    ↑
  MUST ask       MUST get                            MUST verify
  clarifying     user OK                             build passes
  questions      before coding                       before done
```

### Two-Gate Approval Flow

Only TWO mandatory user approval points:

```
🟡 GATE:PLAN (after Phase 2)
   → User sees: approach, risks, files to change, alternatives
   → User decides: "proceed" / "adjust" / "abort"
   ↓
🤖 AUTONOMOUS EXECUTION (Phase 3-4-5 without interruption)
   ↓
🟢 GATE:SHIP (after Phase 5)
   → User sees: complete result, test output, build status
   → User decides: "ship" / "rework" / "abort"
```

**Between gates**: Agent runs autonomously.
**At gates**: Full stop. Present evidence. Wait for decision.
**Exception**: If build fails 3x during execution → escalate immediately.

---

## 🎯 GOAL-DRIVEN EXECUTION

Transform every task into verifiable goals:

| Instead of... | Transform to... |
|--------------|-----------------|
| "Add validation" | "Write test for invalid input → make it pass" |
| "Fix the bug" | "Write test reproducing bug → make it pass" |
| "Refactor X" | "Tests pass before AND after → no behavior change" |
| "Add feature Y" | "Define 3 acceptance tests → implement until green" |

### Execution Loop (Phase 3+)
```
1. Define success criteria (concrete, verifiable)
2. Write/identify verification commands
3. Run verification → expect FAIL (proves criteria is meaningful)
4. Implement minimal code
5. Run verification → expect PASS
6. If FAIL → iterate (max 3 times, then reassess approach)
```

---

## 🧹 SURGICAL CHANGES PRINCIPLE

1. **Touch only what you must** — every changed line traces to the requirement
2. **Don't "improve" adjacent code** — unrelated fixes go in separate PRs
3. **Match existing style** — even if you'd do it differently
4. **Clean up only YOUR mess** — orphans from your changes, not pre-existing

**Verification**: `git diff --stat` — if unexpected files changed, justify or revert.

---

## 🧠 SELF-CORRECTION MEMORY

When the user corrects you:
1. Acknowledge immediately
2. Ask: "Should I save this as a rule for future sessions?"
3. If yes → append to knowledge base:
   ```
   ### Rule: [Title]
   - Trigger: When doing [context]
   - Wrong: [what you did]
   - Correct: [what to do instead]
   - Source: User correction on [date]
   ```

---

## 📊 PARALLELIZATION

- **Phase 1**: Multiple explore agents gathering context from different areas
- **Phase 2**: 2-3 architecture agents proposing different approaches in parallel
- **Phase 4**: Build verification runs in background while writing next change
- **Phase 5**: PR creation + work item update in parallel
