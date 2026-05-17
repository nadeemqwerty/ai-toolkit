# Known Patterns & Solutions

> Reusable solutions to problems the agent has encountered before.
> Prevents re-investigating the same issues across sessions.

---

## Format

### [Area/Service] Problem Description
- **Symptoms**: What it looks like
- **Root Cause**: Why it happens
- **Solution**: How to fix it
- **Prevention**: How to avoid it
- **Last Seen**: YYYY-MM-DD

---

<!-- Patterns will be appended below this line -->

### [Example] Database Connection Pool Exhaustion
- **Symptoms**: API requests timing out, "connection pool exhausted" in logs, gradual degradation
- **Root Cause**: Long-running transactions holding connections, connection leak in error paths
- **Solution**: 
  1. Check active connections: `SELECT * FROM pg_stat_activity WHERE state != 'idle'`
  2. Kill long-running queries: `SELECT pg_terminate_backend(pid)`
  3. Fix leak: ensure connections are closed in finally/defer blocks
- **Prevention**: Set connection pool max-wait timeout, add connection leak detection, monitor active connections
- **Last Seen**: YYYY-MM-DD

### [Example] Deployment Causes Latency Spike
- **Symptoms**: p95 latency increases 5-10x immediately after deployment, recovers in 5-15 minutes
- **Root Cause**: JVM cold start / JIT compilation / cache warming after pod restart
- **Solution**: Implement readiness probe with warmup period, pre-warm caches on startup
- **Prevention**: Rolling deployments with slow rollout, readiness gates that check latency
- **Last Seen**: YYYY-MM-DD

### [Example] Search Index Drift
- **Symptoms**: Items visible in database but not in search results, inconsistent counts
- **Root Cause**: Async indexing failed silently, dead letter queue growing
- **Solution**: 
  1. Check DLQ depth
  2. Reprocess failed messages
  3. If widespread: trigger full reindex
- **Prevention**: Monitor DLQ depth, alert on indexing lag > threshold
- **Last Seen**: YYYY-MM-DD
