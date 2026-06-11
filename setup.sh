#!/usr/bin/env bash
# One-shot bring-up for the containerized RAG eval stack.
#   ./setup.sh
# Starts the 5 serving containers, waits for them to be healthy, generates an
# AnythingLLM API key if needed, and seeds AnythingLLM's provider settings.
# Host requirements: docker + docker compose. Nothing else.
set -euo pipefail
cd "$(dirname "$0")"

DC="docker compose"

# ── .env ─────────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
    cp .env.example .env
    echo "[setup] created .env from .env.example"
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
MASTER_KEY="$(env_get LITELLM_MASTER_KEY sk-bench-master)"
CHAT_CTX="$(env_get CHAT_CTX 8192)"
ALLM_KEY="$(env_get ALLM_KEY '')"

# ── generate AnythingLLM API key if empty ────────────────────────────────────
if [ -z "$ALLM_KEY" ]; then
    ALLM_KEY="nqrag-$(openssl rand -hex 16)"
    if grep -qE '^ALLM_KEY=' .env; then
        sed -i "s|^ALLM_KEY=.*|ALLM_KEY=${ALLM_KEY}|" .env
    else
        echo "ALLM_KEY=${ALLM_KEY}" >> .env
    fi
    echo "[setup] generated ALLM_KEY and saved to .env"
fi

wait_for() {  # wait_for NAME URL TRIES
    local name="$1" url="$2" tries="${3:-60}"
    echo -n "[setup] waiting for $name "
    for i in $(seq 1 "$tries"); do
        if curl -fsS -m 5 "$url" >/dev/null 2>&1; then echo " up"; return 0; fi
        echo -n "."; sleep 5
    done
    echo " TIMEOUT"; return 1
}

# ── bring up serving containers ──────────────────────────────────────────────
echo "[setup] starting containers (first run downloads models — be patient) ..."
$DC up -d llama-chat llama-embed litellm prometheus anythingllm

# llama servers can take a while on first run (model download + load)
wait_for "llama-chat"  "http://localhost:${CHAT_PORT}/health"  240 || { $DC logs --tail 40 llama-chat; exit 1; }
wait_for "llama-embed" "http://localhost:${EMBED_PORT}/health" 120 || { $DC logs --tail 40 llama-embed; exit 1; }
wait_for "litellm"     "http://localhost:${LITELLM_PORT}/health/liveliness" 60 || { $DC logs --tail 40 litellm; exit 1; }
wait_for "anythingllm" "http://localhost:${ALLM_PORT}/api/ping" 60 || { $DC logs --tail 40 anythingllm; exit 1; }

# ── seed AnythingLLM (API key + provider settings) ───────────────────────────
echo "[setup] seeding AnythingLLM ..."
$DC exec -T \
    -e ALLM_KEY="$ALLM_KEY" \
    -e LITELLM_MASTER_KEY="$MASTER_KEY" \
    -e CHAT_CTX="$CHAT_CTX" \
    anythingllm python3 - < scripts/seed_anythingllm.py

echo "[setup] restarting AnythingLLM to apply settings ..."
$DC restart anythingllm >/dev/null
wait_for "anythingllm" "http://localhost:${ALLM_PORT}/api/ping" 60

cat <<EOF

[setup] ✅ stack is up.
  llama-chat   http://localhost:${CHAT_PORT}
  llama-embed  http://localhost:${EMBED_PORT}
  litellm      http://localhost:${LITELLM_PORT}
  prometheus   http://localhost:${PROM_PORT:-9090}
  anythingllm  http://localhost:${ALLM_PORT}

Next:
  make ingest     # download Google NQ + ingest documents into AnythingLLM
  make evaluate   # run queries + LLM-judge
  make report     # generate results/report.md + report.json
EOF
