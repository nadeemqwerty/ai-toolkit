#!/usr/bin/env bash
# workspace-status.sh — Multi-repo workspace dashboard (Linux/macOS)
#
# Usage:
#   ./workspace-status.sh              # All repos
#   ./workspace-status.sh MyRepo       # Single repo
#   ./workspace-status.sh MyRepo -d    # Detailed (show dirty files)

set -euo pipefail

REPO_ROOT="${HOME}/repos"
FILTER="${1:-}"
DETAILED="${2:-}"

# Define your repos here
REPOS=(
    "backend-api:Java"
    "frontend-app:TypeScript"
    "data-pipeline:Python"
    "infra:Terraform"
    "docs:Markdown"
)

printf "\n\033[36m📊 WORKSPACE STATUS\033[0m\n"
printf "\033[36m━━━━━━━━━━━━━━━━━━━\033[0m\n\n"
printf "%-20s %-30s %-15s %-8s %s\n" "REPO" "BRANCH" "DIRTY" "STASH" "LAST COMMIT"
printf "%-20s %-30s %-15s %-8s %s\n" "----" "------" "-----" "-----" "-----------"

DIRTY_REPOS=()

for entry in "${REPOS[@]}"; do
    # shellcheck disable=SC2034
    IFS=':' read -r name lang <<< "$entry"
    
    # Filter if specified
    if [[ -n "$FILTER" && "$FILTER" != "-d" && "$name" != *"$FILTER"* ]]; then
        continue
    fi

    path="${REPO_ROOT}/${name}"
    
    if [[ ! -d "${path}/.git" ]]; then
        printf "%-20s %-30s %-15s %-8s %s\n" "$name" "NOT CLONED" "—" "—" "—"
        continue
    fi

    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    stashes=$(git -C "$path" stash list 2>/dev/null | wc -l | tr -d ' ')
    last_commit=$(git -C "$path" log -1 --format="%ar | %s" 2>/dev/null | head -c 50)

    if [[ "$dirty" -gt 0 ]]; then
        dirty_label="⚠️  ${dirty} files"
        DIRTY_REPOS+=("$name ($branch)")
    else
        dirty_label="✅ clean"
    fi

    stash_label="${stashes}"
    [[ "$stashes" -gt 0 ]] && stash_label="📦 ${stashes}"

    printf "%-20s %-30s %-15s %-8s %s\n" "$name" "$branch" "$dirty_label" "$stash_label" "$last_commit"

    if [[ "$DETAILED" == "-d" && "$dirty" -gt 0 ]]; then
        echo "  Dirty files:"
        git -C "$path" status --porcelain | sed 's/^/    /'
    fi
done

echo ""

if [[ ${#DIRTY_REPOS[@]} -gt 0 ]]; then
    printf "\033[33m⚠️  DIRTY REPOS (uncommitted changes):\033[0m\n"
    for r in "${DIRTY_REPOS[@]}"; do
        printf "\033[33m   - %s\033[0m\n" "$r"
    done
    echo ""
fi
