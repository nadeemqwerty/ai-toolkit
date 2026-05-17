#!/usr/bin/env python3
"""
code-heatmap: Cross-reference graphify code graph with Kusto runtime telemetry.

Classifies every code node as:
  - observed_hot: Top percentile by runtime hits
  - observed_cold: Low but non-zero runtime hits
  - inferred_warm: Called by hot node (weighted decay propagation)
  - statically_reachable_unobserved: Has incoming edges but no runtime evidence
  - unreachable_unobserved: No incoming edges AND no runtime evidence
  - scheduled_observed: Periodic job code with expected execution
  - scheduled_unobserved: Job code with no recent execution
  - test_only: In test paths, excluded from dead-code analysis

Each node gets:
  - heatLabel (above)
  - score (0-100 normalized)
  - confidence (high/medium/low)
  - evidence[] (each signal source + hit count)

Usage:
  python heatmap.py --graph graphify-out/graph.json --service web-api --lookback 30d
  python heatmap.py --graph graphify-out/graph.json --service batch-job --lookback 7d --hot-pct 80 --cold-pct 20
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

# ─── Configuration ───────────────────────────────────────────────────────────

DEFAULT_KUSTO_CLUSTER = os.environ.get(
    "HEATMAP_KUSTO_CLUSTER",
    "https://your-cluster.region.kusto.windows.net",
)
DEFAULT_KUSTO_DB = os.environ.get("HEATMAP_KUSTO_DB", "your-database")

DEFAULT_TABLES = {
    "web_requests": "WebRequests",
    "details": "ServiceDetails",
    "task_events": "TaskEvents",
}

# Signal sources per service type
SERVICE_SIGNALS = {
    "web-api": {
        "web_requests": True,
        "details_log": True,
        "stack_traces": True,
        "task_hosting": False,
        "service_filter": "web-api",
        "web_requests_table": DEFAULT_TABLES["web_requests"],
        "details_table": DEFAULT_TABLES["details"],
        "endpoint_patterns": [
            "/api/users",
            "/api/orders",
            "/api/health",
        ],
        "endpoint_node_hints": {
            "/api/users": "UserController",
            "/api/orders": "OrderController",
            "/api/health": "HealthController",
        },
    },
    "batch-job": {
        "web_requests": False,
        "details_log": True,
        "stack_traces": True,
        "task_hosting": True,
        "service_filter": "batch-processor",
        "details_table": DEFAULT_TABLES["details"],
        "task_hosting_table": DEFAULT_TABLES["task_events"],
        "scheduled": True,
        "expected_cadence_hours": 1,
    },
    "event-processor": {
        "web_requests": False,
        "details_log": True,
        "stack_traces": True,
        "task_hosting": True,
        "service_filter": "event-handler",
        "details_table": DEFAULT_TABLES["details"],
        "task_hosting_table": DEFAULT_TABLES["task_events"],
    },
}

# ─── Incremental State Management ────────────────────────────────────────────

STATE_FILE = "heatmap-state.json"
HISTORY_DIR = "heatmap-history"


def load_state(output_dir: str) -> dict:
    """Load incremental state (last query times, run metadata)."""
    state_path = Path(output_dir) / STATE_FILE
    if state_path.exists():
        return json.loads(state_path.read_text())
    return {"runs": [], "services": {}}


def save_state(output_dir: str, state: dict) -> None:
    """Persist incremental state."""
    state_path = Path(output_dir) / STATE_FILE
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2))


def get_incremental_window(state: dict, service: str, default_lookback: str) -> tuple[str, bool]:
    """Determine query window: full lookback or delta since last run.

    Returns (kql_time_expression, is_incremental).
    """
    svc_state = state.get("services", {}).get(service, {})
    last_run = svc_state.get("last_query_utc")
    if not last_run:
        return f"ago({default_lookback})", False

    return f"datetime('{last_run}')", True


def merge_signals(existing: dict[str, dict[str, int]],
                  delta: dict[str, dict[str, int]],
                  decay_factor: float = 0.9) -> dict[str, dict[str, int]]:
    """Merge delta signals into existing signals.

    Existing signals are decayed (older data worth slightly less),
    then delta is added on top. This prevents unbounded accumulation
    while keeping historical context.
    """
    merged: dict[str, dict[str, int]] = {}
    all_sources = set(list(existing.keys()) + list(delta.keys()))

    for source in all_sources:
        merged[source] = {}
        old = existing.get(source, {})
        new = delta.get(source, {})

        for key, hits in old.items():
            merged[source][key] = int(hits * decay_factor)

        for key, hits in new.items():
            merged[source][key] = merged[source].get(key, 0) + hits

        merged[source] = {k: v for k, v in merged[source].items() if v > 0}

    return merged


def save_snapshot(output_dir: str, service: str, heatmap_data: dict) -> str:
    """Save a timestamped snapshot for trend analysis."""
    hist_dir = Path(output_dir) / HISTORY_DIR
    hist_dir.mkdir(parents=True, exist_ok=True)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"heatmap_{service}_{ts}.json"

    snapshot = {
        "service": service,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "total_nodes": heatmap_data["total_nodes"],
        "classification": heatmap_data["classification"],
        "nodes": [
            {
                "id": n["id"],
                "label": n["label"],
                "heatLabel": n["heatLabel"],
                "score": n["score"],
            }
            for n in heatmap_data["nodes"]
        ],
    }
    snapshot_path = hist_dir / filename
    snapshot_path.write_text(json.dumps(snapshot, indent=2))
    return str(snapshot_path)


def generate_diff_report(output_dir: str, service: str,
                         current: dict) -> list[str] | None:
    """Compare current heatmap with most recent snapshot. Returns diff lines or None."""
    hist_dir = Path(output_dir) / HISTORY_DIR
    if not hist_dir.exists():
        return None

    snapshots = sorted(hist_dir.glob(f"heatmap_{service}_*.json"), reverse=True)
    if len(snapshots) < 2:
        return None

    prev_path = snapshots[1]
    prev = json.loads(prev_path.read_text())

    prev_labels = {n["id"]: n for n in prev.get("nodes", [])}
    curr_labels = {n["id"]: n for n in current.get("nodes", [])}

    promotions = []
    demotions = []
    new_nodes = []
    removed_nodes = []

    heat_rank = {
        "observed_hot": 6, "observed_warm": 5, "scheduled_observed": 4,
        "inferred_warm": 3, "observed_cold": 2, "statically_reachable_unobserved": 1,
        "unreachable_unobserved": 0, "scheduled_unobserved": 0,
        "test_only": -1, "generated_or_framework": -1,
    }

    for nid, curr_node in curr_labels.items():
        if nid not in prev_labels:
            new_nodes.append(curr_node)
            continue
        prev_node = prev_labels[nid]
        prev_rank = heat_rank.get(prev_node.get("heatLabel", ""), 0)
        curr_rank = heat_rank.get(curr_node.get("heatLabel", ""), 0)
        if curr_rank > prev_rank:
            promotions.append({
                "label": curr_node["label"],
                "from": prev_node["heatLabel"],
                "to": curr_node["heatLabel"],
                "score_delta": round(curr_node.get("score", 0) - prev_node.get("score", 0), 1),
            })
        elif curr_rank < prev_rank:
            demotions.append({
                "label": curr_node["label"],
                "from": prev_node["heatLabel"],
                "to": curr_node["heatLabel"],
                "score_delta": round(curr_node.get("score", 0) - prev_node.get("score", 0), 1),
            })

    for nid in prev_labels:
        if nid not in curr_labels:
            removed_nodes.append(prev_labels[nid])

    if not (promotions or demotions or new_nodes or removed_nodes):
        return ["", "## 📈 Trend (vs previous run)", "",
                f"Compared with `{prev_path.name}` — **no changes detected.**"]

    prev_class = prev.get("classification", {})
    curr_class = current.get("classification", {})
    all_labels = set(list(prev_class.keys()) + list(curr_class.keys()))

    lines = [
        "", "## 📈 Trend (vs previous run)", "",
        f"Compared with `{prev_path.name}`:", "",
        "### Classification Changes", "",
        "| Label | Previous | Current | Delta |",
        "|-------|--------:|--------:|------:|",
    ]
    for lbl in sorted(all_labels):
        p = prev_class.get(lbl, 0)
        c = curr_class.get(lbl, 0)
        d = c - p
        arrow = "🔺" if d > 0 else "🔻" if d < 0 else "➖"
        lines.append(f"| {lbl} | {p} | {c} | {arrow} {d:+d} |")

    if promotions:
        lines += ["", f"### ⬆️ Promoted ({len(promotions)} nodes)", "",
                   "| Node | From | To | Score Δ |",
                   "|------|------|----|--------:|"]
        for p in sorted(promotions, key=lambda x: -x["score_delta"])[:20]:
            lines.append(f"| `{p['label'][:50]}` | {p['from']} | {p['to']} | {p['score_delta']:+.1f} |")

    if demotions:
        lines += ["", f"### ⬇️ Demoted ({len(demotions)} nodes)", "",
                   "| Node | From | To | Score Δ |",
                   "|------|------|----|--------:|"]
        for d in sorted(demotions, key=lambda x: x["score_delta"])[:20]:
            lines.append(f"| `{d['label'][:50]}` | {d['from']} | {d['to']} | {d['score_delta']:+.1f} |")

    if new_nodes:
        lines += ["", f"### 🆕 New Nodes ({len(new_nodes)})", ""]
        for n in new_nodes[:10]:
            lines.append(f"- `{n['label'][:60]}` → {n['heatLabel']}")

    if removed_nodes:
        lines += ["", f"### 🗑️ Removed Nodes ({len(removed_nodes)})", ""]
        for n in removed_nodes[:10]:
            lines.append(f"- `{n['label'][:60]}` (was {n['heatLabel']})")

    return lines

# Patterns to identify test code
TEST_PATTERNS = [
    r"/test/",
    r"/src/test/",
    r"/e2e/",
    r"/it/",
    r"\.test\.",
    r"\.tests\.",
    r"\.it\.",
    r"Test$",
    r"Tests$",
    r"IT$",
    r"E2E$",
    r"TestCase$",
    r"Mock",
]

# Patterns to identify generated/framework code (lower confidence for dead-code)
GENERATED_PATTERNS = [
    r"\.generated\.",
    r"\.proto\.",
    r"\.thrift\.",
    r"_pb2",
    r"Grpc",
    r"\.model\.",
    r"\.dto\.",
    r"\.entity\.",  # JPA entities may be framework-loaded
    r"Constants$",
    r"Config$",
    r"Configuration$",
]

# ─── Graph Loading ───────────────────────────────────────────────────────────

def load_graph(graph_path: str) -> dict:
    """Load graphify graph.json and build lookup indexes."""
    with open(graph_path) as f:
        graph = json.load(f)

    nodes = graph.get("nodes", [])
    edges = graph.get("edges", graph.get("links", []))

    # Build indexes for fast matching
    node_by_id = {}
    nodes_by_fqcn = {}         # full qualified class name → node
    nodes_by_simple = defaultdict(list)  # simple class name → [nodes]
    nodes_by_method = defaultdict(list)  # className.methodName → [nodes]

    for node in nodes:
        nid = node.get("id", "")
        node_by_id[nid] = node
        label = node.get("label", node.get("name", ""))

        # Tag test/generated nodes
        node["_is_test"] = any(re.search(p, label) for p in TEST_PATTERNS)
        node["_is_generated"] = any(re.search(p, label) for p in GENERATED_PATTERNS)

        # Build FQCN index
        fqcn = _normalize_fqcn(label)
        if fqcn:
            nodes_by_fqcn[fqcn] = node
            # Also index by simple class name
            simple = fqcn.rsplit(".", 1)[-1] if "." in fqcn else fqcn
            nodes_by_simple[simple].append(node)

        # Index methods
        if node.get("type") in ("method", "function"):
            parent_class = node.get("parent", "")
            if parent_class:
                key = f"{_normalize_fqcn(parent_class)}.{label.split('(')[0].split('.')[-1]}"
                nodes_by_method[key].append(node)

    # Build adjacency (caller → callees)
    callees = defaultdict(list)  # node_id → [node_id]
    callers = defaultdict(list)  # node_id → [node_id]
    for edge in edges:
        src = edge.get("source", edge.get("from", ""))
        tgt = edge.get("target", edge.get("to", ""))
        etype = edge.get("type", edge.get("label", "calls"))
        if src in node_by_id and tgt in node_by_id:
            callees[src].append((tgt, etype))
            callers[tgt].append((src, etype))

    return {
        "nodes": nodes,
        "edges": edges,
        "node_by_id": node_by_id,
        "nodes_by_fqcn": nodes_by_fqcn,
        "nodes_by_simple": nodes_by_simple,
        "nodes_by_method": nodes_by_method,
        "callees": callees,
        "callers": callers,
    }


def _normalize_fqcn(name: str) -> str:
    """Normalize a Java FQCN: strip generics, inner class $, lambda suffixes."""
    if not name:
        return ""
    # Strip generics
    name = re.sub(r"<[^>]*>", "", name)
    # Normalize inner class separator
    name = name.replace("$", ".")
    # Strip lambda suffixes
    name = re.sub(r"\.lambda\$.*", "", name)
    # Strip method params
    name = name.split("(")[0]
    return name.strip()


# ─── Kusto Queries ───────────────────────────────────────────────────────────

def run_kusto_query(kql: str, cluster: str = DEFAULT_KUSTO_CLUSTER,
                    db: str = DEFAULT_KUSTO_DB) -> list[dict]:
    """Run a KQL query via az CLI and return rows as dicts."""
    try:
        token = subprocess.check_output(
            [
                "az",
                "account",
                "get-access-token",
                "--resource",
                cluster,
                "--query",
                "accessToken",
                "-o",
                "tsv",
            ],
            text=True,
        ).strip()
    except subprocess.CalledProcessError as e:
        print(f"[WARN] Failed to get Kusto token: {e}", file=sys.stderr)
        return []

    body = json.dumps({"db": db, "csl": kql})
    curl_cmd = [
        "curl.exe", "-s", "-X", "POST",
        f"{cluster}/v2/rest/query",
        "-H", f"Authorization: Bearer {token}",
        "-H", "Content-Type: application/json; charset=utf-8",
        "--data-binary", "@-",
    ]
    try:
        result = subprocess.check_output(curl_cmd, text=True, timeout=600, input=body)
        frames = json.loads(result)
    except (subprocess.CalledProcessError, json.JSONDecodeError, subprocess.TimeoutExpired) as e:
        print(f"[WARN] Kusto query failed: {e}", file=sys.stderr)
        return []

    # Parse v2 response: find PrimaryResult frame
    for frame in frames:
        if frame.get("FrameType") == "DataTable" and frame.get("TableKind") == "PrimaryResult":
            columns = [c["ColumnName"] for c in frame.get("Columns", [])]
            parsed_rows = []
            for row in frame.get("Rows", []):
                if isinstance(row, dict):
                    if "OneApiErrors" in row:
                        continue
                    parsed_rows.append(row)
                else:
                    parsed_rows.append(dict(zip(columns, row)))
            return parsed_rows

    return []


def _chunk_time_clauses(lookback: str, chunk_days: int = 1) -> list[str] | None:
    match = re.fullmatch(r"(\d+)d", lookback)
    if not match:
        return None

    total_days = int(match.group(1))
    if total_days <= chunk_days:
        return None

    now = datetime.now(timezone.utc)
    current_end = now
    clauses: list[str] = []
    remaining = total_days
    while remaining > 0:
        span = min(chunk_days, remaining)
        current_start = current_end - timedelta(days=span)
        clauses.append(
            f"TIMESTAMP >= datetime('{current_start.isoformat()}') and TIMESTAMP < datetime('{current_end.isoformat()}')"
        )
        current_end = current_start
        remaining -= span

    return clauses


def _query_counts(build_kql, key_field: str, value_field: str,
                  lookback: str, time_expr: str | None = None,
                  chunk_days: int = 1,
                  cluster: str = DEFAULT_KUSTO_CLUSTER,
                  db: str = DEFAULT_KUSTO_DB) -> dict[str, int]:
    clauses = None if time_expr else _chunk_time_clauses(lookback, chunk_days)
    aggregate: dict[str, int] = defaultdict(int)

    if clauses:
        for clause in reversed(clauses):
            rows = run_kusto_query(build_kql(clause), cluster=cluster, db=db)
            for row in rows:
                if key_field in row and value_field in row:
                    aggregate[str(row[key_field])] += int(row[value_field])
        return dict(aggregate)

    time_clause = f"TIMESTAMP > {time_expr}" if time_expr else f"TIMESTAMP > ago({lookback})"
    rows = run_kusto_query(build_kql(time_clause), cluster=cluster, db=db)
    return {
        str(row[key_field]): int(row[value_field])
        for row in rows
        if key_field in row and value_field in row
    }


def query_web_requests(service_filter: str, lookback: str,
                       time_expr: str | None = None,
                       config: dict | None = None,
                       cluster: str = DEFAULT_KUSTO_CLUSTER,
                       db: str = DEFAULT_KUSTO_DB) -> dict[str, int]:
    """Get API endpoint hit counts → maps to REST resource classes."""
    config = config or {}
    table = config.get("web_requests_table", DEFAULT_TABLES["web_requests"])
    endpoint_col = config.get("web_requests_endpoint_column", "RequestUrl")
    container_col = config.get("web_requests_container_column", "ContainerName")
    pod_col = config.get("web_requests_pod_column", "PodName")
    filter_expr = config.get("web_requests_filter")
    endpoint_patterns = config.get("endpoint_patterns", [])
    endpoint_list = ", ".join(f"'{p}'" for p in endpoint_patterns)

    def build_kql(time_clause: str) -> str:
        lines = [
            table,
            f"| where {time_clause}",
            f"| extend endpointSource = tostring(url_decode({endpoint_col}))",
        ]
        if filter_expr:
            lines.append(f"| where {filter_expr}")
        elif service_filter:
            lines.append(
                f"| where {container_col} == '{service_filter}' or {pod_col} startswith '{service_filter}-'"
            )
        if endpoint_patterns:
            lines.append(f"| where endpointSource has_any ({endpoint_list})")
        lines.extend([
            "| extend endpoint = coalesce(",
            "    extract(@'/api/[^/]+/v\\d+/([^?#]+)', 1, endpointSource),",
            "    extract(@'/api/[^/]+/([^?#]+)', 1, endpointSource),",
            "    extract(@'^/([^?#]+)', 1, endpointSource),",
            "    endpointSource",
            ")",
            "| where isnotempty(endpoint)",
            "| summarize total_hits=count() by endpoint",
            "| order by total_hits desc",
            "| take 500",
        ])
        return "\n".join(lines)

    return _query_counts(
        build_kql,
        "endpoint",
        "total_hits",
        lookback,
        time_expr,
        chunk_days=7,
        cluster=cluster,
        db=db,
    )


def query_details_log_classes(service_filter: str, lookback: str,
                              time_expr: str | None = None,
                              config: dict | None = None,
                              cluster: str = DEFAULT_KUSTO_CLUSTER,
                              db: str = DEFAULT_KUSTO_DB) -> dict[str, int]:
    """Get Java FQCN logger names from details table → maps to class nodes."""
    config = config or {}
    table = config.get("details_table", DEFAULT_TABLES["details"])
    class_col = config.get("details_class_column")
    container_col = config.get("details_container_column", "ContainerName")
    pod_col = config.get("details_pod_column", "PodName")
    message_col = config.get("details_message_column", "Msg")
    filter_expr = config.get("details_filter")

    def build_kql(time_clause: str) -> str:
        lines = [table, f"| where {time_clause}"]
        if class_col:
            lines.extend([
                f"| where isnotempty({class_col})",
                f"| summarize hits=count() by logger={class_col}",
            ])
        else:
            if filter_expr:
                lines.append(f"| where {filter_expr}")
            elif service_filter:
                lines.append(
                    f"| where {container_col} == '{service_filter}' or {pod_col} startswith '{service_filter}-' or {message_col} has '{service_filter}'"
                )
            lines.extend([
                f"| extend logger = extract(@'([a-z][a-z0-9_]*(?:\\.[a-z][a-z0-9_]*)+\\.[A-Z][A-Za-z0-9_]+)', 1, {message_col})",
                "| where isnotempty(logger)",
                "| summarize hits=count() by logger",
            ])
        lines.extend([
            "| order by hits desc",
            "| take 1000",
        ])
        return "\n".join(lines)

    return _query_counts(
        build_kql,
        "logger",
        "hits",
        lookback,
        time_expr,
        chunk_days=7,
        cluster=cluster,
        db=db,
    )


def query_stack_trace_methods(service_filter: str, lookback: str,
                              time_expr: str | None = None,
                              config: dict | None = None,
                              cluster: str = DEFAULT_KUSTO_CLUSTER,
                              db: str = DEFAULT_KUSTO_DB) -> dict[str, int]:
    """Extract class.method from error stack traces."""
    config = config or {}
    table = config.get("details_table", DEFAULT_TABLES["details"])
    stack_col = config.get("details_stack_column", config.get("details_message_column", "Msg"))
    container_col = config.get("details_container_column", "ContainerName")
    pod_col = config.get("details_pod_column", "PodName")
    filter_expr = config.get("stack_trace_filter") or config.get("details_filter")

    def build_kql(time_clause: str) -> str:
        lines = [table, f"| where {time_clause}"]
        if filter_expr:
            lines.append(f"| where {filter_expr}")
        elif service_filter:
            lines.append(
                f"| where {container_col} == '{service_filter}' or {pod_col} startswith '{service_filter}-' or {stack_col} has '{service_filter}'"
            )
        lines.extend([
            f"| where {stack_col} has 'Exception' or {stack_col} has 'at '",
            f"| extend frame = extract_all(@'at ([a-z][a-z0-9_.]+\\.[A-Z][A-Za-z0-9_]+\\.[a-zA-Z_]+)\\(', dynamic([1]), {stack_col})",
            "| mv-expand frame to typeof(string)",
            "| where isnotempty(frame)",
            "| summarize hits=count() by frame",
            "| order by hits desc",
            "| take 500",
        ])
        return "\n".join(lines)

    return _query_counts(
        build_kql,
        "frame",
        "hits",
        lookback,
        time_expr,
        chunk_days=7,
        cluster=cluster,
        db=db,
    )


def query_task_hosting(service_filter: str, lookback: str,
                       time_expr: str | None = None,
                       config: dict | None = None,
                       cluster: str = DEFAULT_KUSTO_CLUSTER,
                       db: str = DEFAULT_KUSTO_DB) -> dict[str, int]:
    """Get background task/job execution counts."""
    config = config or {}
    table = config.get("task_hosting_table", DEFAULT_TABLES["task_events"])
    message_col = config.get("task_hosting_message_column", "Message")
    task_regex = config.get("task_hosting_name_regex", r"task[= :]+([A-Za-z0-9_.]+)")
    filter_expr = config.get("task_hosting_filter") or (
        f"{message_col} contains '{service_filter}'" if service_filter else None
    )
    time_filter = time_expr or f"ago({lookback})"
    lines = [
        table,
        f"| where TIMESTAMP > {time_filter}",
    ]
    if filter_expr:
        lines.append(f"| where {filter_expr}")
    lines.extend([
        f"| extend taskName = extract(@'{task_regex}', 1, {message_col})",
        "| where isnotempty(taskName)",
        "| summarize hits=count() by taskName",
        "| order by hits desc",
        "| take 200",
    ])
    rows = run_kusto_query("\n".join(lines), cluster=cluster, db=db)
    return {str(row["taskName"]): int(row["hits"]) for row in rows if "taskName" in row and "hits" in row}


# ─── Matching Engine ─────────────────────────────────────────────────────────

EDGE_DECAY = 0.5       # Heat decays by 50% per hop
MAX_PROPAGATION_DEPTH = 3
EDGE_WEIGHTS = {
    "calls": 1.0,
    "call": 1.0,
    "implements": 0.6,
    "extends": 0.5,
    "inherits": 0.5,
    "imports": 0.0,     # Import doesn't imply execution
    "uses": 0.3,
    "references": 0.2,
}


def match_signals_to_nodes(graph: dict, signals: dict[str, dict[str, int]],
                           service: str | None = None,
                           config: dict[str, Any] | None = None) -> None:
    """Match Kusto signals to graph nodes and assign direct scores + evidence."""
    for node in graph["nodes"]:
        node["_score"] = 0.0
        node["_evidence"] = []
        node["_confidence"] = "none"

        if node.get("_is_test"):
            continue  # Skip test nodes

        label = node.get("label", node.get("name", ""))
        fqcn = _normalize_fqcn(label)
        simple = fqcn.rsplit(".", 1)[-1] if "." in fqcn else fqcn

        # Match against each signal source
        for signal_name, signal_data in signals.items():
            for key, hits in signal_data.items():
                match_conf = _match_service_specific_key_to_node(key, node, signal_name, config)
                if match_conf <= 0:
                    match_conf = _match_key_to_node(key, fqcn, simple, signal_name, service, config)
                if match_conf > 0:
                    node["_score"] += hits * match_conf
                    node["_evidence"].append({
                        "type": signal_name,
                        "key": key,
                        "hits": hits,
                        "match_confidence": match_conf,
                    })

        # Set direct confidence
        if node["_evidence"]:
            max_conf = max(e["match_confidence"] for e in node["_evidence"])
            node["_confidence"] = (
                "high" if max_conf >= 0.8
                else "medium" if max_conf >= 0.5
                else "low"
            )


def _match_service_specific_key_to_node(key: str, node: dict[str, Any], signal_name: str,
                                        config: dict[str, Any] | None = None) -> float:
    """Apply endpoint hint heuristics for graph shapes that lack FQCNs."""
    if signal_name != "web_requests" or not config:
        return 0.0

    endpoint = key.lower()
    label = str(node.get("label", "")).lower()
    source_file = str(node.get("source_file", "")).lower()

    for prefix, hinted_simple in config.get("endpoint_node_hints", {}).items():
        if endpoint.startswith(prefix.lower()):
            hinted = hinted_simple.lower()
            if hinted in label or hinted in source_file:
                return 0.95

    return 0.0


def _match_key_to_node(key: str, fqcn: str, simple: str, signal_name: str,
                       service: str | None = None,
                       config: dict[str, Any] | None = None) -> float:
    """Return match confidence (0-1) between a Kusto key and a node."""
    if not fqcn:
        return 0.0

    key_normalized = _normalize_fqcn(key)

    # Exact FQCN match
    if key_normalized == fqcn:
        return 1.0

    # FQCN ends with node name (package prefix differs)
    if key_normalized.endswith(f".{simple}") or key_normalized == simple:
        # For stack traces, method-level match is high confidence
        if signal_name == "stack_traces":
            return 0.85
        return 0.6

    if signal_name == "web_requests":
        endpoint = key.lower()
        if config:
            for prefix, hinted_simple in config.get("endpoint_node_hints", {}).items():
                if endpoint.startswith(prefix.lower()) and simple.lower() == hinted_simple.lower():
                    return 1.0

        endpoint_parts = endpoint.replace("/", ".").split(".")
        stripped_simple = simple.lower()
        for suffix in ("controller", "resource", "rest", "service", "impl"):
            stripped_simple = stripped_simple.removesuffix(suffix)
        if stripped_simple and stripped_simple in endpoint_parts:
            return 0.5

    # Substring containment (low confidence)
    if len(simple) > 4 and simple.lower() in key_normalized.lower():
        return 0.3

    return 0.0


def propagate_heat(graph: dict) -> None:
    """Propagate heat from hot nodes to callees using weighted decay."""
    # Sort nodes by score descending — propagate from hottest first
    scored_nodes = [
        n for n in graph["nodes"]
        if n["_score"] > 0 and not n.get("_is_test")
    ]
    scored_nodes.sort(key=lambda n: n["_score"], reverse=True)

    # BFS with decay from each hot node
    for source_node in scored_nodes:
        source_id = source_node["id"]
        source_score = source_node["_score"]

        # BFS queue: (node_id, depth)
        queue = [(source_id, 0)]
        visited = {source_id}

        while queue:
            current_id, depth = queue.pop(0)
            if depth >= MAX_PROPAGATION_DEPTH:
                continue

            for callee_id, edge_type in graph["callees"].get(current_id, []):
                if callee_id in visited:
                    continue
                visited.add(callee_id)

                callee_node = graph["node_by_id"].get(callee_id)
                if not callee_node or callee_node.get("_is_test"):
                    continue

                edge_weight = EDGE_WEIGHTS.get(edge_type, 0.3)
                propagated = source_score * (EDGE_DECAY ** (depth + 1)) * edge_weight

                if propagated > 0.1:  # Minimum threshold
                    callee_node["_score"] += propagated
                    callee_node["_evidence"].append({
                        "type": "propagated_call",
                        "from": source_node.get("label", source_id),
                        "edge_type": edge_type,
                        "depth": depth + 1,
                        "propagated_score": round(propagated, 2),
                    })
                    if callee_node["_confidence"] == "none":
                        callee_node["_confidence"] = "inferred"

                    queue.append((callee_id, depth + 1))


# ─── Classification ──────────────────────────────────────────────────────────

def classify_nodes(graph: dict, hot_pct: float = 80, cold_pct: float = 20,
                   is_scheduled: bool = False) -> None:
    """Assign heatLabel to each node based on scores and graph structure."""
    active_nodes = [n for n in graph["nodes"] if not n.get("_is_test")]
    scores = [n["_score"] for n in active_nodes if n["_score"] > 0]

    if scores:
        scores.sort()
        hot_threshold = scores[int(len(scores) * hot_pct / 100)] if len(scores) > 1 else scores[0]
        cold_threshold = scores[int(len(scores) * cold_pct / 100)] if len(scores) > 1 else 0
    else:
        hot_threshold = float("inf")
        cold_threshold = 0

    for node in graph["nodes"]:
        nid = node.get("id", "")
        score = node["_score"]
        has_callers = len(graph["callers"].get(nid, [])) > 0
        has_direct_evidence = any(
            e["type"] != "propagated_call" for e in node.get("_evidence", [])
        )
        has_propagated = any(
            e["type"] == "propagated_call" for e in node.get("_evidence", [])
        )

        if node.get("_is_test"):
            node["heatLabel"] = "test_only"
        elif is_scheduled and score > 0:
            node["heatLabel"] = "scheduled_observed"
        elif is_scheduled and score == 0:
            node["heatLabel"] = "scheduled_unobserved"
        elif has_direct_evidence and score >= hot_threshold:
            node["heatLabel"] = "observed_hot"
        elif has_direct_evidence and score <= cold_threshold:
            node["heatLabel"] = "observed_cold"
        elif has_direct_evidence:
            node["heatLabel"] = "observed_warm"
        elif has_propagated:
            node["heatLabel"] = "inferred_warm"
        elif has_callers:
            node["heatLabel"] = "statically_reachable_unobserved"
        elif node.get("_is_generated"):
            node["heatLabel"] = "generated_or_framework"
        else:
            node["heatLabel"] = "unreachable_unobserved"

        # Normalize score to 0-100
        max_score = max(scores) if scores else 1
        node["score"] = round(min(score / max_score * 100, 100), 1)
        node["confidence"] = node.pop("_confidence", "none")
        node["evidence"] = node.pop("_evidence", [])

    # Clean up internal fields
    for node in graph["nodes"]:
        node.pop("_score", None)
        node.pop("_is_test", None)
        node.pop("_is_generated", None)


# ─── Report Generation ───────────────────────────────────────────────────────

def generate_report(graph: dict, service: str, lookback: str, output_dir: str,
                    diff_lines: list[str] | None = None,
                    cluster: str = DEFAULT_KUSTO_CLUSTER,
                    db: str = DEFAULT_KUSTO_DB) -> dict:
    """Generate HEATMAP_REPORT.md and heatmap.json. Returns heatmap_data for snapshots."""
    outdir = Path(output_dir)
    outdir.mkdir(parents=True, exist_ok=True)

    nodes = graph["nodes"]
    label_counts = defaultdict(int)
    for n in nodes:
        label_counts[n.get("heatLabel", "unknown")] += 1

    # ── heatmap.json ──
    heatmap_data = {
        "service": service,
        "lookback": lookback,
        "total_nodes": len(nodes),
        "classification": dict(label_counts),
        "nodes": [
            {
                "id": n.get("id"),
                "label": n.get("label", n.get("name", "")),
                "type": n.get("type", "unknown"),
                "heatLabel": n.get("heatLabel"),
                "score": n.get("score", 0),
                "confidence": n.get("confidence", "none"),
                "evidence": n.get("evidence", []),
            }
            for n in nodes
        ],
    }
    (outdir / "heatmap.json").write_text(json.dumps(heatmap_data, indent=2), encoding='utf-8')

    # ── HEATMAP_REPORT.md ──
    hot = [n for n in nodes if n.get("heatLabel") == "observed_hot"]
    cold = [n for n in nodes if n.get("heatLabel") == "observed_cold"]
    unreachable = [n for n in nodes if n.get("heatLabel") == "unreachable_unobserved"]
    unobserved = [n for n in nodes if n.get("heatLabel") == "statically_reachable_unobserved"]

    hot.sort(key=lambda n: n.get("score", 0), reverse=True)
    unreachable.sort(key=lambda n: n.get("label", ""))

    lines = [
        f"# Code Heatmap Report: {service}",
        f"",
        f"**Lookback**: {lookback} | **Total nodes**: {len(nodes)} | "
        f"**Generated**: {__import__('datetime').datetime.now().isoformat()[:19]}",
        "",
        "## Summary",
        "",
        "| Label | Count | % |",
        "|-------|------:|---:|",
    ]
    for label, count in sorted(label_counts.items(), key=lambda x: -x[1]):
        pct = round(count / len(nodes) * 100, 1) if nodes else 0
        emoji = {
            "observed_hot": "🔥",
            "observed_warm": "🌡️",
            "observed_cold": "🧊",
            "inferred_warm": "🟡",
            "statically_reachable_unobserved": "⚪",
            "unreachable_unobserved": "⚠️",
            "scheduled_observed": "⏰",
            "scheduled_unobserved": "❓",
            "test_only": "🧪",
            "generated_or_framework": "⚙️",
        }.get(label, "")
        lines.append(f"| {emoji} {label} | {count} | {pct}% |")

    lines += [
        "",
        "## 🔥 Top Hot Paths (Top 20 by score)",
        "",
        "| Score | Confidence | Node | Evidence Sources |",
        "|------:|:----------:|------|-----------------|",
    ]
    for n in hot[:20]:
        evidence_summary = ", ".join(
            f"{e['type']}({e.get('hits', e.get('propagated_score', '?'))})"
            for e in n.get("evidence", [])[:3]
        )
        lines.append(
            f"| {n.get('score', 0)} | {n.get('confidence', '')} | "
            f"`{n.get('label', '')[:60]}` | {evidence_summary} |"
        )

    lines += [
        "",
        "## ⚠️ No Runtime Evidence (Review Candidates)",
        "",
        f"**{len(unreachable)}** nodes with no incoming edges AND no runtime evidence in {lookback}.",
        "",
        "> ⚠️ These are NOT confirmed dead code. They may be: DR paths, feature-flagged, "
        "admin APIs, framework-wired (DI/reflection), region-specific, or one-time migration code. "
        "**Manual review required before removal.**",
        "",
        "| Node | Type | Notes |",
        "|------|------|-------|",
    ]
    for n in unreachable[:50]:
        ntype = n.get("type", "")
        notes = "generated/framework" if n.get("heatLabel") == "generated_or_framework" else ""
        lines.append(f"| `{n.get('label', '')[:60]}` | {ntype} | {notes} |")

    if len(unreachable) > 50:
        lines.append(f"| ... | | +{len(unreachable) - 50} more (see heatmap.json) |")

    lines += [
        "",
        f"## ⚪ Statically Reachable but Unobserved ({len(unobserved)} nodes)",
        "",
        "These have incoming call edges but no runtime telemetry. Likely executed but "
        "not instrumented, or called from unmonitored paths.",
        "",
        "## 🧊 Cold Paths (Bottom 20%)",
        "",
        "| Score | Node | Last Evidence |",
        "|------:|------|--------------|",
    ]
    for n in cold[:20]:
        ev = n.get("evidence", [{}])[0]
        lines.append(
            f"| {n.get('score', 0)} | `{n.get('label', '')[:60]}` | "
            f"{ev.get('type', 'none')}({ev.get('hits', 0)}) |"
        )

    lines += [
        "",
        "---",
        f"*Generated by code-heatmap skill. Data from Kusto ({cluster}/{db}).*",
    ]

    # Append diff/trend section if provided
    if diff_lines:
        lines += diff_lines

    (outdir / "HEATMAP_REPORT.md").write_text("\n".join(lines), encoding='utf-8')
    print(f"\n✅ Report written to {outdir / 'HEATMAP_REPORT.md'}")
    print(f"✅ Data written to {outdir / 'heatmap.json'}")
    print(f"\nSummary: {dict(label_counts)}")
    return heatmap_data

# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Code Heatmap: graphify × Kusto")
    parser.add_argument("--graph", required=True, help="Path to graphify-out/graph.json")
    parser.add_argument("--service", required=True, choices=list(SERVICE_SIGNALS.keys()),
                        help="Service to analyze")
    parser.add_argument("--lookback", default="30d", help="Kusto lookback window (e.g., 7d, 30d)")
    parser.add_argument("--hot-pct", type=float, default=80, help="Percentile for hot classification")
    parser.add_argument("--cold-pct", type=float, default=20, help="Percentile for cold classification")
    parser.add_argument("--output", default="graphify-out", help="Output directory")
    parser.add_argument("--skip-kusto", action="store_true",
                        help="Skip Kusto queries (use existing signals file)")
    parser.add_argument("--signals-file", help="Load pre-computed signals from JSON")
    parser.add_argument("--cluster", default=DEFAULT_KUSTO_CLUSTER, help="Kusto cluster URL")
    parser.add_argument("--db", default=DEFAULT_KUSTO_DB, help="Kusto database")
    parser.add_argument("--update", action="store_true",
                        help="Incremental mode: query only delta since last run, merge with cached signals")
    parser.add_argument("--diff", action="store_true",
                        help="Show diff against previous snapshot in report")
    parser.add_argument("--decay", type=float, default=0.9,
                        help="Decay factor for old signals during merge (default: 0.9)")
    parser.add_argument("--history", action="store_true",
                        help="Save snapshot to history for trend tracking (auto-enabled with --update)")
    args = parser.parse_args()

    # --update implies --history and --diff
    if args.update:
        args.history = True
        args.diff = True

    print(f"🔍 Loading graph from {args.graph}...")
    graph = load_graph(args.graph)
    print(f"   {len(graph['nodes'])} nodes, {len(graph['edges'])} edges")

    test_count = sum(1 for n in graph["nodes"] if n.get("_is_test"))
    gen_count = sum(1 for n in graph["nodes"] if n.get("_is_generated"))
    print(f"   {test_count} test nodes (excluded), {gen_count} generated/framework nodes")

    # Load incremental state
    state = load_state(args.output)
    config = SERVICE_SIGNALS[args.service]
    signals: dict[str, dict[str, int]] = {}
    cached_signals_path = Path(args.output) / "signals.json"

    if args.signals_file:
        print(f"\n📁 Loading signals from {args.signals_file}...")
        with open(args.signals_file) as f:
            signals = json.load(f)
    elif args.skip_kusto:
        if cached_signals_path.exists():
            print(f"\n📁 Loading cached signals from {cached_signals_path}...")
            signals = json.loads(cached_signals_path.read_text())
        else:
            print("\n⏭️  Skipping Kusto queries (--skip-kusto)")
            print(f"   No cached signals found at {cached_signals_path}; continuing with empty signals")
    else:
        # Determine query window
        if args.update:
            time_expr, is_incremental = get_incremental_window(state, args.service, args.lookback)
            if is_incremental:
                print(f"\n📡 Incremental query (delta since last run)...")
                print(f"   Time filter: TIMESTAMP > {time_expr}")
            else:
                print(f"\n📡 First run — full query ({args.lookback} lookback)...")
                time_expr = None  # Use default ago() in queries
        else:
            time_expr = None
            print(f"\n📡 Querying Kusto ({args.lookback} lookback)...")

        query_start = datetime.now(timezone.utc)
        sf = config["service_filter"]

        delta_signals: dict[str, dict[str, int]] = {}

        if config.get("web_requests"):
            table_name = config.get("web_requests_table", DEFAULT_TABLES["web_requests"])
            print(f"   → {table_name} (endpoint hits)...")
            delta_signals["web_requests"] = query_web_requests(
                sf,
                args.lookback,
                time_expr,
                config=config,
                cluster=args.cluster,
                db=args.db,
            )
            print(f"     {len(delta_signals['web_requests'])} endpoints found")

        if config.get("details_log", True):
            table_name = config.get("details_table", DEFAULT_TABLES["details"])
            print(f"   → {table_name} (logger FQCNs)...")
            delta_signals["details_log"] = query_details_log_classes(
                sf,
                args.lookback,
                time_expr,
                config=config,
                cluster=args.cluster,
                db=args.db,
            )
            print(f"     {len(delta_signals['details_log'])} logger classes found")
        else:
            delta_signals["details_log"] = {}
            print("   → Details log (logger FQCNs) skipped for this service")

        if config.get("stack_traces", config.get("details_log", True)):
            table_name = config.get("details_table", DEFAULT_TABLES["details"])
            print(f"   → {table_name} (stack trace methods)...")
            delta_signals["stack_traces"] = query_stack_trace_methods(
                sf,
                args.lookback,
                time_expr,
                config=config,
                cluster=args.cluster,
                db=args.db,
            )
            print(f"     {len(delta_signals['stack_traces'])} stack frame methods found")
        else:
            delta_signals["stack_traces"] = {}
            print("   → Stack trace methods skipped for this service")

        if config.get("task_hosting"):
            table_name = config.get("task_hosting_table", DEFAULT_TABLES["task_events"])
            print(f"   → {table_name} (job executions)...")
            delta_signals["task_hosting"] = query_task_hosting(
                sf,
                args.lookback,
                time_expr,
                config=config,
                cluster=args.cluster,
                db=args.db,
            )
            print(f"     {len(delta_signals['task_hosting'])} task names found")

        # Merge with existing signals if incremental
        if args.update and is_incremental:
            existing_signals_path = Path(args.output) / "signals.json"
            if existing_signals_path.exists():
                print(f"\n🔄 Merging with cached signals (decay={args.decay})...")
                existing = json.loads(existing_signals_path.read_text())
                signals = merge_signals(existing, delta_signals, args.decay)
                # Show merge stats
                for src in signals:
                    old_count = len(existing.get(src, {}))
                    new_count = len(delta_signals.get(src, {}))
                    merged_count = len(signals[src])
                    print(f"   {src}: {old_count} cached + {new_count} new → {merged_count} merged")
            else:
                print("   No cached signals found — using delta as full signals")
                signals = delta_signals
        else:
            signals = delta_signals

        # Save merged signals
        signals_path = cached_signals_path
        signals_path.parent.mkdir(parents=True, exist_ok=True)
        signals_path.write_text(json.dumps(signals, indent=2))
        print(f"   💾 Signals cached to {signals_path}")

        # Update state with query timestamp
        if args.service not in state["services"]:
            state["services"][args.service] = {}
        state["services"][args.service]["last_query_utc"] = query_start.isoformat()
        state["services"][args.service]["last_lookback"] = args.lookback
        state["runs"].append({
            "service": args.service,
            "timestamp": query_start.isoformat(),
            "incremental": args.update and is_incremental,
            "lookback": args.lookback,
        })
        # Keep only last 50 runs in state
        state["runs"] = state["runs"][-50:]
        save_state(args.output, state)
        print(f"   📌 State saved (next --update will query from {query_start.isoformat()[:19]})")
    # Match signals to nodes
    print("\n🔗 Matching signals to graph nodes...")
    match_signals_to_nodes(graph, signals, args.service, config=config)
    matched = sum(1 for n in graph["nodes"] if n.get("_evidence"))
    print(f"   {matched} nodes matched with direct evidence")

    # Propagate heat
    print("🌊 Propagating heat through call edges (decay={}, max_depth={})...".format(
        EDGE_DECAY, MAX_PROPAGATION_DEPTH))
    propagate_heat(graph)
    propagated = sum(
        1 for n in graph["nodes"]
        if any(e["type"] == "propagated_call" for e in n.get("_evidence", []))
    )
    print(f"   {propagated} additional nodes warmed via propagation")

    # Classify
    print("\n📊 Classifying nodes...")
    classify_nodes(
        graph, args.hot_pct, args.cold_pct,
        is_scheduled=config.get("scheduled", False)
    )

    # Generate report
    heatmap_data = generate_report(
        graph,
        args.service,
        args.lookback,
        args.output,
        cluster=args.cluster,
        db=args.db,
    )

    # Save snapshot for history tracking
    if args.history:
        snapshot_path = save_snapshot(args.output, args.service, heatmap_data)
        print(f"📸 Snapshot saved to {snapshot_path}")

    # Generate diff against previous snapshot
    if args.diff:
        diff_lines = generate_diff_report(args.output, args.service, heatmap_data)
        if diff_lines:
            # Re-generate report with diff appended
            heatmap_data = generate_report(
                graph,
                args.service,
                args.lookback,
                args.output,
                diff_lines,
                cluster=args.cluster,
                db=args.db,
            )
            print("📈 Trend diff appended to report")
        else:
            print("📈 No previous snapshot found for diff (run again with --update to build history)")


if __name__ == "__main__":
    main()
