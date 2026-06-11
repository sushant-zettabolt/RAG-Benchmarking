#!/usr/bin/env bash
# Common helpers — source this from every script; do not execute directly.
# Resolves BASE (repo root), loads config.env, exports derived vars.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(dirname "$LIB_DIR")"
export BASE

if [ -f "$BASE/config.env" ]; then
    set -a; . "$BASE/config.env"; set +a
else
    echo "WARN: $BASE/config.env not found — using defaults from config.env.example" >&2
    set -a; . "$BASE/config.env.example"; set +a
fi

RESULTS_DIR="$BASE/results"
export RESULTS_DIR
mkdir -p "$RESULTS_DIR"

# URLs derived from ports — harness.py / ingest.py read these from the env
export ALLM_URL="http://127.0.0.1:${ALLM_PORT}"
export PROM_URL="http://127.0.0.1:${PROM_PORT}"

log()  { echo "[$(basename "$0")] $*"; }
die()  { echo "[$(basename "$0")] ERROR: $*" >&2; exit 1; }

# Render conf/*.tpl -> conf/* substituting only whitelisted variables
render_conf() {
    local vars='${CHAT_PORT} ${EMBED_PORT} ${LITELLM_PORT} ${PROM_PORT} ${ALLM_PORT} ${LITELLM_MASTER_KEY} ${CHAT_CTX}'
    local f
    for f in "$BASE"/conf/*.tpl; do
        envsubst "$vars" < "$f" > "${f%.tpl}"
    done
}

# wait_http <url> <timeout_sec> [grep_pattern] — poll until 200/match or timeout
wait_http() {
    local url="$1" timeout="$2" pat="${3:-}" i out
    for i in $(seq 1 "$((timeout / 5))"); do
        sleep 5
        out=$(curl -s -m 10 "$url" 2>/dev/null) || continue
        if [ -z "$pat" ] || echo "$out" | grep -q "$pat"; then
            return 0
        fi
    done
    return 1
}

# kill_pidfile <file> — stop a previously started process, ignore errors
kill_pidfile() {
    if [ -f "$1" ]; then
        kill "$(cat "$1")" 2>/dev/null || true
        rm -f "$1"
    fi
}
