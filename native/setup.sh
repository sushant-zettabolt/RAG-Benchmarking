#!/usr/bin/env bash
# One-time installer for the native (no-Docker, no-sudo) stack. Everything lands
# under native/.runtime as the current user. Idempotent: re-run safely; each step
# skips work already done.
#
#   cp native/config.env.example native/config.env   # edit model paths first
#   bash native/setup.sh
#
# Installs: a local Node toolchain, Prometheus, Grafana, pushgateway; the Python
# harness deps (pip --user); builds llama.cpp natively if the binaries are absent;
# clones + builds AnythingLLM from source and creates its SQLite DB.
set -euo pipefail
NATIVE="$(cd "$(dirname "$0")" && pwd)"; BASE="$(cd "$NATIVE/.." && pwd)"

if [ ! -f "$NATIVE/config.env" ]; then
    cp "$NATIVE/config.env.example" "$NATIVE/config.env"
    echo "[setup] created native/config.env from example — review model paths/ports, then re-run."
fi
# shellcheck disable=SC1091
. "$NATIVE/lib.sh"; . "$NATIVE/services.sh"

DL="$RUNTIME/dl"; mkdir -p "$DL" "$RUNTIME"
have() { command -v "$1" >/dev/null 2>&1; }

# ── 0. preflight: verify the base toolchain we can NOT install without root ──
# This script installs everything an unprivileged user CAN (Node/npm/yarn,
# Prometheus, Grafana, pushgateway, the Python deps, AnythingLLM, and llama.cpp).
# But it relies on a handful of OS-level tools being present — those come from the
# system package manager and need root, so we fail fast (not halfway) if missing.
preflight() {
    local miss=()
    for t in curl tar git python3; do have "$t" || miss+=("$t"); done
    have xz || tar --help 2>/dev/null | grep -q -- '--xz' || miss+=("xz (xz-utils — to unpack Node)")
    python3 -m pip --version >/dev/null 2>&1 || have pip || miss+=("python3 pip (python3-pip)")
    # The harness runs in a venv (isolated pinned deps); needs ensurepip/venv.
    python3 -c "import ensurepip" >/dev/null 2>&1 || miss+=("python3 venv (python3-venv / ensurepip)")
    # A C/C++ toolchain is needed by node-gyp (AnythingLLM native modules) and by a
    # native llama build. Required unless BOTH are already built.
    local need_cc=0
    [ -d "$ALLM_DIR/server/node_modules" ] || need_cc=1
    { [ -x "$LLAMA_BASELINE_BIN" ] && [ -x "$LLAMA_ZENDNN_BIN" ]; } || need_cc=1
    if [ "$need_cc" = 1 ]; then
        have make || miss+=("make")
        have g++ || have c++ || miss+=("g++ / c++ (a C++ compiler)")
        have gcc || have cc  || miss+=("gcc / cc (a C compiler)")
    fi
    # cmake is only needed to build llama.cpp natively (skipped if binaries exist).
    { [ -x "$LLAMA_BASELINE_BIN" ] && [ -x "$LLAMA_ZENDNN_BIN" ]; } || have cmake || miss+=("cmake")

    if [ "${#miss[@]}" -gt 0 ]; then
        echo "[setup] ERROR: missing base prerequisites this script can NOT install without root" >&2
        for m in "${miss[@]}"; do echo "          - $m" >&2; done
        echo "[setup] These come from your OS package manager (ask an admin if you lack sudo)." >&2
        echo "[setup] Everything else — Node/npm/yarn, Prometheus, Grafana, pushgateway, the" >&2
        echo "        Python deps, AnythingLLM, and llama.cpp — IS installed here, no root needed." >&2
        exit 1
    fi
    log "preflight OK — base toolchain present"
}

# ── 1. toolchains (prebuilt tarballs; no sudo) ───────────────────────────────
install_node() {
    [ -x "$RUNTIME/node/bin/node" ] && { log "node present ($($RUNTIME/node/bin/node -v))"; return; }
    log "installing Node ${NODE_VERSION} ..."
    curl -fSL --retry 3 -o "$DL/node.tar.xz" \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"
    tar xf "$DL/node.tar.xz" -C "$RUNTIME" && mv "$RUNTIME/node-v${NODE_VERSION}-linux-x64" "$RUNTIME/node"
    "$RUNTIME/node/bin/corepack" enable --install-directory "$RUNTIME/node/bin" 2>/dev/null || true
}
install_prom() {
    [ -x "$RUNTIME/prometheus/prometheus" ] && { log "prometheus present"; return; }
    log "installing Prometheus ${PROM_VERSION} ..."
    curl -fSL --retry 3 -o "$DL/prom.tar.gz" \
        "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
    tar xzf "$DL/prom.tar.gz" -C "$RUNTIME" && mv "$RUNTIME/prometheus-${PROM_VERSION}.linux-amd64" "$RUNTIME/prometheus"
}
install_pushgw() {
    [ -x "$RUNTIME/pushgateway/pushgateway" ] && { log "pushgateway present"; return; }
    log "installing pushgateway ${PUSHGW_VERSION} ..."
    curl -fSL --retry 3 -o "$DL/pushgw.tar.gz" \
        "https://github.com/prometheus/pushgateway/releases/download/v${PUSHGW_VERSION}/pushgateway-${PUSHGW_VERSION}.linux-amd64.tar.gz"
    tar xzf "$DL/pushgw.tar.gz" -C "$RUNTIME" && mv "$RUNTIME/pushgateway-${PUSHGW_VERSION}.linux-amd64" "$RUNTIME/pushgateway"
}
install_grafana() {
    [ -x "$RUNTIME/grafana/bin/grafana" ] && { log "grafana present"; return; }
    log "installing Grafana ${GRAFANA_VERSION} ..."
    curl -fSL --retry 3 -o "$DL/grafana.tar.gz" \
        "https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz"
    tar xzf "$DL/grafana.tar.gz" -C "$RUNTIME"
    mv "$RUNTIME/grafana-v${GRAFANA_VERSION}" "$RUNTIME/grafana" 2>/dev/null || \
    mv "$RUNTIME/grafana-${GRAFANA_VERSION}" "$RUNTIME/grafana"
}

