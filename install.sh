#!/usr/bin/env bash
# install.sh — One-command AI Toolkit installer for Linux/macOS
#
# Usage:
#   ./install.sh                  # Interactive
#   ./install.sh --preset all     # Install everything
#   ./install.sh --preset reliability
#   ./install.sh --dry-run        # Preview only

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COPILOT_ROOT="${HOME}/.copilot"
AGENTS_TARGET="${COPILOT_ROOT}/agents"
SKILLS_TARGET="${COPILOT_ROOT}/skills"
KNOWLEDGE_TARGET="${COPILOT_ROOT}/knowledge"

AGENT_SOURCE_ROOT="${SCRIPT_DIR}/agents"
SKILL_SOURCE_ROOT="${SCRIPT_DIR}/skills"
KNOWLEDGE_SOURCE_ROOT="${SCRIPT_DIR}/knowledge-templates"

PRESET=""
DRY_RUN=0
CONFLICT_MODE=""
DIRECTORIES_CREATED=0
COPIED_COUNT=0
OVERWRITTEN_COUNT=0
SKIPPED_COUNT=0
PLANNED_COUNT=0

ALL_AGENTS=()
ALL_SKILLS=()
KNOWLEDGE_FILES=()
SELECTED_AGENTS=()
SELECTED_SKILLS=()
SELECTED_PRESET=""

