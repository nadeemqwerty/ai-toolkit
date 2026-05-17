# Shared Tools & Scripts

> Reusable tools available to all agents. These handle common tasks that are
> too complex or risky to do manually every time.

---

## Philosophy

When working with large codebases, direct AI analysis can be unreliable.
Purpose-built tools provide:
- **Safety** — bounded output, time limits, row caps
- **Reproducibility** — same inputs → same outputs
- **Composability** — tools chain together
- **Trust** — validated once, used many times

---

## Available Tools

### 1. Workspace Status Dashboard
- **Script**: `scripts/workspace-status.ps1`
- **Purpose**: Show all repo clones, branches, dirty state at a glance
- **Usage**:
  ```powershell
  .\workspace-status.ps1              # All repos
  .\workspace-status.ps1 -Repo MyApp  # Single repo
  .\workspace-status.ps1 -Detailed    # Show dirty file list
  ```

### 2. JDK Version Switcher
- **Script**: `scripts/switch-java.ps1`
- **Purpose**: Switch between Java versions for the current session and persist as default
- **Usage**:
  ```powershell
  .\switch-java.ps1 8    # Switch to Java 8
  .\switch-java.ps1 17   # Switch to Java 17
  ```

### 3. Auto-Reconnecting Port Forward
- **Script**: `scripts/Start-PortForward.ps1`
- **Purpose**: kubectl port-forward with automatic reconnection on drop
- **Usage**:
  ```powershell
  .\Start-PortForward.ps1 -Service my-service -Namespace default -LocalPort 8080 -Context my-cluster
  ```

### 4. Agency Workspace Isolation (Git Worktrees)
- **Module**: `scripts/AgencyWorkspace.psm1`
- **Purpose**: Create isolated git worktrees for parallel tasks, with advisory registry
- **Usage**:
  ```powershell
  Import-Module .\AgencyWorkspace.psm1
  New-AgencyWorkspace -Repo MyApp -Task fix-auth       # Create workspace
  Get-AgencyWorkspaces                                  # List active
  Remove-AgencyWorkspace -Repo MyApp -Task fix-auth    # Clean up
  ```

---

## Adding New Tools

When creating a new tool:
1. Save the script to appropriate location
2. Document it here following the format above
3. Include safety limits (max rows, time bounds)
4. All tools should work standalone (no agent-specific dependencies)
5. Save output to timestamped files for audit trail

---

## Query Patterns (Customize for Your Stack)

```sql
-- Request errors in last hour
SELECT status_code, COUNT(*) as count
FROM requests
WHERE timestamp > NOW() - INTERVAL '1 hour'
AND status_code >= 400
GROUP BY status_code
ORDER BY count DESC;

-- Latency percentiles by endpoint
SELECT endpoint,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_ms) as p50,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) as p95,
  PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) as p99
FROM requests
WHERE timestamp > NOW() - INTERVAL '1 hour'
GROUP BY endpoint
ORDER BY p99 DESC;
```
