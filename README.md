# Local RAG Evaluation Stack — AnythingLLM + llama.cpp + Google NQ

A fully containerized, reproducible RAG evaluation pipeline. Everything runs in
Docker — including the LLM and embedding servers — so the only host requirement
is **Docker + Docker Compose**. The llama.cpp servers are **built from public
source on first `up`** (clone latest master, compile `-march=native`); nothing is
pulled from a registry and no binaries are shipped. One `docker compose up`
builds + starts the stack and auto-configures AnythingLLM; three commands ingest
Google Natural Questions, evaluate, and produce a report.

```
        ┌─────────────┐   embed   ┌──────────────┐
        │ llama-embed │◀──────────│              │
        │ (llama.cpp) │           │   LiteLLM    │   OpenAI-compatible proxy
        └─────────────┘           │   (proxy +   │   (token usage + TTFT metrics)
        ┌─────────────┐   chat    │  Prometheus  │
        │ llama-chat  │◀──────────│   metrics)   │
        │ (llama.cpp) │           └──────┬───────┘
        └─────────────┘                  │ /v1
                                  ┌───────▼───────┐        ┌────────────┐
                                  │  AnythingLLM  │◀───────│  harness   │
                                  │ (RAG app +    │ HTTP   │ ingest /   │
                                  │  LanceDB)     │        │ evaluate / │
                                  └───────────────┘        │ report     │
                                                           └────────────┘
```

## Prerequisites

- Docker Engine + Docker Compose v2 (`docker compose version`)
- A C++ toolchain is **not** needed on the host — llama.cpp is compiled inside the
  build container.
- ~6 GB disk for images, plus your own model GGUFs
- Your own chat + embedding GGUF files (models are **not** downloaded — you mount them)
- Internet access on first run (clones llama.cpp, pulls the support images, and
  downloads the NQ dataset). For air-gapped machines see **Shipping images via
  git-lfs** below.

## Quick start

```bash
cp .env.example .env        # then set MODELS_DIR + CHAT_MODEL_PATH/EMBED_MODEL_PATH
docker compose up -d        # FIRST run: compiles llama.cpp from source (minutes),
                            # pulls support images, seeds AnythingLLM automatically
make ingest                 # download Google NQ + ingest 100 documents
make evaluate               # run queries against AnythingLLM + LLM-as-judge
make report                 # write results/report.md + results/report.json
```

`docker compose up -d` (or `make up`, or the thin `./setup.sh` wrapper that also
validates your model paths) is all you need to start — the one-shot `seed` service
configures AnythingLLM once it's healthy, so there is no separate setup step. The
**first** `up` clones latest-master llama.cpp and compiles it (several minutes,
`GGML_ZENDNN=OFF` → `nqrag-llama:baseline`); subsequent `up`s reuse the cached
image. `make all` runs ingest → evaluate → report in sequence. Outputs land in
`./data/` (bind-mounted into the harness container):

```
data/
  docs/                 ingested document files
  eval.jsonl            questions + reference answers
  ingest_metadata.json  ingestion status / failures
  results/
    metrics.jsonl       one structured record per query
    results.json        raw results + run summary
    report.md           human-readable report
    report.json         machine-readable report
```

A pre-generated example lives in [`reports/`](reports/).

## Building the llama.cpp images from source

The `llama-chat` / `llama-embed` servers run images compiled locally from public
llama.cpp source (`docker/llama/Dockerfile`, multi-stage). A single `GGML_ZENDNN`
build arg produces two images from identical source:

| Image | Build arg | Backend |
|---|---|---|
| `nqrag-llama:baseline` | `GGML_ZENDNN=OFF` | ggml CPU only |
| `nqrag-llama:zendnn` | `GGML_ZENDNN=ON` | ggml + ZenDNN (auto-fetches **public** ZenDNN source) |

Either image can serve as chat **or** embed — only the mounted model and command
flags differ. `docker compose up` builds `nqrag-llama:baseline` on first run (it's
the default for both services). The A/B run additionally needs the zendnn image:

```bash
make build-llama            # build BOTH images at the SAME commit (fair A/B)
```

`make build-llama` resolves master's HEAD SHA once (`git ls-remote`) and feeds it
to both builds via the `LLAMA_CPP_REF` arg, so baseline and zendnn are the same
commit. Notes:

- **`up` does not auto-refresh.** Once an image exists, `up` reuses the cache even
  if master moved. To rebuild on latest, run `make build-llama` (or
  `docker compose build --no-cache --pull llama-chat`).
- **Pin for reproducibility.** Set `LLAMA_CPP_REF=<sha-or-tag>` in `.env` to freeze
  the build (empty = latest master at build time).
