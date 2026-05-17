---
name: jira-sprint
description: >
  Jira sprint skill for finding the active sprint, listing sprint issues, tracking sprint
  health, and comparing burndown and velocity. Activates on keywords like: Jira,
  sprint, current sprint, board, backlog, story points, velocity, kanban, scrum.
---

# Jira Sprint Skill

> **Anchor sprint analysis on the active board and active sprint. Never guess the sprint
> from issue labels or names alone.**

This skill helps an agent discover the active Jira sprint, query sprint issues, evaluate
progress, detect scope creep, and present a concise sprint dashboard.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks for the current Jira sprint
- User asks about sprint issues, board, or backlog
- User asks for sprint progress, burndown, or velocity
- User wants sprint-specific JQL or sprint issue operations
- User mentions scrum, story points, or sprint health in Jira

---

## 🔐 AUTH SETUP

Expect these environment variables or equivalent config:
- `JIRA_URL` — base Jira URL, e.g. `https://company.atlassian.net`
- `JIRA_TOKEN` — Jira API token
- `JIRA_EMAIL` — Jira user email for basic auth
- Optional: `JIRA_BOARD_ID` or default project-to-board mapping

Common auth patterns:

### Basic auth (default)
```powershell
$pair = "${env:JIRA_EMAIL}:$env:JIRA_TOKEN"
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ Authorization = "Basic $basic" }
```

```bash
curl -u "$JIRA_EMAIL:$JIRA_TOKEN" "$JIRA_URL/rest/agile/1.0/board/$JIRA_BOARD_ID/sprint?state=active"
```

### Bearer token (OAuth only)
```powershell
$headers = @{ Authorization = "Bearer $env:JIRA_TOKEN" }
```

---

## 🔄 WORKFLOW

### Step 1: Resolve Jira instance and board
1. Read `JIRA_URL` and auth config from environment or repo config
2. Resolve the board from:
   - explicit board ID
   - project key mapping
   - board search API if needed

Useful board discovery API:
```http
GET /rest/agile/1.0/board?projectKeyOrId={projectKey}
```

### Step 2: Get the active sprint
Primary API:

```http
GET /rest/agile/1.0/board/{boardId}/sprint?state=active
```

Rules:
- If exactly one sprint is active, use it
- If multiple are active, present board-specific context and choose explicitly by board
- If none are active, fall back to future sprint or report that no active sprint exists

### Step 3: Gather sprint context
Collect:
- Sprint name
- Start date / end date
- Goal if available
- Days remaining
- Board name

### Step 4: Query sprint issues
Primary API:

```http
GET /rest/agile/1.0/sprint/{sprintId}/issue?startAt={startAt}&maxResults={maxResults}
```

Pagination note:
- Use `startAt` and `maxResults`
- Loop until `startAt + maxResults >= total`

Useful expansions / fields:
- key
- summary
- status
- assignee
- story points field
- created / updated

### Step 5: Assess sprint health
Calculate:
- Completion % by issue count and points
- Burndown trend
- Scope creep (issues added after sprint start)
- Remaining work by status

### Step 6: Support follow-up operations
Support:
- JQL for current sprint slices
- Issue state / assignee updates
- Commenting or linking related work
- Exporting sprint tasks into planning flows

---

## 📈 SPRINT HEALTH MODEL

### Completion
Track both:
- **Issue completion** = completed issues / total sprint issues
- **Point completion** = completed story points / total sprint story points

### Burndown status
Estimate by comparing:
- elapsed sprint time %
- completed points %

Interpretation:
- **On track**: progress roughly matches elapsed time
- **Ahead**: completion exceeds expected burn
- **Behind**: completion materially trails elapsed time

### Scope creep detection
Flag issues added **after sprint start**.

Detection pattern:
- Compare issue `created` or sprint membership change time against sprint start
- Count issues or points added mid-sprint
- Separate planned scope from added scope in the dashboard

### At-risk issues
Flag issues when ANY is true:
- unassigned and not done
- large point value late in sprint
- blocked / impediment label
- status unchanged for too long

---

## 🔌 API / JQL PATTERNS

### Active sprint for board
```http
GET /rest/agile/1.0/board/{boardId}/sprint?state=active
```

### Sprint issues
```http
GET /rest/agile/1.0/sprint/{sprintId}/issue?startAt={startAt}&maxResults={maxResults}
```

Paginate by increasing `startAt` until the response `total` is exhausted.

### Board discovery
```http
GET /rest/agile/1.0/board?projectKeyOrId={projectKey}
```

### Current sprint JQL
```jql
sprint in openSprints() AND project = "PROJ"
```

### My current sprint work
```jql
sprint in openSprints() AND assignee = currentUser() AND project = "PROJ"
```

### Blocked sprint work
```jql
sprint in openSprints() AND project = "PROJ" AND labels = blocked
```

### Done this sprint
```jql
sprint in openSprints() AND project = "PROJ" AND statusCategory = Done
```

### Scope added mid-sprint
Use issue timestamps and sprint start time to separate original vs added scope.

---

## 🔗 INTEGRATION NOTES

### With planning workflows
- Map each Jira issue to a stable task ID like `jira-{issueKey}`
- Preserve sprint ID, board ID, and assignee in metadata
- Sync only non-done issues by default

### With PR authoring / code review
- Use issue keys from branch names, commits, or PR text
- Tie sprint-critical issues to PR risk and review summaries

---

## 🧱 OUTPUT TEMPLATE

```markdown
## 🏃 Sprint Dashboard: <Sprint Name>
📅 <start> → <end> (<X days remaining>)
📊 Completion: <X>/<Y story points> (<Z%>)
⚠️ Scope change: +<N items added mid-sprint>

### Sprint Issues
| Key | Summary | Status | Assignee | Points |
|-----|---------|--------|----------|-------:|
| ... | ... | ... | ... | ... |

### By Status
| Status | Count | Points |
|--------|------:|------:|
| Done | ... | ... |
| In Progress | ... | ... |
| To Do | ... | ... |

### Risks
- <blocked or stale issue>
- <scope creep or burn concern>

### Recommended Actions
1. <re-scope / unblock / reassign>
2. <update issue / notify owner>
```

---

## ✅ OPERATION RULES

- Always resolve the **active sprint from the board API** before issuing sprint claims
- Prefer board-scoped issue queries over generic project queries when sprint context matters
- Call out missing story-point configuration explicitly
- Separate planned scope from scope added after sprint start
- Do not infer burndown quality without both sprint dates and issue progress data
