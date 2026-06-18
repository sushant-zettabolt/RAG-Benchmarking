#!/usr/bin/env bash
# Thin convenience wrapper around `docker compose up -d`.
#   ./setup.sh
# Validates that your model GGUFs exist, then brings up the full stack. The FIRST
# run compiles llama.cpp from public source (GGML_ZENDNN=OFF -> nqrag-llama:baseline)
# and builds the harness image — this takes several minutes. Subsequent runs reuse
# the cached images. The one-shot `seed` service auto-configures AnythingLLM, so
# running this is optional — `docker compose up -d` does the same thing.
# Host requirements: docker + docker compose. Nothing else.
set -euo pipefail
cd "$(dirname "$0")"

DC="docker compose"

# ── .env ─────────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
    cp .env.example .env
    echo "[setup] created .env from .env.example — edit MODELS_DIR + model paths, then re-run"
fi

env_get() {  # env_get KEY DEFAULT
    local v
    v="$(grep -E "^$1=" .env | head -1 | cut -d= -f2-)"
    if [ -z "$v" ]; then echo "$2"; else echo "$v"; fi
}

CHAT_PORT="$(env_get CHAT_PORT 8081)"
EMBED_PORT="$(env_get EMBED_PORT 8082)"
LITELLM_PORT="$(env_get LITELLM_PORT 4000)"
PROM_PORT="$(env_get PROM_PORT 9090)"
ALLM_PORT="$(env_get ALLM_PORT 3001)"
GRAFANA_PORT="$(env_get GRAFANA_PORT 3000)"

# ── models must be supplied locally (nothing is downloaded) ──────────────────
MODELS_DIR="$(env_get MODELS_DIR ./models)"
CHAT_MODEL_PATH="$(env_get CHAT_MODEL_PATH '')"
EMBED_MODEL_PATH="$(env_get EMBED_MODEL_PATH '')"
check_model() {  # check_model VARNAME CONTAINER_PATH
    local var="$1" cpath="$2"
    if [ -z "$cpath" ]; then
        echo "[setup] ERROR: $var is empty in .env. Set it to your GGUF path under /models (e.g. /models/model.gguf)." >&2; exit 1
    fi
    # map the in-container /models path back to the host MODELS_DIR to verify it exists
    local host="${MODELS_DIR%/}/${cpath#/models/}"
    if [ ! -f "$host" ]; then
        echo "[setup] ERROR: $var=$cpath not found on host at '$host'. Put the GGUF in MODELS_DIR ($MODELS_DIR) or fix the path." >&2; exit 1
    fi
}
check_model CHAT_MODEL_PATH "$CHAT_MODEL_PATH"
check_model EMBED_MODEL_PATH "$EMBED_MODEL_PATH"

wait_for() {  # wait_for NAME URL TRIES
    local name="$1" url="$2" tries="${3:-60}"
    echo -n "[setup] waiting for $name "
    for i in $(seq 1 "$tries"); do
        if curl -fsS -m 5 "$url" >/dev/null 2>&1; then echo " up"; return 0; fi
        echo -n "."; sleep 5
    done
    echo " TIMEOUT"; return 1
}

# ── bring up the full stack ──────────────────────────────────────────────────
# Builds nqrag-llama:baseline + the harness image on first run, pulls the public
# images (litellm/prometheus/grafana/anythingllm/pushgateway), and starts the
# one-shot `seed` service which configures AnythingLLM once it is healthy.
echo "[setup] bringing up the stack (first run compiles llama.cpp — minutes) ..."
$DC up -d

# llama servers need a moment to load the mounted model into memory
wait_for "llama-chat"  "http://localhost:${CHAT_PORT}/health"  240 || { $DC logs --tail 40 llama-chat; exit 1; }
wait_for "llama-embed" "http://localhost:${EMBED_PORT}/health" 120 || { $DC logs --tail 40 llama-embed; exit 1; }
wait_for "litellm"     "http://localhost:${LITELLM_PORT}/health/liveliness" 60 || { $DC logs --tail 40 litellm; exit 1; }
wait_for "anythingllm" "http://localhost:${ALLM_PORT}/api/ping" 60 || { $DC logs --tail 40 anythingllm; exit 1; }

# ── wait for the seed service to finish configuring AnythingLLM ───────────────
echo "[setup] waiting for the seed service to configure AnythingLLM ..."
if seed_rc="$(docker wait nqrag-seed 2>/dev/null)"; then
    if [ "$seed_rc" != "0" ]; then
        echo "[setup] ERROR: seed service exited $seed_rc:" >&2
        $DC logs --tail 40 seed >&2
        exit 1
    fi
    echo "[setup] AnythingLLM seeded."
else
    echo "[setup] WARNING: could not inspect the seed container; check 'docker compose logs seed'." >&2
fi

cat <<EOF

[setup] ✅ stack is up.
  llama-chat   http://localhost:${CHAT_PORT}
  llama-embed  http://localhost:${EMBED_PORT}
  litellm      http://localhost:${LITELLM_PORT}
  prometheus   http://localhost:${PROM_PORT}
  grafana      http://localhost:${GRAFANA_PORT}
  anythingllm  http://localhost:${ALLM_PORT}

Next:
  make ingest     # download Google NQ + ingest documents into AnythingLLM
  make evaluate   # run queries + LLM-judge
  make report     # generate results/report.md + report.json
  ./run_ab.sh     # build the zendnn image + run baseline-vs-zendnn A/B
EOF
