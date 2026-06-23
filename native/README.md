# Native (no-Docker) RAG eval stack

A side-by-side, **Docker-free** twin of the containerized stack in the repo root.
Every service runs as a plain OS process owned by your user — **no Docker, no
sudo, no systemd, no root**. Built for a locked-down box where Docker is not
available. The Docker workflow (root `docker-compose.yml`, `Makefile`, `run_ab.sh`,
`ci/`) is untouched; this lives entirely under `native/`.

The Python harness (`src/*.py`) and the AnythingLLM seeding (`scripts/`) are
**shared** with the Docker stack — the native scripts just point them at
`localhost` instead of container DNS names.

## What runs (all as your-user processes)

| Service | Native form |
|---|---|
| llama-chat / llama-embed | `llama.cpp/build*/bin/llama-server` (already built; or built from source by `setup.sh`) |
| LiteLLM proxy | `litellm` (pip `--user`) |
| AnythingLLM (+ collector) | Node monorepo **built from source** under `native/.runtime/anythingllm` (no image exists) |
| Prometheus / Grafana / pushgateway | prebuilt release tarballs under `native/.runtime/` |
| harness (ingest/eval/report) | `python3 src/*.py` with `--user` deps |

All toolchains install under `native/.runtime/` (git-ignored). Nothing touches the
system.

## Quick start

```bash
cp native/config.env.example native/config.env   # edit model paths / ports / NUMA
bash native/setup.sh        # one-time: install toolchains + build AnythingLLM  (slow)
bash native/up.sh           # start the whole stack + seed AnythingLLM
bash native/ingest.sh       # ONE-TIME: download NQ + bulk-embed corpus into LanceDB
bash native/evaluate.sh && bash native/report.sh   # REPEATABLE measurement run
bash native/down.sh         # stop everything
```

Or via make. **Ingest once, then `bench` (evaluate + report) as often as you like** —
no need to re-ingest between runs:

```bash
make -C native setup
make -C native up
make -C native ingest       # ONE-TIME: load + embed the corpus
make -C native bench        # REPEATABLE: evaluate + report, run after run
# (make -C native all = ingest + bench, for the first full run)
make -C native ab           # ZenDNN A/B (baseline vs zendnn build) + report_ab
make -C native status       # running state + health of each service
make -C native down
```

## How it maps to the Docker stack

- **Ports** are the same host ports (chat 8081, embed 8082, litellm 4000,
  anythingllm 3001, prometheus 9090, pushgateway 9091, grafana 3000); everything
  binds `127.0.0.1`.
- **Wiring** that was container DNS (`llama-chat:8080`, `litellm:4000`) becomes
  `127.0.0.1:<port>`. `native/up.sh` generates localhost `litellm.yaml` /
  `prometheus.yml` / Grafana provisioning into `native/.runtime/conf/`.
- **AnythingLLM storage** (SQLite DB + LanceDB) lives in
  `native/.runtime/anythingllm/server/storage`. Because the harness and
  AnythingLLM run as the **same user**, the Docker uid/permission dance for the
  shared LanceDB volume disappears.
- **A/B** swaps the chat `llama-server` **process** between the baseline and
  `build_zendnn` binaries (instead of swapping a container image), exactly like
  the original `.sh` stack did.

## Process management

No orchestrator: each service is `setsid`-launched into its own process group,
its PID recorded in `native/run/<svc>.pid`, and its stdout/stderr in
`native/logs/<svc>.log`. `down.sh` kills each group. `status.sh` shows
running-state + a health probe. `make -C native logs` tails everything.

## Configuration

All knobs live in `native/config.env` (copied from `config.env.example`):
model paths, ports, NUMA pinning (`*_CPUS`/`*_MEMBIND`, applied via `numactl` when
present), llama tuning, eval/dataset parameters, the ZenDNN A/B settings, and the
toolchain versions `setup.sh` installs.

## Requirements on the target

`setup.sh` runs a **preflight** that fails fast (listing what's missing) before
doing any work, so you know up front.

**Installed by `setup.sh` — no root needed** (this is the bulk of it):
- **Node + npm + yarn** (a self-contained Node tarball into `native/.runtime/`),
- **Prometheus, Grafana, pushgateway** (prebuilt release tarballs),
- the **Python harness deps** into an isolated **venv** at `native/.runtime/venv`
  (pinned `datasets==3.2.0` / `huggingface_hub==0.27.0` so the legacy script-based
  NQ datasets load, and `lancedb==0.15.0` to match AnythingLLM's table format) —
  never the host's `--user` packages; plus `litellm` (`pip --user`),
- **AnythingLLM** (cloned + built from source),
- **llama.cpp** (built natively via `cmake` **only if** `llama.cpp/build*` binaries
  aren't already present — ZenDNN included).

**Must already be present** (base OS tools — `setup.sh` cannot install these without
root; they come from your system package manager):
- `curl`, `tar` + `xz`, `git`, `python3` + `pip` + `venv` (the `python3-venv`
  package — the harness runs in an isolated virtualenv),
- a **C/C++ toolchain** (`make`, `gcc`/`cc`, `g++`/`c++`) and **`cmake`** — needed by
  node-gyp when AnythingLLM compiles native modules, and to build llama.cpp. (If both
  AnythingLLM and the llama binaries are already built, the compiler/cmake check is
  skipped.)

**Other:**
- Linux x86_64, glibc ≥ 2.31, outbound HTTPS (to fetch toolchains + HF datasets on
  first run).
- `numactl` is optional (NUMA pinning is skipped if absent).
- The GGUF model files (not downloaded) at the paths in `config.env`.

## Notes / limitations

- The AnythingLLM **web UI** is not built (the frontend `yarn build` is skipped) —
  the harness only uses the server's HTTP API, which works without it.
- Native ingest uses the single persistent embed server (no data-parallel
  fan-out); raise `EMBED_CONCURRENCY` in `config.env` for more throughput.
- The Python `lancedb` pin (`0.15.0`) must match AnythingLLM's `@lancedb/lancedb`
  so the table the harness writes is readable by AnythingLLM.
