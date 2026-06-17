#!/usr/bin/env bash
# Auto-build the two A/B benchmark backends from fresh upstream llama.cpp — with
# NO machine-specific paths. Nothing local is preserved: any existing llama.cpp
# checkout (or symlink) at ./llama.cpp is replaced with a clean upstream clone.
#
# Produces two build trees under ./llama.cpp:
#   build/         baseline  — ggml-cpu only            (GGML_ZENDNN=OFF)
#   build_zendnn/  zendnn     — ggml-cpu + ggml-zendnn   (GGML_ZENDNN=ON)
#
# ZenDNN is handled entirely by llama.cpp's own CMake: with GGML_ZENDNN=ON and no
# ZENDNN_ROOT, ggml/src/ggml-zendnn/CMakeLists.txt ExternalProject_Add's the
# public github.com/amd/ZenDNN at a pinned tag, builds it, and links it. So we
# only ever build llama.cpp — nothing else to fetch or configure.
#
# Usage:
#   scripts/build_llama.sh            # clone-if-absent, then build
#   scripts/build_llama.sh --fresh    # wipe ./llama.cpp and re-clone from scratch
#
# run_ab.sh then needs no AB_*BINDIR / AB_ZENDNN_LIBDIR: the binaries land at the
# default project paths and the zendnn lib is auto-discovered from the binary.
set -euo pipefail
cd "$(dirname "$0")/.."           # repo root (rag_pipeline_bench)
ROOT="$PWD"

env_get() { local v; v="$(grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2-)"; [ -z "$v" ] && echo "$2" || echo "$v"; }
log()  { echo "[build] $*"; }
die()  { echo "[build] ERROR: $*" >&2; exit 1; }

command -v git   >/dev/null || die "git not found"
command -v cmake >/dev/null || die "cmake not found"

JOBS="$(nproc)"
FRESH=0; [ "${1:-}" = "--fresh" ] && FRESH=1

LLAMA_REPO="$(env_get LLAMA_REPO https://github.com/ggml-org/llama.cpp.git)"
LLAMA_REF="$(env_get LLAMA_REF master)"
LLAMA_DIR="$ROOT/llama.cpp"

# ── 1. fresh llama.cpp (drop any local checkout / symlink / modifications) ────
if [ "$FRESH" = 1 ] || [ -L "$LLAMA_DIR" ] || [ ! -e "$LLAMA_DIR/CMakeLists.txt" ]; then
    log "fetching fresh llama.cpp: $LLAMA_REPO ($LLAMA_REF)"
    rm -rf "$LLAMA_DIR"           # if it's a symlink this only removes the link
    git clone --depth 1 --branch "$LLAMA_REF" "$LLAMA_REPO" "$LLAMA_DIR"
else
    log "reusing existing llama.cpp clone at $LLAMA_DIR"
fi

# ── 2. baseline build — ggml-cpu only ────────────────────────────────────────
log "building baseline (ggml-cpu) -> llama.cpp/build"
cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DGGML_ZENDNN=OFF
cmake --build "$LLAMA_DIR/build" -j"$JOBS" --target llama-server

# ── 3. zendnn build — ggml-cpu + ggml-zendnn (CMake auto-fetches ZenDNN) ─────
log "building zendnn (ggml-cpu + ggml-zendnn) -> llama.cpp/build_zendnn"
log "  (first build downloads + compiles ZenDNN via ExternalProject — several minutes)"
cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build_zendnn" \
    -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DGGML_ZENDNN=ON
cmake --build "$LLAMA_DIR/build_zendnn" -j"$JOBS" --target llama-server

log "done."
log "  baseline : $LLAMA_DIR/build/bin/llama-server"
log "  zendnn   : $LLAMA_DIR/build_zendnn/bin/llama-server"
log "  (zendnn lib is auto-discovered by run_ab.sh from the binary's RPATH)"