COLOR_RESET='\033[0m'
COLOR_CYAN='\033[36m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_RED='\033[31m'
COLOR_MAGENTA='\033[35m'

info() {
    printf "%bℹ️  %s%b\n" "$COLOR_CYAN" "$1" "$COLOR_RESET"
}

success() {
    printf "%b✅ %s%b\n" "$COLOR_GREEN" "$1" "$COLOR_RESET"
}

warn() {
    printf "%b⚠️  %s%b\n" "$COLOR_YELLOW" "$1" "$COLOR_RESET"
}

error_line() {
    printf "%b❌ %s%b\n" "$COLOR_RED" "$1" "$COLOR_RESET" >&2
}

header() {
    printf "\n%b🧰 AI Toolkit Installer (Bash)%b\n" "$COLOR_MAGENTA" "$COLOR_RESET"
    printf "%b===============================%b\n" "$COLOR_MAGENTA" "$COLOR_RESET"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "Dry run mode enabled — no files will be copied."
    fi
}

usage() {
    cat <<'EOF'
Usage:
  ./install.sh                  # Interactive
  ./install.sh --preset all     # Install everything
  ./install.sh --preset reliability
  ./install.sh --dry-run        # Preview only
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset)
                if [[ $# -lt 2 ]]; then
                    error_line "--preset requires a value"
                    exit 1
                fi
                PRESET="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_line "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

load_catalog() {
    local path base

    shopt -s nullglob
    for path in "${AGENT_SOURCE_ROOT}"/*.md; do
        base="$(basename "$path")"
        [[ "$base" == "README.md" ]] && continue
        ALL_AGENTS+=("$base")
    done

    for path in "${SKILL_SOURCE_ROOT}"/*; do
        [[ -d "$path" ]] || continue
        ALL_SKILLS+=("$(basename "$path")")
    done

    for path in "${KNOWLEDGE_SOURCE_ROOT}"/*.md; do
        base="$(basename "$path")"
        [[ "$base" == "README.md" ]] && continue
        KNOWLEDGE_FILES+=("$base")
    done
    shopt -u nullglob

    mapfile -t ALL_AGENTS < <(printf '%s\n' "${ALL_AGENTS[@]}" | sort)
    mapfile -t ALL_SKILLS < <(printf '%s\n' "${ALL_SKILLS[@]}" | sort)
    mapfile -t KNOWLEDGE_FILES < <(printf '%s\n' "${KNOWLEDGE_FILES[@]}" | sort)
}

join_by() {
    local separator="$1"
    shift || true
    if [[ $# -eq 0 ]]; then
        printf 'none'
        return
    fi
    local first=1
    local item
    for item in "$@"; do
        if [[ $first -eq 1 ]]; then
            printf '%s' "$item"
            first=0
        else
            printf '%s%s' "$separator" "$item"
        fi
    done
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

read_interactive_preset() {
    while true; do
        printf "\n%bChoose an install preset:%b\n" "$COLOR_CYAN" "$COLOR_RESET"
        printf "  1) reliability   — evidence-driven + architect-first + critic\n"
        printf "  2) productivity  — cross-session-planner + flow-discovery + agent-output-contract\n"
        printf "  3) all           — every available agent and skill\n"
        printf "  4) custom        — choose agents and skills individually\n"
        read -r -p "Enter 1, 2, 3, or 4: " choice
        case "${choice}" in
            1) PRESET='reliability'; return ;;
            2) PRESET='productivity'; return ;;
            3) PRESET='all'; return ;;
            4) PRESET='custom'; return ;;
            *) warn "Invalid selection. Please try again." ;;
        esac
    done
}

select_custom_items() {
    local output_var="$1"
    local label="$2"
    shift 2
    local item answer lowered

    case "$output_var" in
        SELECTED_AGENTS) SELECTED_AGENTS=() ;;
        SELECTED_SKILLS) SELECTED_SKILLS=() ;;
        *) error_line "Unsupported output array: $output_var" ;;
    esac

    for item in "$@"; do
        while true; do
            read -r -p "Install ${label} '${item}'? [y/N] " answer
            lowered="$(to_lower "$answer")"
            if [[ -z "$lowered" || "$lowered" == "n" || "$lowered" == "no" ]]; then
                break
            fi
            if [[ "$lowered" == "y" || "$lowered" == "yes" ]]; then
                case "$output_var" in
                    SELECTED_AGENTS) SELECTED_AGENTS+=("$item") ;;
                    SELECTED_SKILLS) SELECTED_SKILLS+=("$item") ;;
                esac
                break
            fi
            warn "Please answer y or n."
        done
    done
}

resolve_selection() {
    local chosen
    chosen="$PRESET"
    if [[ -z "$chosen" ]]; then
        read_interactive_preset
        chosen="$PRESET"
    fi

    case "$chosen" in
        reliability)
            SELECTED_PRESET='reliability'
            SELECTED_AGENTS=('critic.md')
            SELECTED_SKILLS=('evidence-driven' 'architect-first')
            ;;
        productivity)
            SELECTED_PRESET='productivity'
            SELECTED_AGENTS=()
            SELECTED_SKILLS=('cross-session-planner' 'flow-discovery' 'agent-output-contract')
            ;;
        all)
            SELECTED_PRESET='all'
            SELECTED_AGENTS=("${ALL_AGENTS[@]}")
            SELECTED_SKILLS=("${ALL_SKILLS[@]}")
            ;;
        custom)
            SELECTED_PRESET='custom'
            select_custom_items SELECTED_AGENTS 'agent' "${ALL_AGENTS[@]}"
            select_custom_items SELECTED_SKILLS 'skill' "${ALL_SKILLS[@]}"
            ;;
        *)
            error_line "Invalid preset: $chosen"
            exit 1
            ;;
    esac
}

assert_sources_exist() {
    local missing=0 item path

    for item in "${SELECTED_AGENTS[@]}"; do
        path="${AGENT_SOURCE_ROOT}/${item}"
        if [[ ! -e "$path" ]]; then
            error_line "Missing source item: $path"
            missing=1
        fi
    done

    for item in "${SELECTED_SKILLS[@]}"; do
        path="${SKILL_SOURCE_ROOT}/${item}"
        if [[ ! -e "$path" ]]; then
            error_line "Missing source item: $path"
            missing=1
        fi
    done

    for item in "${KNOWLEDGE_FILES[@]}"; do
        path="${KNOWLEDGE_SOURCE_ROOT}/${item}"
        if [[ ! -e "$path" ]]; then
            error_line "Missing source item: $path"
            missing=1
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        exit 1
    fi
}

ensure_dir() {
    local path="$1"
    if [[ -d "$path" ]]; then
        return
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "Would create directory: $path"
        ((PLANNED_COUNT+=1))
        return
    fi

    mkdir -p "$path"
    ((DIRECTORIES_CREATED+=1))
    success "Created directory: $path"
}

get_conflict_decision() {
    local destination="$1"
    local answer

    if [[ "$CONFLICT_MODE" == "overwrite-all" ]]; then
        printf 'overwrite'
        return
    fi
    if [[ "$CONFLICT_MODE" == "skip-all" ]]; then
        printf 'skip'
        return
    fi

    while true; do
        read -r -p "⚠️  '${destination}' already exists. [o]verwrite, [s]kip, overwrite [a]ll, skip [n]all: " answer
        answer="$(to_lower "$answer")"
        case "$answer" in
            o|overwrite)
                printf 'overwrite'
                return
                ;;
            s|skip)
                printf 'skip'
                return
                ;;
            a|all)
                CONFLICT_MODE='overwrite-all'
                printf 'overwrite'
                return
                ;;
            n|none)
                CONFLICT_MODE='skip-all'
                printf 'skip'
                return
                ;;
            *)
                warn "Please choose o, s, a, or n."
                ;;
        esac
    done
}

install_item() {
    local source="$1"
    local destination="$2"
    local item_type="$3"
    local label="$4"
    local action='copy'

    if [[ -e "$destination" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "Would overwrite ${label}: ${destination}"
            ((PLANNED_COUNT+=1))
            return
        fi

        local decision
        decision="$(get_conflict_decision "$destination")"
        if [[ "$decision" == 'skip' ]]; then
            ((SKIPPED_COUNT+=1))
            warn "Skipped ${label}: ${destination}"
            return
        fi
        action='overwrite'
    elif [[ "$DRY_RUN" -eq 1 ]]; then
        info "Would install ${label}: ${destination}"
        ((PLANNED_COUNT+=1))
        return
    fi

    ensure_dir "$(dirname "$destination")"

    if [[ "$item_type" == 'directory' ]]; then
        rm -rf "$destination"
        cp -R "$source" "$destination"
    else
        cp "$source" "$destination"
    fi

    if [[ "$action" == 'overwrite' ]]; then
        ((OVERWRITTEN_COUNT+=1))
        success "Overwrote ${label}: ${destination}"
    else
        ((COPIED_COUNT+=1))
        success "Installed ${label}: ${destination}"
    fi
}

validate_installation() {
    local failed=0 item path

    if [[ "$DRY_RUN" -eq 1 ]]; then
        success 'Dry-run validation passed — all source items are available and target paths were resolved.'
        return 0
    fi

    for item in "${SELECTED_AGENTS[@]}"; do
        path="${AGENTS_TARGET}/${item}"
        if [[ ! -e "$path" ]]; then
            error_line "Missing installed item: $path"
            failed=1
        fi
    done

    for item in "${SELECTED_SKILLS[@]}"; do
        path="${SKILLS_TARGET}/${item}/SKILL.md"
        if [[ ! -e "$path" ]]; then
            error_line "Missing installed item: $path"
            failed=1
        fi
    done

    for item in "${KNOWLEDGE_FILES[@]}"; do
        path="${KNOWLEDGE_TARGET}/${item}"
        if [[ ! -e "$path" ]]; then
            error_line "Missing installed item: $path"
            failed=1
        fi
    done

    if [[ "$failed" -ne 0 ]]; then
        return 1
    fi

    success 'Installation validation passed.'
}

show_summary() {
    printf "\n%b📦 Summary%b\n" "$COLOR_MAGENTA" "$COLOR_RESET"
    printf "%b----------%b\n" "$COLOR_MAGENTA" "$COLOR_RESET"
    printf "Preset:      %s\n" "$SELECTED_PRESET"
    printf "Agents:      %s\n" "$(join_by ', ' "${SELECTED_AGENTS[@]}")"
    printf "Skills:      %s\n" "$(join_by ', ' "${SELECTED_SKILLS[@]}")"
    printf "Knowledge:   %s\n" "$(join_by ', ' "${KNOWLEDGE_FILES[@]}")"
    printf "Created:     %s directories\n" "$DIRECTORIES_CREATED"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "Planned:     %s actions\n\n" "$PLANNED_COUNT"
    else
        printf "Copied:      %s\n" "$COPIED_COUNT"
        printf "Overwritten: %s\n" "$OVERWRITTEN_COUNT"
        printf "Skipped:     %s\n\n" "$SKIPPED_COUNT"
    fi
}

parse_args "$@"
load_catalog
header
resolve_selection

info "Selected preset: ${SELECTED_PRESET}"
info "Agents to install: $(join_by ', ' "${SELECTED_AGENTS[@]}")"
info "Skills to install: $(join_by ', ' "${SELECTED_SKILLS[@]}")"
info "Knowledge templates: $(join_by ', ' "${KNOWLEDGE_FILES[@]}")"

assert_sources_exist

ensure_dir "$COPILOT_ROOT"
ensure_dir "$AGENTS_TARGET"
ensure_dir "$SKILLS_TARGET"
ensure_dir "$KNOWLEDGE_TARGET"

for item in "${SELECTED_AGENTS[@]}"; do
    install_item "${AGENT_SOURCE_ROOT}/${item}" "${AGENTS_TARGET}/${item}" 'file' "agent '${item}'"
done

for item in "${SELECTED_SKILLS[@]}"; do
    install_item "${SKILL_SOURCE_ROOT}/${item}" "${SKILLS_TARGET}/${item}" 'directory' "skill '${item}'"
done

for item in "${KNOWLEDGE_FILES[@]}"; do
    install_item "${KNOWLEDGE_SOURCE_ROOT}/${item}" "${KNOWLEDGE_TARGET}/${item}" 'file' "knowledge template '${item}'"
done

validate_installation
show_summary
success 'Installer completed successfully.'