- **`-march=native`** — a built image is tuned to this CPU and is **not** portable
  to a different microarchitecture (illegal-instruction faults). Each host builds
  its own.

## Configuration (`.env`)

Everything is configurable through `.env` — nothing is hardcoded.

| Variable | Default | Meaning |
|---|---|---|
| `LLAMA_CPP_REPO` | `github.com/ggml-org/llama.cpp` | Public llama.cpp source cloned at build time |
| `LLAMA_CPP_REF` | _empty_ | Pin to a commit/tag for a frozen build (empty = latest master) |
| `MODELS_DIR` | `./models` | **Required.** Host dir holding your GGUFs, mounted read-only at `/models` |
| `CHAT_MODEL_PATH` | `/models/Llama-3.2-1B-Instruct-BF16.gguf` | **Required.** In-container path to the chat GGUF (under `/models`) |
| `EMBED_MODEL_PATH` | `/models/nomic-embed-text-v1.5.f16.gguf` | **Required.** In-container path to the embedding GGUF (under `/models`) |
| `CHAT_CTX` / `CHAT_BATCH` / `CHAT_UBATCH` | `8192` / `512` / `512` | Chat context & batch sizes |
| `EMBED_CTX` / `EMBED_BATCH` / `EMBED_UBATCH` | `2048` | Embed context & batch (keep batch ≥ ctx) |
| `CHAT_NGL` / `EMBED_NGL` | `0` | GPU layers to offload (0 = CPU). See **GPU** below |
| `CHAT_THREADS` / `EMBED_THREADS` | _empty_ | CPU threads (empty = auto) |
| `*_CPUSET` / `CHAT_MEMBIND` / `EMBED_MEMBIND` | _empty_ | CPU / NUMA pinning per service — see **NUMA / CPU pinning** |
| `CHAT_EXTRA_FLAGS` | _empty_ | Extra llama-server flags, e.g. `--flash-attn on` |
| `*_PORT` | 8081/8082/4000/9090/3001 | Host ports for chat/embed/litellm/prometheus/anythingllm |
| `DOC_N` | `100` | Documents to ingest |
| `EVAL_N` | `100` | Eval questions to draw |
| `EVAL_LIMIT` | _empty_ | Cap measured queries (smoke tests) |
| `CORPUS_SCAN` | `20000` | Passages scanned to find answer-bearing documents |
| `JUDGE_MODEL` | `chat-model` | Model used as LLM judge |
| `JUDGE_THRESHOLD` | `0.5` | Judge score ≥ threshold counts as a match |
| `WARMUP` | `1` | Leading warmup queries excluded from the report |

### Models

Models are **not** downloaded — you supply your own GGUF files and mount them.
Put the chat + embedding GGUFs in one host folder, point `MODELS_DIR` at it, and
set `CHAT_MODEL_PATH` / `EMBED_MODEL_PATH` to their paths under `/models`:

```dotenv
MODELS_DIR=/scratch/models/gguf
CHAT_MODEL_PATH=/models/Llama-3.1-8B-Instruct-BF16.gguf
EMBED_MODEL_PATH=/models/nomic-embed-text-v1.5.f32.gguf
```

The `llama-chat` / `llama-embed` containers exit immediately with a clear error
if either variable is unset or the referenced file isn't found in the mount.

### GPU

The image is CPU-only (the Dockerfile builds with `GGML_NATIVE=ON` for the host
CPU). For NVIDIA GPUs you'd add a CUDA toolchain + `-DGGML_CUDA=ON` to
`docker/llama/Dockerfile`, set `CHAT_NGL`/`EMBED_NGL` > 0, and add a
`deploy.resources.reservations.devices` GPU reservation to the
`llama-chat`/`llama-embed` services (requires nvidia-container-toolkit).

### NUMA / CPU pinning

On a multi-socket (NUMA) box, decode is memory-bandwidth bound: if the chat
server's threads roam across sockets and pull weights over the inter-socket link,
throughput tanks. Pin each container to a distinct, non-overlapping set of cores,
and bind the llama servers' **memory** to the same NUMA node as their CPUs. All of
this is optional — leave the variables empty for no pinning (the portable default).

| Variable | Meaning |
|---|---|
| `CHAT_CPUSET` / `EMBED_CPUSET` | CPUs the llama containers may run on (Docker `cpuset`), e.g. `96-191` |
| `LITELLM_CPUSET` / `ALLM_CPUSET` / `PROM_CPUSET` / `HARNESS_CPUSET` | Same, for the support services |
| `CHAT_MEMBIND` / `EMBED_MEMBIND` | NUMA **memory** node for the llama servers (e.g. `1` / `0`) |