# ── 2. python harness deps (pip --user) ──────────────────────────────────────
install_python() {
    local venv="$RUNTIME/venv"
    # Isolated venv with the PINNED harness deps. The host's own --user packages
    # (often a newer datasets/huggingface_hub) reject the legacy script-based NQ
    # datasets, so we never use them — the venv pins fix dataset loading AND keep
    # lancedb at 0.15.0 to match AnythingLLM's table format.
    if [ ! -x "$venv/bin/python" ]; then
        log "creating harness venv ($venv) ..."
        python3 -m venv "$venv"
    fi
    if "$venv/bin/python" -c "import datasets,huggingface_hub,lancedb,requests" 2>/dev/null; then
        log "harness venv deps present"
    else
        log "installing pinned harness deps into venv ..."
        "$venv/bin/python" -m pip install --quiet --upgrade pip
        "$venv/bin/python" -m pip install --quiet -r "$BASE/harness/requirements.txt"
    fi
    # litellm runs as a standalone proxy process (on PATH); it doesn't import the
    # harness, so a --user install is fine.
    have litellm || python3 -m pip install --user "litellm[proxy]"
}

# ── 3. llama.cpp native binaries (built here; on target build from source) ───
build_llama() {
    local src="$BASE/llama.cpp"
    if [ -x "$LLAMA_BASELINE_BIN" ] && [ -x "$LLAMA_ZENDNN_BIN" ]; then
        log "llama.cpp binaries present (baseline + zendnn)"; return
    fi
    [ -d "$src" ] || die "llama.cpp source not found at $src (clone it first)"
    have cmake || die "cmake not found — needed to build llama.cpp natively"
    if [ ! -x "$LLAMA_BASELINE_BIN" ]; then
        log "building llama.cpp baseline (native -march=native) ..."
        cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON \
              -DLLAMA_CURL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
        cmake --build "$src/build" --config Release --target llama-server -j"$(nproc)"
    fi
    if [ ! -x "$LLAMA_ZENDNN_BIN" ]; then
        log "building llama.cpp ZenDNN (native; fetches public ZenDNN — slow) ..."
        cmake -S "$src" -B "$src/build_zendnn" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON \
              -DGGML_ZENDNN=ON -DLLAMA_CURL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
        cmake --build "$src/build_zendnn" --config Release --target llama-server -j"$(nproc)"
    fi
}

# ── 4. AnythingLLM from source ───────────────────────────────────────────────
build_anythingllm() {
    local d="$ALLM_DIR"
    export PATH="$RUNTIME/node/bin:$PATH"
    if [ ! -d "$d/.git" ]; then
        log "cloning AnythingLLM ($ANYTHINGLLM_REF) ..."
        git clone --depth 1 --branch "$ANYTHINGLLM_REF" "$ANYTHINGLLM_REPO" "$d" 2>/dev/null \
            || git clone --depth 1 "$ANYTHINGLLM_REPO" "$d"
    fi
    [ -d "$d/server/node_modules" ]    || { log "yarn install (server) ...";    ( cd "$d/server" && yarn install ); }
    [ -d "$d/collector/node_modules" ] || { log "yarn install (collector) ..."; ( cd "$d/collector" && yarn install ); }
    log "prisma generate + migrate deploy (creates the SQLite DB) ..."
    mkdir -p "$d/server/storage"
    ( cd "$d/server" && npx prisma generate >/dev/null 2>&1 || true )
    ( cd "$d/server" && npx prisma migrate deploy )
    # NOTE: the web frontend is intentionally NOT built — the harness only uses the
    # server's HTTP API, and the server serves a default page without it.
}

log "════════ native stack setup ════════"
preflight
install_node
install_prom
install_pushgw
install_grafana
install_python
build_llama
build_anythingllm
gen_configs
rm -rf "$DL"
cat <<EOF

[setup] ✅ done. Start it with:
    native/up.sh        (or: make -C native up)
    native/ingest.sh && native/evaluate.sh && native/report.sh   (or: make -C native all)
EOF
