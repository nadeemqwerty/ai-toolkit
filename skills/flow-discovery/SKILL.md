---
name: flow-discovery
description: >
  Automated end-to-end API flow discovery. Given an endpoint or feature, traces the
  full request path through services, producing a documented flow with code paths,
  log evidence, and downstream effects.
  Activates on keywords like: flow, trace, endpoint, request path, how does X work,
  what happens when, API flow, call chain, service hop, downstream, upstream.
---

# Flow Discovery Skill

> Given any API endpoint, feature, or user action, trace the complete request lifecycle
> and produce a structured flow document with evidence at every step.

---

## 🎯 WHEN TO ACTIVATE

- "How does [endpoint] work?"
- "Trace the [feature] flow"
- "What happens when [action]?"
- "Discover all [service] endpoints"
- Any question about request paths, call chains, service hops

---

## 📋 DISCOVERY METHOD (6-Phase)

### Phase 1: Identify the Target
- Resolve user's question to concrete HTTP method + URL pattern
- Check if flow already documented (avoid duplicating work)

### Phase 2: Prod Telemetry Evidence
Query your request logs for real traffic:
```
# Find recent requests for this endpoint
REQUEST_TABLE
| where time > ago(2h)
| where url contains "<endpoint>"
| project time, request_id, url, status, duration, service
| take 20

# Pick a request_id and trace through all services
LOG_TABLE
| where time > ago(2h)
| where request_id == "<id>"
| project time, service, level, message
| order by time asc
```

### Phase 3: Code Path Tracing
For each service hop found in logs:
1. **Entry point** — Find controller/handler class
2. **Service layer** — Follow method calls into business logic
3. **Data layer** — Identify database writes, cache operations
4. **Async effects** — Webhooks, events, notifications

### Phase 4: Downstream Effect Mapping
For each mutation, identify:
- Database writes (what records change?)
- Search index updates (sync or async?)
- Event publishing (what topics/queues?)
- Cache invalidation
- Billing/metering
- External notifications

### Phase 5: Document the Flow
```markdown
# Flow: [Method] [Path]

## Evidence
- Endpoint: `METHOD /path`
- Traced request_id: `<id>` at `<timestamp>`

## Request Flow
1. [Service A] receives request
2. [Auth/validation step]
3. [Business logic]
4. [Data mutation]
5. [Async effects]

## Code Path
1. Entry: `file.java` → `method()`
2. Service: `file.java` → `method()`
3. Store: `file.java` → `method()`

## Downstream Effects
- DB: [what changes]
- Search: [what indexes]
- Events: [what publishes]

## Error Paths
- 400: [condition]
- 403: [condition]
- 404: [condition]
- 500: [known crash scenarios]

## Performance
- P50: Xms, P95: Xms, P99: Xms
```

### Phase 6: Validate
- Every service hop has log evidence
- Every code reference points to existing file
- Latency numbers come from real data
- Error paths validated against actual responses

---

## 🔄 CONTINUOUS DISCOVERY MODE

When asked to discover all flows:
1. Generate endpoint inventory from code annotations (@Path, @Route, etc.)
2. Prioritize by traffic volume from logs
3. Discover in priority order, skip already-documented
4. Cross-validate each flow

---

## ✅ QUALITY CRITERIA

Every flow document MUST have:
- [ ] At least 1 real request ID from telemetry
- [ ] Code file paths that exist in the repo
- [ ] Minimum 2 service hops traced
- [ ] At least 1 downstream effect identified
- [ ] Error path for at least 400 and 500 cases

---

## 🚫 HALLUCINATION AVOIDANCE

1. **Never invent request IDs** — only from actual query results
2. **Never assume API paths** — only from observed logs or source code
3. **Never claim "this is the only path"** — caveat with time window
4. **Never guess service names** — verify from live infrastructure
5. **Never describe 10+ hops without a single trace ID** → likely fabricated

When uncertain:
```markdown
> ⚠️ UNVERIFIED: This hop is inferred from code structure but has no log evidence.
> Confidence: LOW — needs telemetry validation.
```

---

## ⚡ PARALLELIZATION

- Code search for controller + service + store layers → ALL PARALLEL
- Query request logs + detail logs + downstream tables → ALL PARALLEL
- Multi-service flows → launch parallel explore agents per service hop
- Code tracing AND log querying → SAME turn (independent operations)
