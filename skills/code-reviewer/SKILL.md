---
name: code-reviewer
description: >
  High-signal code review skill that focuses only on meaningful correctness, security,
  reliability, and data-loss issues. Activates on keywords like: review, code review,
  PR review, pull request, diff, changes.
---

# Code Review Skill

> **Only surface issues that materially matter. No style noise. No preference debates.
> No filler comments.**

This skill makes AI code reviews reliable by focusing on real defects, grounding each finding
in concrete evidence, and producing a clear merge recommendation.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks for a code review or PR review
- User asks "does this diff look right?"
- User asks to inspect changes, patch, or pull request risk
- User wants review comments or an approval recommendation

---

## 🚫 ANTI-NOISE RULES

### ONLY flag findings that genuinely matter
Allowed categories:
- Bugs and logic errors
- Security issues
- Data corruption or data loss risk
- Crash / exception paths
- Reliability or concurrency hazards
- Backward compatibility breakage
- Broken tests or invalid assumptions

### NEVER comment on:
- Style or formatting preferences
- Naming preferences that are still clear
- Minor refactors with no functional impact
- Comments / whitespace / import ordering
- "Could be cleaner" suggestions without real risk

**Rule**: If the code is merely non-ideal but not risky, suppress the comment.

---

## 🔍 REVIEW WORKFLOW

### Step 1: Understand context
- What problem does the PR solve?
- Which files and behaviors changed?
- What is the intended user or system impact?

### Step 2: Identify the risk surface
Ask:
- What data paths changed?
- What assumptions changed?
- What external interfaces changed?
- What failures would hurt most in production?

### Step 3: Inspect each change against risk
Review changed code for:
- incorrect conditions or state transitions
- missing null / empty handling
- mismatched read-write paths
- bad retries, timeouts, or transaction boundaries
- missing auth / validation / escaping
- races or non-atomic updates

### Step 4: Write only evidence-backed findings
For every finding include:
- exact file and line
- why the code is wrong or risky
- concrete production scenario
- specific fix direction

### Step 5: Produce verdict
Choose one:
- **APPROVE** — no meaningful issues found
- **REQUEST_CHANGES** — at least one important issue must be fixed
- **COMMENT** — minor but non-blocking tradeoff discussion

---

## 📏 SEVERITY MODEL

| Severity | Meaning | Use When |
|----------|---------|----------|
| **Critical** | Breaks production or creates severe security/data-loss risk | Certain high-impact defect |
| **Warning** | Likely defect or meaningful reliability issue | Important but not catastrophic |
| **Note** | Non-blocking suggestion with tradeoff | Useful discussion, not a blocker |

**Rule**: Use `Note` sparingly. If it does not change risk or maintainability materially, omit it.

---

## 🧾 EVIDENCE REQUIREMENT

Each finding MUST have:
1. **Specific location** — `path/to/file.ext:line`
2. **Observed behavior** — what the changed code does
3. **Failure scenario** — when it breaks in reality
4. **Impact** — what users, data, or systems experience
5. **Fix** — actionable correction, not vague advice

Bad review comment:
- "This seems wrong."

Good review comment:
- "`foo.ts:42` writes to the cache before the DB transaction commits. If the transaction fails,
  readers can observe data that never persisted, causing stale or phantom reads. Move cache
  publication after commit or invalidate on rollback."

---

## 🧠 REVIEW HEURISTICS

### High-priority checks
- State updates split across multiple systems
- Changed validation or auth logic
- New parsing / serialization code
- Added async or parallel behavior
- Retry / timeout / backoff changes
- Schema, API, or event contract changes
- Deletes, overwrites, migrations, or cleanup jobs

### Questions to ask per diff
- Can this silently lose data?
- Can it create duplicate or partial work?
- Can it expose something unauthorized?
- Can it regress existing callers?
- Can it fail only under concurrency or retries?

---

## 🧱 OUTPUT TEMPLATE

```markdown
## Code Review: <PR title>

### Summary
<1-2 sentences on what this PR does>

### Risk Assessment
<What could go wrong with these changes?>

### Findings
#### 🔴 Critical: <title>
**File**: `path/to/file.java:42`
**Issue**: <description>
**Impact**: <what breaks in production>
**Fix**: <specific suggestion>

#### 🟡 Warning: <title>
**File**: `path/to/file.java:57`
**Issue**: <description>
**Impact**: <meaningful consequence>
**Fix**: <specific suggestion>

#### 🔵 Note: <title>
**File**: `path/to/file.java:80`
**Issue**: <tradeoff or improvement>
**Impact**: <why it may matter>
**Fix**: <optional suggestion>

### Verdict
<APPROVE / REQUEST_CHANGES / COMMENT>
<brief reasoning>
```

---

## ✅ DECISION RULES

- If there are **no evidence-backed meaningful issues**, approve
- If a finding needs speculation to sound important, suppress it
- If two findings describe the same underlying defect, merge them
- Prefer fewer, stronger comments over many weak ones
- Summarize the change intent before giving findings
- Every blocking comment must explain both **why** and **how to fix**
