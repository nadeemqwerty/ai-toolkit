#!/usr/bin/env bash
# agency-workspace.sh — Git worktree isolation for parallel AI agent tasks (Linux/macOS)
#
# Usage:
#   source agency-workspace.sh          # Load functions
#   agency-new MyRepo fix-auth          # Create workspace
#   agency-list                         # List active workspaces  
#   agency-remove MyRepo fix-auth       # Clean up
#
# Concept: Each task gets its own git worktree, preventing parallel sessions
# from interfering with each other. Workspaces live at ~/repos/_worktrees/<repo>/<task>/

set -uo pipefail

# Check dependencies
for cmd in git jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Required command not found: $cmd"
        echo "   Install with: sudo apt install $cmd"
        exit 1
    fi
done

REPOS_ROOT="${HOME}/repos"
WORKTREE_ROOT="${REPOS_ROOT}/_worktrees"
REGISTRY="${HOME}/.copilot/workspace-registry.json"
DEFAULT_USER="${USER:-$(whoami)}"

# ── Helpers ──────────────────────────────────────────────────────────────

to_slug() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-60
}

ensure_registry() {
    local dir
    dir=$(dirname "$REGISTRY")
    [[ -d "$dir" ]] || mkdir -p "$dir"
    [[ -f "$REGISTRY" ]] || echo '[]' > "$REGISTRY"
}

# ── Public Functions ─────────────────────────────────────────────────────

agency-new() {
    local repo="${1:-}"
    local task="${2:-}"
    local branch="${3:-}"  # Optional: existing branch
    local base="${4:-origin/main}"

    if [[ -z "$repo" || -z "$task" ]]; then
        echo "Usage: agency-new <repo> <task> [branch] [base-ref]"
        echo "  repo:   Name of repo in ~/repos/"
        echo "  task:   Short task name (e.g., fix-auth)"
        echo "  branch: Existing branch to checkout (optional)"
        echo "  base:   Base ref for new branch (default: origin/main)"
        return 1
    fi

    local slug
    slug=$(to_slug "$task")
    local main_clone="${REPOS_ROOT}/${repo}"
    local wt_path="${WORKTREE_ROOT}/${repo}/${slug}"

    if [[ ! -d "${main_clone}/.git" ]]; then
        echo "❌ Repo not found: ${main_clone}"
        return 1
    fi

    if [[ -d "$wt_path" ]]; then
        echo "⚠️  Workspace already exists: $wt_path"
        echo "   Use: agency-remove $repo $task"
        return 0
    fi

    mkdir -p "${WORKTREE_ROOT}/${repo}"

    # Fetch latest
    echo "📡 Fetching latest..."
    git -C "$main_clone" fetch --prune --quiet 2>/dev/null || true

    if [[ -n "$branch" ]]; then
        echo "🌿 Creating worktree with existing branch: $branch"
        git -C "$main_clone" worktree add "$wt_path" "$branch" 2>&1
    else
        local auto_branch="users/${DEFAULT_USER}/${slug}"
        echo "🌱 Creating worktree with new branch: $auto_branch (from $base)"
        git -C "$main_clone" worktree add -b "$auto_branch" "$wt_path" "$base" 2>&1
    fi

    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to create worktree"
        return 1
    fi

    local actual_branch
    actual_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD)

    # Register — use jq --arg for safe JSON construction
    ensure_registry
    local tmp="${REGISTRY}.tmp"
    jq --arg repo "$repo" \
       --arg task "$slug" \
       --arg branch "$actual_branch" \
       --arg path "$wt_path" \
       --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + [{"repo": $repo, "task": $task, "branch": $branch, "path": $path, "created": $created}]' \
       "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"

    echo ""
    echo "✅ Workspace ready!"
    echo "   Path:   $wt_path"
    echo "   Branch: $actual_branch"
    echo ""
    echo "   cd '$wt_path'"
}

agency-list() {
    local filter="${1:-}"
    ensure_registry

    local count
    count=$(jq length "$REGISTRY")

    if [[ "$count" -eq 0 ]]; then
        echo "No active workspaces."
        return
    fi

    echo ""
    echo "Agency Workspaces"
    echo "────────────────────────────────────────────────────"

    jq -r '.[] | "\(.repo)/\(.task) | \(.branch) | \(.path) | \(.created)"' "$REGISTRY" | while IFS='|' read -r name branch path created; do
        name=$(echo "$name" | xargs)
        branch=$(echo "$branch" | xargs)
        path=$(echo "$path" | xargs)
        created=$(echo "$created" | xargs)

        if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
            continue
        fi

        local status="🟢"
        [[ ! -d "$path" ]] && status="🔴 (missing)"

        local dirty=""
        if [[ -d "$path" ]]; then
            local dirty_count
            dirty_count=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            [[ "$dirty_count" -gt 0 ]] && dirty=" [${dirty_count} dirty]"
        fi

        echo "${status} ${name}${dirty}"
        echo "   Branch:  ${branch}"
        echo "   Path:    ${path}"
        echo "   Created: ${created}"
        echo ""
    done
}

agency-remove() {
    local repo="${1:-}"
    local task="${2:-}"
    local force="${3:-}"

    if [[ -z "$repo" || -z "$task" ]]; then
        echo "Usage: agency-remove <repo> <task> [--force]"
        return 1
    fi

    local slug
    slug=$(to_slug "$task")
    local main_clone="${REPOS_ROOT}/${repo}"
    local wt_path="${WORKTREE_ROOT}/${repo}/${slug}"

    if [[ -d "$wt_path" ]]; then
        # Check dirty state
        if [[ "$force" != "--force" ]]; then
            local dirty
            dirty=$(git -C "$wt_path" status --porcelain 2>/dev/null)
            if [[ -n "$dirty" ]]; then
                echo "⚠️  Worktree has uncommitted changes:"
                echo "$dirty" | head -10
                echo ""
                echo "Use: agency-remove $repo $task --force"
                return 1
            fi
        fi

        echo "🗑  Removing worktree: $wt_path"
        if [[ "$force" == "--force" ]]; then
            git -C "$main_clone" worktree remove "$wt_path" --force 2>&1
        else
            git -C "$main_clone" worktree remove "$wt_path" 2>&1
        fi
    fi

    # Deregister
    ensure_registry
    local tmp="${REGISTRY}.tmp"
    jq "[ .[] | select(.repo != \"${repo}\" or .task != \"${slug}\") ]" "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"

    # Prune
    git -C "$main_clone" worktree prune 2>/dev/null || true

    echo "✅ Workspace removed: ${repo}/${slug}"
}

# Export for interactive use
export -f agency-new agency-list agency-remove 2>/dev/null || true
