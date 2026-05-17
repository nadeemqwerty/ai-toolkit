# Creating Your Own Skills

## What is a Skill?

A skill is a Markdown file that instructs an AI agent HOW to handle a specific type of task.
It activates when the user's request matches certain keywords, and provides structured
workflows, rules, and templates that the agent follows.

---

## Skill File Structure

```markdown
---
name: my-skill-name
description: >
  One-paragraph description of what this skill does and when it activates.
  Include activation keywords at the end.
---

# Skill Title

> One-line mission statement

## WHEN TO ACTIVATE
[Trigger conditions]

## EXECUTION STEPS
[What to do, in order]

## OUTPUT FORMAT
[What the result should look like]

## RULES
[Constraints and boundaries]

## HALLUCINATION AVOIDANCE
[Domain-specific anti-hallucination rules]
```

---

## Anatomy of a Good Skill

### 1. Clear Activation Triggers

Tell the agent WHEN to use this skill:

```markdown
## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks about [topic A]
- User says "[keyword 1]", "[keyword 2]", "[keyword 3]"
- Task involves [specific type of work]

DO NOT activate for:
- [Things that look similar but aren't]
- [Edge cases to exclude]
```

### 2. Structured Workflow

Break the work into clear phases:

```markdown
## 📋 EXECUTION PHASES

### Phase 1: Gather Context
1. [Specific action]
2. [Specific action]
3. [Expected output from this phase]

### Phase 2: Analyze
1. [Specific action]
2. [Decision point: if X then Y, else Z]

### Phase 3: Deliver
1. [Format the output]
2. [Validate before presenting]
```

### 3. Output Templates

Show EXACTLY what good output looks like:

```markdown
## 📊 OUTPUT FORMAT

\```markdown
## [Title]

### Summary
[1-2 sentences]

### Evidence
- **Source**: [where this came from]
- **Data**: [what was observed]

### Recommendation
[What to do, with confidence level]
\```
```

### 4. Anti-Hallucination Rules

Every skill should have domain-specific guardrails:

```markdown
## 🚫 NEVER DO

1. Never [domain-specific hallucination risk]
2. Never [another common mistake]
3. Always [verification step] before claiming [X]

## VERIFICATION GATES

| Claim Type | Must Verify Via |
|-----------|----------------|
| File path | glob/view |
| API behavior | actual request |
| Performance | query with real data |
```

### 5. Self-Critique Checklist

End with quality checks:

```markdown
## ✅ PRE-DELIVERY CHECKLIST

- [ ] Every claim has evidence
- [ ] Output matches template
- [ ] No assumptions without verification
- [ ] Confidence labels present
- [ ] Counter-evidence considered
```

---

## Design Principles

### 1. Be Specific, Not Vague

```markdown
# ❌ Bad
"Check the logs for errors"

# ✅ Good
"Query ERROR_TABLE | where level == 'ERROR' | where time > ago(1h) | summarize count() by error_type"
```

### 2. Include Decision Trees

```markdown
# ❌ Bad
"Handle errors appropriately"

# ✅ Good
If error count > 100/min → CRITICAL, escalate immediately
If error count 10-100/min → HIGH, investigate within 1h
If error count < 10/min → MEDIUM, investigate within 1d
```

### 3. Show Don't Tell

```markdown
# ❌ Bad
"Format the output nicely"

# ✅ Good (include a complete example)
## Example Output:
| Service | p95 Latency | Status |
|---------|------------|--------|
| auth-svc | 45ms | ✅ Normal |
| data-svc | 2300ms | 🔴 Degraded |
```

### 4. Layer Skills

Skills should compose, not compete:

```markdown
## 🔗 INTEGRATION WITH OTHER SKILLS

| Situation | Route To |
|-----------|----------|
| Need evidence validation | evidence-driven skill |
| Need architecture review | architect-first skill |
| Need to track progress | cross-session-planner |
```

---

## Testing Your Skill

1. **Trigger test** — Does the agent activate the skill on relevant keywords?
2. **Workflow test** — Does it follow the phases in order?
3. **Output test** — Does output match the template?
4. **Negative test** — Does it correctly NOT activate on similar-but-wrong queries?
5. **Error test** — Does it handle failures gracefully?

---

## Common Patterns

### Pattern: Investigation Skill
```
Trigger → Gather data → Analyze → Cross-validate → Present with evidence
```

### Pattern: Implementation Skill
```
Trigger → Understand requirements → Design → Validate approach → Implement → Verify
```

### Pattern: Monitoring Skill
```
Trigger → Query metrics → Compare to baseline → Detect anomalies → Alert/Report
```

### Pattern: Documentation Skill
```
Trigger → Discover current state → Structure information → Write → Validate accuracy
```

---

## Sharing Skills

When contributing skills to this repo:
1. Remove any proprietary/internal references
2. Replace specific service names with generic examples
3. Include a "Customization" section explaining what to change
4. Add to the README skill inventory
