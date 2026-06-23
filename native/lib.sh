#!/usr/bin/env bash
# Shared helpers for the native (no-Docker) stack: config loading, PATH wiring to
# the local toolchains, and PID/log-based process management. Sourced by every
# native/*.sh script. No Docker, no sudo, no systemd — services are plain
# background processes tracked by a pidfile under $RUN and a log under $LOGS.

# Resolve repo root + native dir from THIS file's location (works from anywhere).
NATIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$NATIVE/.." && pwd)"
export BASE NATIVE

CONFIG="${NATIVE}/config.env"
if [ ! -f "$CONFIG" ]; then
    echo "[native] ERROR: $CONFIG not found — run: cp native/config.env.example native/config.env" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$CONFIG"

# Local toolchains first on PATH (node), then pip --user bin (litellm), then system.
export PATH="${RUNTIME}/node/bin:${HOME}/.local/bin:${PATH}"

# The harness (src/*.py) runs in an ISOLATED venv with pinned deps — datasets 3.2.0
# + huggingface_hub 0.27.0 (so the legacy NQ datasets, which are load-script based,
# still load; newer datasets/hub reject the bare `nq_open` repo id) and lancedb
# 0.15.0 (table format AnythingLLM reads). Never relies on the host's --user packages.
# Falls back to system python3 only before setup has created the venv.
HARNESS_PY="${RUNTIME}/venv/bin/python"
[ -x "$HARNESS_PY" ] || HARNESS_PY="python3"
export HARNESS_PY

mkdir -p "$RUN" "$LOGS" "$DATA"

log()  { echo "[native $(date '+%H:%M:%S')] $*"; }
die()  { echo "[native] ERROR: $*" >&2; exit 1; }

pidfile() { echo "${RUN}/$1.pid"; }
logfile() { echo "${LOGS}/$1.log"; }

is_running() {  # name
    local pf; pf="$(pidfile "$1")"
    [ -f "$pf" ] || return 1
    local pid; pid="$(cat "$pf" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Start a service in the background, in its OWN process group (setsid) so the
# whole tree dies cleanly on stop. Caller passes a full shell command string and
# should `exec` the final binary (so the tracked pid is the service); compound
# commands like `cd DIR && exec node ...` are fine. Killing the group on stop
# means teardown is correct even without exec.
start_bg() {  # name "command string"
    local name="$1" cmd="$2" pf lf
    pf="$(pidfile "$name")"; lf="$(logfile "$name")"
    if is_running "$name"; then log "$name already running (pid $(cat "$pf"))"; return 0; fi
    : > "$lf"
    setsid bash -c "$cmd" >>"$lf" 2>&1 &
    echo $! > "$pf"
    log "started $name (pid $!) → ${lf#$BASE/}"
}

# Kill a pid's whole process group (then the pid), best-effort.
stop_bg() {  # name
    local name="$1" pf pid; pf="$(pidfile "$name")"
    [ -f "$pf" ] || { return 0; }
    pid="$(cat "$pf" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
        kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        log "stopped $name (pid $pid)"
    fi
    rm -f "$pf"
}

wait_http() {  # label url [tries] [delay]
    local label="$1" url="$2" tries="${3:-120}" delay="${4:-2}"
    printf '[native] waiting for %s ' "$label"
    for _ in $(seq 1 "$tries"); do
        if curl -fsS -m 5 "$url" >/dev/null 2>&1; then echo " up"; return 0; fi
        printf '.'; sleep "$delay"
    done
    echo " TIMEOUT"; return 1
}

# numactl prefix for a llama server, or empty if pinning is unavailable/disabled.
numa_prefix() {  # cpus membind
    local cpus="$1" mem="$2"
    [ -n "$cpus" ] || { echo ""; return; }
    command -v numactl >/dev/null 2>&1 || { echo ""; return; }
    if [ -n "$mem" ]; then echo "numactl --physcpubind=$cpus --membind=$mem";
    else echo "numactl --physcpubind=$cpus"; fi
}

ALLM_STORAGE="${RUNTIME}/anythingllm/server/storage"
ALLM_DB="${ALLM_STORAGE}/anythingllm.db"
