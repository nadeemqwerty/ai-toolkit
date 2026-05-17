---
name: pr-author
description: >
  PR authoring skill for generating clear, evidence-based pull request titles and
  descriptions from a diff. Activates on keywords like: PR, pull request, create PR,
  PR description, PR title, submit changes.
---

# PR Author Skill

> **A good PR explains the why, groups the change logically, and tells reviewers exactly
> how to validate risk.**

This skill helps an agent inspect the diff, extract intent, summarize the implementation,
and write a high-quality PR title and description.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks to create a PR or write a PR description
- User asks for a PR title
- User wants a summary of changes for reviewers
- User asks how to present testing, risk, or rollout context

---

## 🔄 WORKFLOW

### Step 1: Analyze the diff
Collect:
- files changed
- lines added / removed
- major change clusters
- tests added / updated
- config or contract changes

### Step 2: Identify the "why"
Determine:
- linked issue, task, or requirement
- business or operational motivation
- user-visible impact

### Step 3: Group changes logically
Summarize by logical unit, not by raw file order.
Typical groups:
- feature behavior
- validation or error handling
- tests
- docs / config / rollout support

### Step 4: Assess risk and verification
Document:
- what could go wrong
- what was tested
- manual verification steps
- rollback or mitigation path if relevant

### Step 5: Generate PR title and body
Output:
- concise, action-oriented PR title
- structured description reviewers can scan quickly

---

## ✍️ TITLE GUIDELINES

A good title should be:
- concise
- specific about the behavior change
- phrased as the actual change, not vague intent

Good examples:
- `Add sprint dashboard skills for ADO and Jira`
- `Prevent duplicate cache writes during retry`
- `Write regression tests for empty-input parser case`

Avoid:
- `misc fixes`
- `updates`
- `changes requested by review`

---

## 🧱 PR DESCRIPTION TEMPLATE

```markdown
## What
<1-2 sentences summarizing the change>

## Why
<Link to issue/requirement. Business context.>

## How
<Technical approach. Key design decisions.>

## Changes
- `path/file1`: <what changed and why>
- `path/file2`: <what changed and why>

## Testing
- [ ] Unit tests added/updated
- [ ] Manual verification: <steps>
- [ ] Edge cases considered: <list>

## Risk
<What could go wrong? Rollback plan?>

## Screenshots
<If UI change>
```

---

## 📋 AUTHORING RULES

- Start with the **why**, not the file list
- Group files into meaningful change sets
- Mention tests that actually ran, not aspirational ones
- Call out risk honestly; do not hide migration or compatibility concerns
- If there is no UI change, say screenshots are not applicable
- Keep the description scannable with short bullets and short sections

### Change bullet guidance
Each file bullet should explain both:
- what changed
- why that change exists

Bad:
- `foo.py`: updated code

Good:
- `foo.py`: adds iteration-date matching so the active sprint is resolved from real dates instead of sprint-name guesses

---

## ✅ OUTPUT EXPECTATION

Return:
1. Suggested PR title
2. Completed PR description
3. Optional reviewer notes if there is unusual risk or rollout context