Example for a 2×96-core EPYC (node 0 = cpus `0-95`, node 1 = cpus `96-191`):

```dotenv
CHAT_CPUSET=96-191    # chat owns all of node 1 …
CHAT_MEMBIND=1        # … with its memory there too
CHAT_THREADS=96       # one thread per physical core
EMBED_CPUSET=0-15     # everything else lives on node 0
EMBED_MEMBIND=0
LITELLM_CPUSET=16-23
ALLM_CPUSET=24-39
PROM_CPUSET=40-43
HARNESS_CPUSET=44-51
```

How it's enforced:

- **Both layers, belt-and-suspenders.** Docker `cpuset:` constrains each container
  at the cgroup level; the two llama servers are *additionally* launched under
  `numactl --physcpubind=<CPUSET> --membind=<node>` so the CPU affinity and memory
  policy are also set in-process. (`numactl` is auto-installed into the llama image
  when a membind is requested.)
- The llama services need the **`SYS_NICE`** capability (already in the compose
  file) — without it the kernel's default seccomp profile blocks `set_mempolicy`
  and `--membind` fails with *"Operation not permitted"*.
- `numactl` can't run inside `prometheus` (distroless, no package manager) or the
  app images, so the support services use the cgroup `cpuset` only — sufficient,
  since they're I/O-light and first-touch keeps their memory node-local anyway.
- Both `cpuset` and `--physcpubind` are *allowed-set* masks (threads may still
  migrate **within** the set); they are not 1:1 core pinning. For strict
  no-migration pinning use llama.cpp's `--cpu-mask` + `--cpu-strict 1` via
  `CHAT_EXTRA_FLAGS`.

The same `CHAT_CPUSET` also pins the chat server during the ZenDNN A/B run.

## What gets measured

Per query we snapshot the llama.cpp `/metrics` counters on the chat and embed
servers before/after the AnythingLLM call (queries run serially, so deltas are
clean), and grade the answer with an LLM judge afterwards.

| Metric | Source |
|---|---|
| Match score / verdict | LLM-as-judge (LiteLLM) comparing answer vs reference |
| End-to-end latency | Harness wall-clock (request → SSE `close`) |
| TTFT | Harness: time to first `textResponse` chunk |
| Query embedding time | `llamacpp:prompt_seconds_total` delta on llama-embed |
| Prompt processing (prefill) | `llamacpp:prompt_seconds_total` delta on llama-chat |
| Generation (decode) | `llamacpp:tokens_predicted_seconds_total` delta on llama-chat |
| Retrieval + overhead | derived: `ttft − embed − prefill` (vector search + prompt build) |
| Token usage | `llamacpp:prompt_tokens_total` / `tokens_predicted_total` deltas |
| Total runtime | Harness job wall-clock |

LiteLLM + Prometheus also expose aggregate token-usage and TTFT metrics at
`http://localhost:9090` (Prometheus) for dashboards.

## ZenDNN A/B benchmark (optional)

Compare a **baseline** vs a **ZenDNN** llama.cpp backend on the *same* RAG
pipeline (identical model, documents, and queries) and get a baseline-vs-zendnn
report with per-stage latency, inference throughput (prefill/decode t/s), and
speedup ratios.

```bash
docker compose up -d && make ingest   # stack up + documents ingested
make ab                                # builds zendnn image if missing, then
                                       # baseline job → zendnn job → report_ab
```

`run_ab.sh` swaps **both** the `llama-chat` and `llama-embed` backends together
per job (by overriding their images) — so the report compares the whole inference
path under each backend (query embedded **and** answer generated by the same
backend). Jobs run **strictly sequentially** — one backend at a time — so they
never compete for CPU and the numbers stay clean. It builds both images via
`make build-llama` if they don't exist, then writes
`data/results/report_ab.{md,json}`.

How the two backends are provided (configurable in `.env`):

| Variable | Default | Meaning |
|---|---|---|
| `LLAMA_BASELINE_IMAGE` | `nqrag-llama:baseline` | Image used for the baseline job (built `GGML_ZENDNN=OFF`) |
| `LLAMA_ZENDNN_IMAGE` | `nqrag-llama:zendnn` | Image used for the zendnn job (built `GGML_ZENDNN=ON`) |
| `AB_ZENDNN_ALGO` | `1` | `ZENDNNL_MATMUL_ALGO` value for the zendnn job |
| `AB_FIXED_DECODE` | _empty_ | Force exactly N decode tokens/query on both backends for a clean prefill+decode comparison (quality judging auto-skipped) |

