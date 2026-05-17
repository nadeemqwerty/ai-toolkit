#!/usr/bin/env bash
# start-port-forward.sh — Auto-reconnecting kubectl port-forward (Linux/macOS)
#
# Usage:
#   ./start-port-forward.sh -s my-service -n my-namespace -l 8080 [-r 80] [-c my-context] [-d 3]
#
# Options:
#   -s  Service name (required)
#   -n  Namespace (required)
#   -l  Local port (required)
#   -r  Remote port (defaults to local port)
#   -c  kubectl context (defaults to current context)
#   -d  Retry delay in seconds (default: 3)

set -uo pipefail

# Parse arguments
SERVICE=""
NAMESPACE=""
LOCAL_PORT=""
REMOTE_PORT=""
CONTEXT=""
RETRY_DELAY=3

while getopts "s:n:l:r:c:d:" opt; do
    case $opt in
        s) SERVICE="$OPTARG" ;;
        n) NAMESPACE="$OPTARG" ;;
        l) LOCAL_PORT="$OPTARG" ;;
        r) REMOTE_PORT="$OPTARG" ;;
        c) CONTEXT="$OPTARG" ;;
        d) RETRY_DELAY="$OPTARG" ;;
        *) echo "Usage: $0 -s service -n namespace -l local_port [-r remote_port] [-c context] [-d delay]"; exit 1 ;;
    esac
done

if [[ -z "$SERVICE" || -z "$NAMESPACE" || -z "$LOCAL_PORT" ]]; then
    echo "Error: -s (service), -n (namespace), and -l (local port) are required."
    echo "Usage: $0 -s my-service -n my-namespace -l 8080"
    exit 1
fi

[[ -z "$REMOTE_PORT" ]] && REMOTE_PORT="$LOCAL_PORT"

CONTEXT_FLAG=""
[[ -n "$CONTEXT" ]] && CONTEXT_FLAG="--context $CONTEXT"

ATTEMPT=0

cleanup() {
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Port-forward stopped by user."
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "🔌 Port-forward: localhost:${LOCAL_PORT} → svc/${SERVICE}:${REMOTE_PORT} (ns=${NAMESPACE})"
echo "   Press Ctrl+C to stop"
echo ""

while true; do
    ATTEMPT=$((ATTEMPT + 1))
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TS] Attempt #${ATTEMPT} — connecting..."

    # shellcheck disable=SC2086
    kubectl port-forward "svc/${SERVICE}" "${LOCAL_PORT}:${REMOTE_PORT}" \
        -n "$NAMESPACE" $CONTEXT_FLAG 2>&1

    TS=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TS] Connection dropped (exit $?). Reconnecting in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
done
