---
name: code-heatmap
description: >
  Cross-references a code knowledge graph with runtime telemetry to classify
  every code node as hot/cold/dead. Produces heat-labeled graph, dead-code candidates,
  and hot-path chains. Activates on keywords like: heatmap, hot path, cold path, dead code,
  unused code, code coverage, runtime evidence, telemetry coverage, code health.
---

# Code Heatmap: Code Graph × Runtime Telemetry

> **Static code graph + production telemetry = evidence-based path classification.**

Cross-references a code knowledge graph (from tools like [graphify](https://github.com/safishamsi/graphify))
with runtime logs/metrics to label every class/method as hot, cold, or unobserved.

---

## §1 CONCEPTS

### Heat Labels (NOT binary dead/alive)

| Label | Emoji | Meaning | Action |
|-------|-------|---------|--------|
| `observed_hot` | 🔥 | Top percentile by runtime hits | Optimize, monitor closely |
| `observed_warm` | 🌡️ | Mid-range runtime hits | Normal — no action |
| `observed_cold` | 🧊 | Low but non-zero hits | Review — still needed? |
| `inferred_warm` | 🟡 | Called by a hot node (propagated) | Likely executes, low telemetry |
| `statically_reachable_unobserved` | ⚪ | Has callers in code but zero evidence | Probably executes but doesn't log |
| `unreachable_unobserved` | ⚠️ | No callers AND no runtime evidence | **Review candidate** (NOT confirmed dead) |
| `scheduled_observed` | ⏰ | Job/cron code with expected execution | Normal for batch jobs |
| `scheduled_unobserved` | ❓ | Job code with no recent execution | Check if disabled/broken |
| `test_only` | 🧪 | In test paths — excluded | N/A |
| `generated_or_framework` | ⚙️ | Generated/DTO/config code | Usually framework-loaded |

> ⚠️ **"No runtime evidence" ≠ "dead code"**. Code may be: DR paths, feature-flagged,
> admin APIs, framework-wired (DI/reflection), region-specific, or one-time migration.
> Always require human review before any removal action.

### Confidence Levels

- **high**: Exact fully-qualified class name match in logs
- **medium**: Partial/suffix match or endpoint-to-class mapping
- **low**: Fuzzy substring match only
- **inferred**: No direct evidence, heat propagated from caller
- **none**: No evidence at all

### Heat Propagation

Hot nodes propagate heat to callees:
- Decay factor: `score × 0.5^depth` (halves each hop)
- Max propagation depth: 3 hops
- Edge weights: calls=1.0, implements=0.6, extends=0.5, uses=0.3, imports=0.0

---

## §2 SIGNAL SOURCES

Map your telemetry to code:

| Signal Type | What it Captures | Maps to |
|-------------|-----------------|---------|
| API endpoint hits | REST endpoint call counts | Resource/Controller classes |
| Logger class names | Java/Python class names in log output | Class nodes by FQCN |
| Stack traces | Method names in exceptions | Method nodes |
| Job execution events | Background task/job runs | Job runner classes |

### Adapting to Your Stack

Replace these queries with your own telemetry source:

```
# API hits → which endpoints are active
YOUR_REQUEST_TABLE | summarize count() by endpoint | top 100 by count_

# Logger activity → which classes are logging
YOUR_LOG_TABLE | summarize count() by logger_name | top 500 by count_

# Errors → which methods appear in stack traces  
YOUR_LOG_TABLE | where level == "ERROR" | parse message with regex | summarize by method_name
```

---

## §3 USAGE

### Prerequisites

1. **Code graph** built (e.g., via graphify, CodeGraphContext, or similar)
2. **Telemetry access** — logs/metrics with class/method names
3. **Python 3.10+** (the included `heatmap.py` uses stdlib + subprocess)

### Quick Start

```bash
# Step 1: Build code graph
cd ~/repos/your-service
graphify .

# Step 2: Run heatmap analysis
python heatmap.py \
  --graph graphify-out/graph.json \
  --service your-service \
  --lookback 30d

# Step 3: View results
cat graphify-out/HEATMAP_REPORT.md
```

### Options

```
--graph <path>       Required: path to code graph JSON
--service <name>     Required: service name for telemetry filtering
--lookback 30d       Kusto/telemetry time window (default: 30d)
--hot-pct 80         Hot threshold percentile (default: 80)
--cold-pct 20        Cold threshold percentile (default: 20)
--output <dir>       Output directory (default: graphify-out)
--skip-kusto         Skip live queries, use cached signals
--signals-file X     Load pre-computed signals from JSON
--update             Incremental: query delta since last run, merge
--diff               Show diff against previous snapshot
--decay 0.9          Decay factor for old signals (default: 0.9)
```

### Incremental Mode (`--update`)

Instead of re-querying the full window every time:
1. **State tracking** — records timestamp of each query
2. **Delta query** — only queries data since last run
3. **Signal merge** — old signals decayed, new delta added
4. **Snapshot history** — each run saved for trend tracking
5. **Diff report** — shows promotions/demotions between runs

---

## §4 OUTPUT FILES

```
graphify-out/
├── graph.json              # Code graph (input)
├── heatmap.json            # Heat-labeled nodes (output)
├── HEATMAP_REPORT.md       # Human-readable report with trends
├── signals.json            # Cached telemetry signals
├── heatmap-state.json      # Incremental state
└── heatmap-history/        # Timestamped snapshots
```

### heatmap.json Structure

```json
{
  "service": "your-service",
  "lookback": "30d",
  "total_nodes": 1247,
  "classification": {
    "observed_hot": 89,
    "observed_warm": 234,
    "unreachable_unobserved": 156
  },
  "nodes": [
    {
      "id": "node_123",
      "label": "com.example.api.UserController",
      "type": "class",
      "heatLabel": "observed_hot",
      "score": 97.3,
      "confidence": "high",
      "evidence": [
        {"type": "web_requests", "key": "/users", "hits": 45230}
      ]
    }
  ]
}
```

---

## §5 INTERPRETING RESULTS

### What "unreachable_unobserved" Means

**Does NOT mean**: "Delete this code."

**Does mean**: "In N days of telemetry, zero evidence this executed, AND no static callers."

**Before acting, check**:
- Is it behind a feature flag?
- Is it a DR/failover path?
- Is it loaded via reflection/DI?
- Is it region-specific?
- Is it admin-only?
- Is it a new, undeployed feature?

### Scheduled Jobs

For batch/cron jobs:
- "Cold" is relative to their cadence (daily job won't look "hot")
- `scheduled_observed` = ran at least once in lookback window
- `scheduled_unobserved` = possibly disabled, config-gated, or broken

---

## §6 KNOWN LIMITATIONS

1. **Logger ≠ full coverage** — utility classes may execute without logging
2. **No method-level granularity on happy path** — only errors give stack traces
3. **Static graph ≠ runtime dispatch** — reflection, DI, virtual dispatch are approximations
4. **Endpoint matching is heuristic** — custom routing may cause mismatches
5. **Time window may miss** — monthly jobs, seasonal features, admin tools

---

## §7 EXTENDING

### Adding a New Service

```python
SERVICE_SIGNALS["my-service"] = {
    "web_requests": True,      # Has REST API?
    "details_log": True,       # Emits structured logs?
    "task_hosting": False,     # Has background tasks?
    "service_filter": "myservice",
    "scheduled": False,
}
```

### Custom Signal Sources

Add new query functions for your specific telemetry (Geneva, Datadog, Prometheus, etc.)
and register in the signal collection pipeline.

### Visualization

Output feeds into graph visualization tools (graphify HTML, Neo4j, Gephi) with
heat-based node coloring.
