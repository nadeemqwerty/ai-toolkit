---
name: ado-sprint
description: >
  Azure DevOps sprint skill for discovering the current iteration, summarizing sprint
  health, listing sprint work items, and syncing sprint context into agent workflows.
  Activates on keywords like: ADO, sprint, iteration, current sprint, work items,
  backlog, board, sprint planning, velocity.
---

# Azure DevOps Sprint Skill

> **Know the current sprint first. Then reason from real iteration dates, real work items,
> and real team capacity.**

This skill helps an agent identify the active Azure DevOps sprint, gather iteration context,
inspect work items, assess sprint health, and compare current progress with historical velocity.

---

## 🎯 WHEN TO ACTIVATE

Trigger on ANY of:
- User asks about the current ADO sprint or iteration
- User asks for sprint backlog, board, or work items
- User asks for sprint planning, sprint health, or velocity
- User wants to create or update work items in the active sprint
- User wants to link sprint work to pull requests or agent tasks

---

## 🔎 REQUIRED INPUTS

Collect or infer these before acting:
- **Organization** and **project** from the git remote URL
- **Team name** from repo convention, config, or explicit user input
- **Auth** via Azure CLI session, `az devops login`, or configured ADO defaults
- Optional filters: assignee, state, work item type, board path

**Remote parsing patterns:**
- HTTPS: `https://dev.azure.com/{org}/{project}/_git/{repo}`
- SSH: `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`

---

## 🔄 WORKFLOW

### Step 1: Detect org / project / team
1. Run `git remote get-url origin`
2. Parse `{org}` and `{project}` from the remote URL
3. Resolve the team from user input, local defaults, or ADO team settings

### Step 2: Identify the current iteration
Prefer the team settings API:

```http
GET https://dev.azure.com/{org}/{project}/{team}/_apis/work/teamsettings/iterations?$timeframe=current&api-version=7.1-preview.1
```

Fallback approach:
1. Query team iterations with start and finish dates
2. Match today's date to the iteration date range
3. Use the matching iteration path as the sprint context

CLI option:
```powershell
az boards iteration team list --organization https://dev.azure.com/{org} --project {project} --team {team}
```

### Step 3: Gather sprint context
Collect:
- Sprint name / iteration path
- Start date and end date
- Days remaining
- Team capacity
- Total work items and story points

Capacity API:

```http
GET https://dev.azure.com/{org}/{project}/{team}/_apis/work/teamsettings/iterations/{iterationId}/capacities?api-version=7.1-preview.1
```

### Step 4: Query sprint work items
Prefer the team iteration CLI for quick listing:

```powershell
az boards iteration team list-work-items --organization https://dev.azure.com/{org} --project {project} --team "{team}" --id "{iterationId}"
```

Or use WIQL when you need filtering in the query itself:

```powershell
az boards query --organization https://dev.azure.com/{org} --project {project} --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.IterationPath] = '{iterationPath}' ORDER BY [System.ChangedDate] DESC"
```

Then filter locally or via WIQL by:
- State
- Assigned To
- Work item type
- Tags / blocked markers

Note: these listing commands return work item IDs only. Use `az boards work-item show --id {id}` to fetch full field details for each item.

Useful WIQL pattern:
```sql
SELECT [System.Id], [System.Title], [System.State], [System.AssignedTo],
       [System.WorkItemType], [Microsoft.VSTS.Scheduling.StoryPoints]
FROM WorkItems
WHERE [System.IterationPath] = '{iterationPath}'
ORDER BY [System.ChangedDate] DESC
```

### Step 5: Build sprint dashboard
Summarize:
- Completion % by items and story points
- Breakdown by state
- My items
- Blocked / at-risk items
- Burn vs historical average

### Step 6: Support follow-up operations
Support common actions:
- Create a task in the active sprint
- Update work item state or assignee
- Link work item to a PR or commit
- Sync sprint tasks into `cross-session-planner`