Both jobs apply the same three runtime flags (`ZENDNNL_MATMUL_ALGO`,
`OMP_PROC_BIND=close`, `OMP_PLACES=cores`); `ZENDNNL_MATMUL_ALGO` is the only
thing that differs (unset for baseline). The images are built from the same
commit by `make build-llama`, so baseline and zendnn differ only in the ZenDNN
backend. `CHAT_MODEL_PATH` must point at a local GGUF (the A/B uses your real
model, since ZenDNN targets matmul-bound prefill). A sample A/B report is in
[`reports/`](reports/).

## Dataset notes

- **Documents** come from `BeIR/nq` (Google NQ Wikipedia passages).
- **Questions + reference answers** come from `nq_open` (Google NQ open Q&A).
- To keep retrieval meaningful, ingestion prefers passages that actually contain
  a reference answer (`CORPUS_SCAN`), then tops up to `DOC_N`. The number of
  answerable questions is recorded in `ingest_metadata.json` and the report.
- **Full corpus:** set `DOC_N=0` **and** `CORPUS_SCAN=0` to ingest the *entire*
  `BeIR/nq` corpus (~2.68M passages) for a realistic, non-toy retrieval test.
  This is made feasible by **bulk ingest** (`BULK_INGEST=1`, the default): the
  harness embeds chunks itself against `llama-embed` in parallel batches and
  writes the vectors **straight into AnythingLLM's LanceDB table**, skipping the
  legacy one-file-+-one-HTTP-POST-per-document path. Ingest time is then bounded
  by the embedder's throughput, not by per-document HTTP overhead. Tune
  `EMBED_REQ_BATCH` / `EMBED_CONCURRENCY`; set `BULK_INGEST=0` for the legacy path.
- **Ingest vs retrieve embed tuning.** `make ingest` (via `run_ingest.sh`)
  temporarily reconfigures `llama-embed` for max throughput — **whole box +
  `EMBED_INGEST_PARALLEL` server slots** (ctx auto-scales by slot count) — then
  **restores the bounded, single-slot retrieve config** (`EMBED_CPUSET`, no
  `--parallel`). Retrieval embeds one query at a time, so it stays pinned and
  single-slot and never steals cores from `llama-chat` during the A/B. These
  knobs (`EMBED_INGEST_CPUSET/THREADS/PARALLEL/BATCH`) affect ingest speed only —
  not the benchmark numbers.
- Both datasets are configurable via `EVAL_DATASET` / `CORPUS_DATASET`.

## Shipping images via git-lfs (air-gapped install)

```bash
make save-images            # docker save -> images/*.tar (tracked by git-lfs)
git lfs track "images/*.tar"   # already in .gitattributes
git add .gitattributes images/*.tar && git commit -m "ship images"
```

On the target machine:

```bash
git lfs pull
make load-images            # docker load all tarballs
./setup.sh                  # no registry pulls needed
```

## Lifecycle

```bash
make up           # build (first run) + start the full stack; seed auto-configures
make build-llama  # (re)build BOTH llama.cpp images from source at the same commit
make ps           # status
make logs         # follow logs
make down         # stop containers (keeps volumes)
make clean        # remove generated data/results
make clean-all    # also drop volumes (models cache, vector DB)
```

## Troubleshooting

- **`make ingest` says ALLM_KEY is empty** — `ALLM_KEY` has a default in
  `.env.example` and the one-shot `seed` service writes it into AnythingLLM on
  `up`. If you blanked it, set it in `.env` and re-run `docker compose up -d` (the
  `seed` service re-applies it). Change it from the default for any non-local use.
- **First `up` is slow / want to watch the build** — the first `up` compiles
  llama.cpp from source (minutes). Run `docker compose build llama-chat` (or
  `make build-llama`) to see the build output directly.
- **llama-chat exits immediately / "CHAT_MODEL_PATH is not set" or "model not
  found"** — set `MODELS_DIR` to the host folder with your GGUFs and
  `CHAT_MODEL_PATH` / `EMBED_MODEL_PATH` to their paths under `/models`. Watch
  with `make logs`.
- **All answers empty / unhealthy embed model** — confirm `conf/litellm.yaml`
  keeps `model_info: {mode: embedding}` on `embed-model`; without it LiteLLM
  health-probes the embed endpoint with a chat completion and flags it unhealthy.
- **llama-chat/embed crash-loop with `set_mempolicy: Operation not permitted`** —
  `--membind` needs the `SYS_NICE` capability. It's already in `docker-compose.yml`;
  if you stripped it, restore `cap_add: [SYS_NICE]` on the llama services (or clear
  `CHAT_MEMBIND`/`EMBED_MEMBIND` to disable memory binding).
- **Port already in use** — change the `*_PORT` values in `.env`.
```
