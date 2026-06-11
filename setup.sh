#!/usr/bin/env bash
# One-shot setup: deps -> build llama.cpp (baseline + zendnn) -> start stack
# -> init AnythingLLM -> download + ingest corpus -> end-to-end gate check.
# Idempotent — safe to re-run; finished stages are skipped.
#
#   cp config.env.example config.env   # edit for your machine
#   ./setup.sh
#   ./run_bench.sh
set -eo pipefail
cd "$(dirname "$0")"

# ── 0. config ───────────────────────────────────────────────────────────────
if [ ! -f config.env ]; then
    cp config.env.example config.env
    echo "[setup] created config.env from example — review model paths / NUMA"
    echo "        binding / ZENDNN_ROOT in it if this is a new machine."
fi
. scripts/lib.sh

# ── 1. prerequisites ────────────────────────────────────────────────────────
log "checking prerequisites"
for c in python3 docker cmake curl envsubst git; do
    command -v "$c" >/dev/null || die "missing required command: $c"
done
if [ -n "$CHAT_CPUS$EMBED_CPUS" ]; then
    command -v numactl >/dev/null || die "numactl required for CPU binding (or clear *_CPUS in config.env)"
fi
docker info >/dev/null 2>&1 || die "docker daemon not reachable (permissions?)"
[ -f "$CHAT_MODEL" ]  || die "CHAT_MODEL not found: $CHAT_MODEL (set it in config.env)"
[ -f "$EMBED_MODEL" ] || die "EMBED_MODEL not found: $EMBED_MODEL (set it in config.env)"

python3 -c "import requests" 2>/dev/null || python3 -m pip install --user -q requests
python3 -c "import datasets" 2>/dev/null || python3 -m pip install --user -q datasets
command -v "$LITELLM_BIN" >/dev/null || {
    log "installing litellm[proxy]"
    python3 -m pip install --user -q 'litellm[proxy]'
}

# ── 2. generate AnythingLLM API key if unset ────────────────────────────────
if [ -z "$ALLM_KEY" ]; then
    ALLM_KEY="bench-$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    sed -i "s|^ALLM_KEY=.*|ALLM_KEY=\"$ALLM_KEY\"|" config.env
    export ALLM_KEY
    log "generated ALLM_KEY and saved it to config.env"
fi

# ── 3. build llama-server binaries ──────────────────────────────────────────
scripts/build_llama.sh

# ── 4. bring up the stack (baseline) ────────────────────────────────────────
./start_services.sh baseline

# ── 5. first-time AnythingLLM init (API key + provider settings in SQLite) ──
scripts/init_anythingllm.sh

# ── 6. data prep + corpus ingest (once) ─────────────────────────────────────
if [ -f data/queries.jsonl ]; then
    log "data/queries.jsonl exists — skipping data prep"
else
    log "downloading NQ corpus (CORPUS_N=$CORPUS_N QUERIES_N=$QUERIES_N)"
    env BASE="$BASE" CORPUS_N="$CORPUS_N" QUERIES_N="$QUERIES_N" python3 prepare_data.py
fi

if [ -f results/workspace_slug.txt ]; then
    log "workspace already ingested ($(cat results/workspace_slug.txt)) — skipping ingest"
else
    log "ingesting corpus into AnythingLLM workspace (this embeds every chunk — takes a while)"
    env BASE="$BASE" ALLM_KEY="$ALLM_KEY" ALLM_URL="$ALLM_URL" SLUG="$SLUG" python3 ingest.py
fi

# ── 7. end-to-end gate check ────────────────────────────────────────────────
log "gate check: one RAG query through the full pipeline"
OUT=$(curl -s -m 120 -X POST "$ALLM_URL/api/v1/workspace/$SLUG/chat" \
    -H "Authorization: Bearer $ALLM_KEY" \
    -H "Content-Type: application/json" \
    -d '{"message":"What is the largest planet?","mode":"query"}')
echo "$OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
n = len(d.get('sources') or [])
ans = (d.get('textResponse') or '')[:80]
print(f'  sources={n}  answer={ans!r}')
sys.exit(0 if n > 0 and ans else 1)" || die "gate check FAILED — see Troubleshooting in steps.md"

echo
log "setup complete. run the benchmark with:  ./run_bench.sh"
