#!/usr/bin/env bash
# switch-java.sh — Switch between Java versions (Linux/macOS)
# IMPORTANT: This script must be sourced, not executed:
#   source ./switch-java.sh 17
#
# Usage:
#   ./switch-java.sh 8    # Switch to Java 8
#   ./switch-java.sh 17   # Switch to Java 17
#   ./switch-java.sh 21   # Switch to Java 21
#
# Prerequisites: Install JDKs via sdkman, apt, or manual download
# Customize JAVA_PATHS below for your installation locations.

set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: switch-java.sh <version>"
    echo "Available: 8, 11, 17, 21"
    exit 1
fi

# ── Customize these paths for your system ──────────────────────────────
# Common locations by install method:
#   sdkman:  ~/.sdkman/candidates/java/<version>
#   apt:     /usr/lib/jvm/java-<version>-openjdk-amd64
#   manual:  /opt/java/jdk-<version>

declare -A JAVA_PATHS=(
    [8]="/usr/lib/jvm/java-8-openjdk-amd64"
    [11]="/usr/lib/jvm/java-11-openjdk-amd64"
    [17]="/usr/lib/jvm/java-17-openjdk-amd64"
    [21]="/usr/lib/jvm/java-21-openjdk-amd64"
)

# sdkman override (if installed)
if [[ -d "${HOME}/.sdkman/candidates/java" ]]; then
    for v in "${!JAVA_PATHS[@]}"; do
        sdk_path=$(find "${HOME}/.sdkman/candidates/java" -maxdepth 1 -name "${v}*" -type d 2>/dev/null | head -1)
        [[ -n "$sdk_path" ]] && JAVA_PATHS[$v]="$sdk_path"
    done
fi
# ───────────────────────────────────────────────────────────────────────

JAVA_HOME="${JAVA_PATHS[$VERSION]:-}"

if [[ -z "$JAVA_HOME" ]]; then
    echo "❌ Java $VERSION not configured. Edit JAVA_PATHS in this script."
    echo "Available versions: ${!JAVA_PATHS[*]}"
    exit 1
fi

if [[ ! -d "$JAVA_HOME" ]]; then
    echo "❌ Java $VERSION not found at: $JAVA_HOME"
    echo "Install it or update the path in this script."
    exit 1
fi

# Remove any existing Java from PATH
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "java\|jdk\|jre" | tr '\n' ':' | sed 's/:$//')

export JAVA_HOME
export PATH="${JAVA_HOME}/bin:${CLEAN_PATH}"

echo "✅ Switched to Java $VERSION"
java -version 2>&1 | head -1

# Persist for new shells (optional — uncomment your preferred method)
# echo "export JAVA_HOME=$JAVA_HOME" > ~/.java_env && echo "source ~/.java_env in your .bashrc"

cat << 'EOF'

To persist across new terminals, add to ~/.bashrc or ~/.zshrc:
  source ~/bin/switch-java.sh <version>
Or add this line:
  export JAVA_HOME=/path/to/jdk && export PATH="$JAVA_HOME/bin:$PATH"
EOF
