#!/usr/bin/env bash
# Download Google NQ + bulk-embed the corpus straight into AnythingLLM's LanceDB.
# Uses the persistent native embed server (no data-parallel fan-out — same user,
# no Docker, kept simple; bump EMBED_CONCURRENCY in config.env if you want more).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$NATIVE/services.sh"

is_running llama-embed  || die "stack not up — run: native/up.sh"
is_running anythingllm  || die "anythingllm not up — run: native/up.sh"

mkdir -p "$ALLM_STORAGE/lancedb"
log "ingesting corpus (bulk embed → LanceDB at $ALLM_STORAGE) ..."
run_harness ingest.py
log "ingest complete — syncing retrieval settings ..."
sync_retrieval