---

## 📊 SPRINT HEALTH CHECKS

### Completion
Compute both:
- **Item completion** = done items / total items
- **Point completion** = done story points / total story points

### At-risk items
Flag items when ANY is true:
- State is not Done and sprint end is near
- Blocked tag / dependency present
- No assignee
- Large story points still in To Do or New late in sprint

### Blocked items
Look for:
- `Blocked` tag
- Custom blocked field if present
- `Waiting`, `On Hold`, or similar state category
- External dependency comments or linked blockers

### Velocity tracking
Compare current sprint delivered points vs prior completed sprints.

Useful approach:
1. Fetch last 3-5 completed iterations
2. Sum completed story points in each
3. Compute historical average
4. Compare current projected finish against that average

Interpretation guidance:
- **Ahead**: current projected completion > historical average
- **On track**: within normal variance
- **At risk**: current delivered / remaining pattern trails average materially

---

## 🔌 API / CLI PATTERNS

### Current iteration
```http
GET {org}/{project}/{team}/_apis/work/teamsettings/iterations?$timeframe=current
```

### Team iterations with dates
```http
GET {org}/{project}/{team}/_apis/work/teamsettings/iterations?api-version=7.1-preview.1
```

### Sprint capacity
```http
GET _apis/work/teamsettings/iterations/{iterationId}/capacities
```

### List sprint work items
```powershell
az boards iteration team list-work-items --organization https://dev.azure.com/{org} --project {project} --team "{team}" --id "{iterationId}"
```

### Query sprint work items with WIQL
```powershell
az boards query --organization https://dev.azure.com/{org} --project {project} --wiql "SELECT [System.Id] FROM WorkItems WHERE [System.IterationPath] = '{iterationPath}' ORDER BY [System.ChangedDate] DESC"
```

Both commands return IDs only; use `az boards work-item show --id {id}` for full details.

### Update work item state
```powershell
az boards work-item update --id {id} --fields "System.State=Active"
```

### Create task in active sprint
```powershell
az boards work-item create --type Task --title "..." --fields "System.IterationPath={iterationPath}"
```

### Link PR to work item
Use ADO work item relation APIs or PR linking in the repo workflow.

---

## 🔗 CROSS-SKILL INTEGRATION

### With `cross-session-planner`
Map sprint items into agent tasks using:
- Stable task ID: `ado-{workItemId}`
- Title from work item title
- Status from ADO state
- Due date from sprint end date
- Context from iteration path and assigned owner

Suggested sync rules:
- Sync only non-completed sprint items by default
- Mark blocked items as higher urgency
- Preserve original work item ID in task metadata

### With PR / review workflows
- Link changed files and PRs back to sprint items
- Use work item references when generating PR descriptions
- Highlight sprint-critical changes in code review summaries

---

## 🧱 OUTPUT TEMPLATE

```markdown
## 🏃 Sprint Dashboard: <Sprint Name>
📅 <start> → <end> (<X days remaining>)
📊 Completion: <X>/<Y items done> (<Z%>)
📈 Velocity: <current delivered> vs <historical average>

### By State
| State | Count | Story Points |
|-------|------:|------------:|
| Done | ... | ... |
| In Progress | ... | ... |
| To Do | ... | ... |

### My Items
| ID | Title | State | Type |
|----|-------|-------|------|
| ... | ... | ... | ... |

### Risks
- <blocked item or risk>
- <scope or capacity concern>

### Recommended Actions
1. <create / update / escalate>
2. <link PR / reassign / unblock>
```

---

## ✅ OPERATION RULES

- Always identify the sprint from **real iteration dates**, not name guesses
- Prefer the team-scoped current-iteration API before manual date matching
- Report both item counts and story points when available
- Call out missing fields explicitly (capacity missing, points missing, team unknown)
- Do not infer team capacity or velocity when data is absent
- When creating or updating work, always stamp the active iteration path intentionally
