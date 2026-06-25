# RAG Pipeline Benchmark — System Understanding

A reference document for explaining **what this system is, what each component does,
how the pieces fit together, and the parameters that govern it.** Written to be
read by a technical audience.

---

## 1. What this project is (one paragraph)

This is a **fully containerized, reproducible Retrieval-Augmented-Generation (RAG)
evaluation harness** whose real purpose is to **benchmark a CPU LLM-inference
backend** — specifically to measure the effect of AMD's **ZenDNN** acceleration
library for `llama.cpp` against a plain (baseline) build, on a *complete, realistic
RAG pipeline* (embed a query → vector search → build a prompt → generate an answer →
grade it). Everything runs in Docker: the LLM server, the embedding server, the
RAG application, the metrics stack, and the CI controller. The only host
requirement is Docker + Docker Compose and the model files. Two things make the
numbers trustworthy: (a) **the model, documents, and questions are held identical**
across the A/B, so only the inference backend differs; (b) **per-query timings are
read straight from `llama.cpp`'s own Prometheus counters**, not estimated.

---

## 2. The big picture (data + control flow)

```
                              ┌──────────────────────────────────────────────┐
                              │                  HARNESS                      │
                              │  (Python; ingest.py / evaluate.py / report*)  │
                              └───────┬──────────────────────────┬───────────┘
            bulk embed + write vectors│                          │ HTTP query (one per question)
                                      ▼                          ▼
   ┌───────────────┐  embeddings ┌─────────────┐         ┌──────────────────────┐
   │  llama-embed  │◀────────────│   LiteLLM    │◀────────│     AnythingLLM       │
   │  (llama.cpp,  │   (OpenAI    │   proxy      │  embed  │  (RAG orchestrator)   │
   │  nomic-embed) │    /v1)      │  + Prom      │         │  + LanceDB (vectors)  │
   └───────────────┘             │  metrics     │  chat   └──────────┬───────────┘
   ┌───────────────┐   tokens    │              │◀───────────────────┘ retrieves top-K
   │  llama-chat   │◀────────────│              │                       chunks, builds
   │  (llama.cpp,  │             └──────┬───────┘                       prompt, calls chat
   │  the model    │                    │ scrape /metrics
   │  under test)  │             ┌──────▼───────┐     ┌─────────┐
   └───────────────┘             │  Prometheus  │────▶│ Grafana │  (dashboards)
        ▲ ▲                      │ + pushgateway│     └─────────┘
        └─┴─ per-query /metrics counter deltas read by the harness
```

**Two phases:**

1. **Ingest (one-time per corpus).** The harness reads the document corpus,
   embeds every chunk against `llama-embed`, and writes the resulting vectors
   **straight into AnythingLLM's LanceDB table** (bypassing slow per-document HTTP
   uploads). This is done once; the corpus is then frozen and reused for every
   benchmark so retrieval is identical across runs.

2. **Evaluate (repeatable).** For each test question the harness calls
   AnythingLLM, which: embeds the question (via LiteLLM → `llama-embed`), does a
   vector search in LanceDB for the top-K chunks, stuffs them into a prompt, and
   calls the chat model (via LiteLLM → `llama-chat`) to generate an answer. The
   harness records per-stage timing/throughput and then an **LLM-as-judge** grades
   the answer against the reference. A report aggregates everything.

---

## 3. Components — what each does and how

### 3.1 `llama-chat` — the LLM under test
- **What:** a `llama.cpp` `llama-server` serving the chat/generation model over an
  OpenAI-compatible HTTP API, and exposing a Prometheus `/metrics` endpoint.
- **How:** built from source into a Docker image (`docker/llama/Dockerfile`),
  `-march=native`, CPU-only. The **same image can be built two ways**:
  - `nqrag-llama:baseline` — ggml CPU only (`GGML_ZENDNN=OFF`)
  - `nqrag-llama:zendnn` — ggml CPU **+ ZenDNN** backend (`GGML_ZENDNN=ON`)
  The two images are pinned to the **same llama.cpp commit** so the A/B is fair.
- **Why this matters:** this is the component whose performance the whole project
  exists to measure. The model is mounted read-only (never baked into the image).

### 3.2 `llama-embed` — the embedding server
- **What:** a second `llama.cpp` `llama-server` running the embedding model
  (`nomic-embed-text-v1.5`, **768-dim** output) to turn text into vectors.
- **How:** same image as `llama-chat`; the only difference between the two
  containers is which model is mounted and the command flags. Used both at ingest
  (bulk) and at query time (one embed per question).

### 3.3 LiteLLM — the OpenAI-compatible proxy + metrics gateway
- **What:** a single OpenAI-compatible endpoint (`/v1`) in front of both llama
  servers, exposing two logical models: `chat-model` and `embed-model`.
- **How:** config in `conf/litellm.yaml`. AnythingLLM talks only to LiteLLM, not
  to the llama servers directly. LiteLLM also emits Prometheus metrics (token
  usage, request latency) — the harness reads the **embedding latency** for each
  query from LiteLLM's histogram. `embed-model` is tagged `mode: embedding` so
  LiteLLM health-checks it correctly.

### 3.4 AnythingLLM — the RAG orchestrator + vector store
- **What:** the actual RAG application. Owns the **LanceDB** vector database, does
  the retrieval, prompt assembly, and the chat call. Queried over its REST API.
- **How:** the harness calls `POST /api/v1/workspace/<SLUG>/stream-chat` in
  **query mode** (answers *only* from retrieved context, no model world-knowledge
  fallback). Retrieval returns the top **`RETRIEVAL_TOPN` (=5)** chunks above a
  similarity threshold (0.0 = no floor). The vector table is named after the
  workspace **slug** (`squad-bench`) and lives in the `anythingllm-storage` Docker
  volume.
- **Key implementation fact:** ingest writes vectors **directly** into the LanceDB
  table (schema: `id, vector(float32[768]), text, title, url`). AnythingLLM's
  query path only needs a populated table named after the slug — verified against
  the AnythingLLM + LanceDB versions in use.

### 3.5 Prometheus + pushgateway + Grafana — observability
- **Prometheus** scrapes the llama servers and LiteLLM and stores the time series.
- **pushgateway** receives metrics from short-lived jobs.
- **Grafana** provides dashboards (`conf/grafana/...`, the `rag-flow` dashboard).
- **Role in correctness:** the per-query numbers used in the report do **not** come
  from Prometheus aggregates — the harness scrapes the llama `/metrics` endpoints
  directly before/after each query for clean deltas. Prometheus/Grafana are for
  human-facing dashboards and aggregate views.

### 3.6 The harness — `ingest.py` / `evaluate.py` / `report*.py`
- **What:** the Python container (`nqrag-harness:local`) that drives everything.
- **`ingest.py`** builds the corpus + test set from the dataset, then
  **`bulk_ingest.py`** embeds and writes the vectors.
- **`evaluate.py`** runs the questions, captures metrics, and judges answers.
- **`report.py`** (single run) / **`report_ab.py`** (baseline-vs-zendnn) render
  Markdown + JSON reports.

### 3.7 `seed` — one-shot configuration service
- **What:** a short-lived container that configures AnythingLLM on `up` (API key,
  text-splitter/chunk settings) by writing directly to its SQLite DB on the shared
  volume, so a bare `docker compose up` is self-configuring (no manual UI setup).

### 3.8 Jenkins — the regression-watch CI controller
- **What:** a Jenkins controller in its **own** compose project (`nqrag-ci`) that
  runs the benchmark on a schedule and flags performance/accuracy regressions.
- **How:** configured entirely by code (JCasC, `docker/jenkins/casc.yaml` +
  `seed_job.groovy`) — comes up with one job, `zendnn-regression-watch`, already
  created. It uses **Docker-out-of-Docker** (mounts the host `docker.sock` and
  bind-mounts the repo at the *same absolute path* as the host) and **host
  networking** so the benchmark containers it launches behave exactly as a
  hand-run would. Details in §7.

---

## 4. The two pipelines in detail

### 4.1 Ingest (build the knowledge base)
1. Read the source file. **Current deployment uses a local SQuAD JSONL**
   (`INGEST_SOURCE=squad`): each row has `question`, `context`, `answer`,
   `all_answers`.
2. **Corpus = the `context` fields.** Unique contexts are de-duplicated into
   documents (`doc_NNNNN.txt`). With `DOC_N=0` *all* unique contexts are
   ingested (~**18,891** documents for this file).
3. **Chunking is disabled** (`EMBED_NO_SPLIT=1`): each context is short enough
   (≤ 653 words, ~820 tokens, under the embed context window) to be **one whole
   chunk**, so retrieval returns complete, coherent passages. The windowed
   splitter is left intact in code — only bypassed for this corpus.
4. **Test set = questions + answers.** `EVAL_N=100` questions are sampled
   **evenly across the file** (not the first N — adjacent SQuAD rows share
   contexts) and their golden answers come from `all_answers`. The contexts that
   answer the eval questions are guaranteed to be in the corpus (so every question
   is answerable).
5. **Embed + store.** `bulk_ingest.py` embeds all chunks in parallel and writes
   them into the `squad-bench` LanceDB table. For the one-time ingest the system
   spins up **32 data-parallel embed instances × 12 threads** (= all 384 logical
   CPUs on the 2×96-core box), shards the corpus across them, then tears them down.

### 4.2 Evaluate (measure)
For each question (run **serially** so metric deltas are uncontaminated):
1. Snapshot `llama-chat` `/metrics` counters + LiteLLM embed-latency counters
   **before** the call.
2. Call AnythingLLM (`stream-chat`, query mode, a **unique session per query** so
   there's no chat-history carryover). AnythingLLM embeds the question, retrieves
   top-5 chunks, builds the prompt, and streams the answer.
3. Snapshot the counters **after**, and compute the per-stage deltas (§5).
4. **Judge** the answer with an external LLM-as-judge (after the snapshot, so the
   judge call never pollutes the measured counters).
5. Append one structured record to `metrics.jsonl`.

A configurable number of **warmup** queries (`WARMUP=1`) run first and are
**excluded** from results (they absorb model load / cache fill). `EVAL_LIMIT=10`
caps how many of the 100 drawn questions are actually measured.

---

## 5. What is measured, and from where (the credibility section)

Per query, the harness records:

| Metric | Meaning | Source (how it's obtained) |
|---|---|---|
| `total_s` | end-to-end wall time | harness clock: request → SSE close |
| `ttft_s` | time to first token | harness: first `textResponse` chunk |
| `embed_s` | query-embedding time | LiteLLM latency histogram delta for `embed-model` |
| `prefill_s` | prompt processing time | `llamacpp:prompt_seconds_total` delta on `llama-chat` |
| `decode_s` | generation time | `llamacpp:tokens_predicted_seconds_total` delta |
| `retrieval_s` | vector search + prompt build | derived: `max(0, ttft − embed − prefill)` |
| `prefill_tps` | prompt throughput (tok/s) | `prompt_tokens` delta / `prefill_s` |
| `decode_tps` | generation throughput (tok/s) | `completion_tokens` delta / `decode_s` |
| `prompt/completion/total_tokens` | token counts | `llama.cpp` counter deltas |
| `match` / `judge_score` / `judge_verdict` | correctness | LLM-as-judge (≥ `JUDGE_THRESHOLD`) |
| `contains_ref` | lexical hit (model-independent) | reference string present in answer (true/false) |

**Why the design is defensible:**
- **Counter deltas, not estimates.** `prefill`/`decode` time and token counts come
  from `llama.cpp`'s own counters — the server's ground truth.
- **Serial execution.** Queries never overlap, so a before/after delta is purely
  that one query.
- **Two independent correctness signals.** The **LLM judge** (semantic) *and*
  **`contains_ref`** (lexical, model-independent). The latter survives even when
  the judge is disabled, so a "fast but garbage" backend is still detectable.
- **`prefill_tps` / `decode_tps` are the headline numbers** because throughput
  (tokens/sec) is workload-independent — the fair way to compare backends.

---

## 6. The ZenDNN A/B benchmark

**Goal:** same model, same documents, same questions — change *only* the
`llama.cpp` backend and measure the difference.

- `run_ab.sh` runs **two jobs strictly sequentially** (never concurrently, so they
  never contend for CPU):
  1. **baseline** — `llama-chat` recreated on `nqrag-llama:baseline`
  2. **zendnn** — `llama-chat` recreated on `nqrag-llama:zendnn`, with
     `ZENDNNL_MATMUL_ALGO=AB_ZENDNN_ALGO` (=1).
- Only the **chat image is swapped** between jobs (`docker-compose.ab.yml`); the
  corpus, the embed server, and the queries are untouched.
- **Fixed-decode mode** (`AB_FIXED_DECODE=128`): both backends are forced to emit
  exactly 128 decode tokens/query. This isolates a clean **throughput/latency**
  comparison (it is a *performance* comparison, **not** an answer-quality one in
  that mode — quality is tracked separately via `contains_ref`).
- Output: `report_ab.{md,json}` with per-stage latency, throughput, speedup
  ratios, **plus a built-in guard**: if the zendnn job's lexical hit-rate collapses
  relative to baseline, the report flags any speedup as **"fast-but-wrong"** rather
  than presenting it as a win.

---

## 7. The regression watch (Jenkins CI) — and the per-run artifacts

`llama.cpp` and ZenDNN are moving open-source projects. A fresh rebuild from
latest source can silently make ZenDNN faster **or slower** than last week. The CI
catches this. Each scheduled run (`ci/run_ci.sh`):

1. **Fresh-pull rebuild** (`FRESH_BUILD=1`, the scheduled default): re-clone latest
   `llama.cpp` HEAD + re-fetch public ZenDNN, rebuild both images `--no-cache`.
   The exact built commit SHA is recorded with the result. (For a quick wiring
   test, `FRESH_BUILD=0` reuses existing images.)
2. **Reuse the ingested corpus** — never re-ingests, so documents/retrieval are
   identical over time and the *only* variable is the rebuilt backend.
3. **Multi-model sweep** — the CI evaluates **every chat model** in `CHAT_MODELS_DIR`
   (a host dir of GGUFs; symlinks are dereferenced to their target under
   `MODELS_DIR`). For each model it swaps `llama-chat` and runs the full A/B
   (`run_ab.sh`) over `CI_EVAL_LIMIT` (=10) queries per backend. The per-question
   metrics of all models are tagged with the model name and merged. `CHAT_MODELS_DIR`
   is **required** — the CI errors out (no single-model fallback) if it is unset/empty.
4. **Compare** (strictly **ZenDNN→ZenDNN across time**, the baseline column is not
   what's tracked).

**Comparison is two-layered:**

- **Aggregate watchdog** (`ci/compare_zendnn.py`): per model, diffs that model's
  headline throughput (`prefill_tps`, `decode_tps`) against its own previous run;
  emits a one-line verdict — **SPEEDUP / NEUTRAL / DEGRADE** — using
  `CI_CMP_THRESHOLD_PCT` (=±5%). Verdicts are **informational, per-model: the build
  is NOT gated** (a multi-model run never marks the build UNSTABLE); the combined
  `verdict.txt` lists each model's verdict.

- **Per-question comparison** (`ci/compare_rows.py`): drills below the aggregate
  verdict to the level of individual questions. Each run captures two per-question
  metrics files — `metrics_baseline` (plain **ggml**) and `metrics_zendnn` — and the
  previous run's pointer supplies the same two from last time, giving four datasets:
  `ggml_prev`, `zendnn_prev`, `ggml_curr`, `zendnn_curr`. It emits **four** CSVs,
  each named for exactly what it compares (left → right; the `*_prev` columns are the
  left side, `*_curr` the right):

  | CSV | Compares | Tells you |
  |---|---|---|
  | `cmp_ggml-prev_to_zendnn-prev_<TS>.csv`   | ggml_prev → zendnn_prev   | backend effect, frozen at last build |
  | `cmp_ggml-prev_to_ggml-curr_<TS>.csv`     | ggml_prev → ggml_curr     | plain-backend drift across time |
  | `cmp_zendnn-prev_to_zendnn-curr_<TS>.csv` | zendnn_prev → zendnn_curr | **ZenDNN drift across time** (the regression watch) |
  | `cmp_ggml-curr_to_zendnn-curr_<TS>.csv`   | ggml_curr → zendnn_curr   | backend effect, this build (the live A/B) |

  Every CSV has the **same fixed columns**, and carries **one row per (model,
  question)** — all swept models in the one file, distinguished by the first column:
  `chat_model_name`, `question`, `accuracy_prev`/`accuracy_curr` (`correct`/`incorrect`)
  + `accuracy_tag`, `prompt_size`, `prefill_tps_prev`/`_curr`/`_delta_percentage` +
  `prefill_perf_tag`, `decode_token_size`, `decode_tps_prev`/`_curr`/`_delta_percentage`
  + `decode_perf_tag`. The delta is a plain percent change, `(curr − prev) / prev × 100`
  (positive = the right side is faster); a question that flipped **correct→incorrect**
  is tagged `DEGRADED`. Throughput tags are `SPEEDUP`/`NEUTRAL`/`DEGRADE` against
  `CI_CMP_THRESHOLD_PCT`. On the very first run the across-time CSVs are empty (no
  previous run yet); the within-run A/B (`ggml_curr → zendnn_curr`) is always populated.

**Where everything lives — `CI_ARTIFACT_DIR`.** *Everything* persistent lives under
one configurable root (default `<repo>/ci`), bind-mounted into the Jenkins container
at its identical absolute path — both the CI outputs (runs/history/reports) **and the
Jenkins controller's home** (`jenkins_home/`: build history shown in the UI, console
logs, archived artifacts, build-number counter, job config). There are **no
docker-managed named volumes** — the mounted dir is the single source of truth. So
repointing `CI_ARTIFACT_DIR` at a fresh directory (dir1 → dir2) and restarting gives
**total isolation**: Jenkins boots a fresh `jenkins_home` from dir2, so dir1's builds
and history vanish from the UI; and the pipeline finds no `prev_run.json`/
`zendnn_history`, so it begins from BASELINE and never compares against dir1. JCasC
(mounted read-only) re-creates the job on every boot, so a fresh home still comes up
fully configured. Artifacts produced every run (never touching `data/results` or the
hand-curated `reports/`):

| Artifact | What it is |
|---|---|
| `$CI_ARTIFACT_DIR/jenkins_home/` | **Jenkins controller home** — build history/console logs/archived artifacts/job config shown in the UI (only path that isn't host-chowned; stays root-owned controller state) |
| `$CI_ARTIFACT_DIR/runs/<TS>/report_ab_<model>_<TS>.{md,json}` | per-model A/B report snapshot |
| `$CI_ARTIFACT_DIR/runs/<TS>/cmp_*_<TS>.csv` | the **four** per-question comparison CSVs (all models, table above) |
| `$CI_ARTIFACT_DIR/runs/<TS>/verdict.{md,txt}` | combined per-model verdicts (`verdict_<model>.{md,txt}` per model) |
| `$CI_ARTIFACT_DIR/runs/<TS>/metrics_{baseline,zendnn}_<TS>.jsonl` | merged per-query metrics (model-tagged) |
| `$CI_ARTIFACT_DIR/history/prev_run.json` | **persistent pointer to the previous run** (both metrics files), updated each run |
| `$CI_ARTIFACT_DIR/history/per_model/<model>/zendnn_history.jsonl` | per-model across-time aggregate series |
| `$CI_ARTIFACT_DIR/reports/` (flat archive) | timestamped copies of every run's reports/CSVs/verdict + `index.csv` |

The **`prev_run.json` pointer** is the mechanism that defines "previous run": each
run reads it to find what to compare against, then overwrites it to point at itself
— so the next run sees this one as its baseline. All kept filenames carry the
`<TS>` timestamp so historical runs never collide.

**Schedule:** the job runs on a **30-minute test cron** (`H/30 * * * *`) defined in
`docker/jenkins/seed_job.groovy`. For production, switch to weekly
(`H H(0-6) * * 1`). Concurrent builds are disabled (a run can outlast the cron, and
two runs would fight over the benchmark containers).

---

## 8. Parameters you should know (current deployment)

All configuration is in **`.env`** (Docker stack reads it via Compose
substitution). Nothing is hardcoded.

### Models & dataset
| Param | Value | Meaning |
|---|---|---|
| `CHAT_MODEL_PATH` | `Llama-3.1-8B-Instruct-q8_0.gguf` | single chat model for the base stack / manual A/B |
| `CHAT_MODELS_DIR` | `/scratch/.../symlinks` | dir of chat GGUFs the **CI sweeps** (one A/B per model); required for CI |
| `EMBED_MODEL_PATH` | `nomic-embed-text-v1.5.f32.gguf` | embedding model (768-dim) |
| `INGEST_SOURCE` / `SLUG` | `squad` / `squad-bench` | dataset mode + LanceDB/workspace name |
| `EMBED_NO_SPLIT` | `1` | one context = one chunk (no windowing) |
| `DOC_N` | `0` | ingest ALL unique contexts (~18,891) |
| `EVAL_N` | `100` | test questions drawn (sampled evenly) |
| `EVAL_LIMIT` | `10` | of those, how many are actually measured |
| `WARMUP` | `1` | leading warmup queries, excluded from results |

### Inference / serving
| Param | Value | Meaning |
|---|---|---|
| `CHAT_CTX` | `16384` | chat context window |
| `CHAT_THREADS` | `96` | one thread per physical core of NUMA node 1 |
| `CHAT_NGL` / `EMBED_NGL` | `0` | GPU layers (0 = **CPU-only**) |
| `EMBED_CTX` | `2048` | embed context window |
| `RETRIEVAL_TOPN` | `5` | chunks retrieved per query |
| `EMBED_INGEST_INSTANCES × _THREADS_PER` | `32 × 12` | data-parallel embed fleet for one-time ingest |

### Judging
| Param | Value | Meaning |
|---|---|---|
| `JUDGE_BASE_URL` / `JUDGE_MODEL` | OpenRouter / `deepseek/deepseek-chat` | external LLM-as-judge |
| `JUDGE_THRESHOLD` | `0.5` | judge score ≥ this counts as a match |

### A/B and CI
| Param | Value | Meaning |
|---|---|---|
| `AB_ZENDNN_ALGO` | `1` | ZenDNN matmul algorithm for the zendnn job |
| `AB_FIXED_DECODE` | `128` | force exactly 128 decode tokens/query (perf parity) |
| `CI_EVAL_LIMIT` | `10` | queries per backend per model in a CI run |
| `CI_CMP_THRESHOLD_PCT` | `5` | ±% that counts as SPEEDUP/DEGRADE |
| `CI_ARTIFACT_DIR` | `<repo>/ci` | single root for ALL persistent CI state — runs/history/reports **and** `jenkins_home/` (UI build history); no named volumes. Repoint to fully isolate/reset history (UI + comparison both follow it) |
| Jenkins cron | `H/30 * * * *` | every 30 min (testing cadence) |

### Hardware pinning (NUMA)
The deployment box is a **2-socket AMD EPYC 9R14** (node 0 = CPUs 0–95, node 1 =
96–191). Decode is memory-bandwidth-bound, so each service is pinned to a distinct,
non-overlapping CPU range and the llama servers bind their **memory** to the local
NUMA node:
- `llama-chat`: CPUs `96–191`, memory node `1` (owns all of socket 1).
- `llama-embed`: CPUs `0–15`, memory node `0`; support services share node 0.
- Enforced via Docker `cpuset` (CPUs) + `numactl --membind` (memory, needs the
  `SYS_NICE` capability, already granted).

### Ports (host)
chat `8081` · embed `8082` · LiteLLM `4000` · Prometheus `9090` · AnythingLLM
`3001` · Grafana `3000` · Jenkins `8088`.

---

## 9. Key facts, scope, and caveats (state these to the client)

- **CPU-only by design.** The whole point is benchmarking the *CPU* inference path
  (ZenDNN targets AMD CPUs). GPU is not wired up.
- **`-march=native` images are not portable** across CPU microarchitectures — each
  host builds its own. Fine here (single benchmark box); don't copy a built image
  to a different-CPU machine.
- **The A/B is fair by construction:** identical model weights, identical frozen
  corpus, identical questions, both backend images pinned to the same llama.cpp
  commit, jobs run sequentially.
- **Fixed-decode A/B measures *speed*, not *quality*.** Answer quality is tracked
  separately (LLM judge + lexical `contains_ref`), and the report explicitly flags
  a backend that got *faster but wrong* so a misleading "speedup" can't slip
  through.
- **Reproducibility vs. freshness trade-off:** the CI deliberately rebuilds from
  *latest* source to track upstream drift, recording the exact commit each time. To
  freeze a benchmark, pin `LLAMA_CPP_REF`.
- **Models are never shipped or downloaded** — they're mounted read-only from the
  host; the containers fail fast with a clear error if a model path is wrong.
- **State that persists in Docker volumes:** the vector DB (`anythingllm-storage`,
  holds the 18,891-vector `squad-bench` table) and Jenkins config/history
  (`jenkins-home`). `make down` keeps volumes; `make clean-all` drops them.
- **Two independent stacks share this repo:** the Docker stack (this document) and
  a Docker-free "native" twin under `native/` that runs the same pipeline as plain
  user processes. They never share state.

---

## 10. Operating cheat-sheet

```bash
# Bring the stack up + configure AnythingLLM
./setup.sh                 # (or: make up)

# One-time: ingest the corpus into the vector DB
make ingest                # builds eval set + embeds ~18,891 contexts

# Repeatable: measure + report (single backend)
make evaluate && make report

# Build both backend images, then run the baseline-vs-zendnn A/B
make build-llama
make ab                    # → data/results/report_ab.{md,json}

# Regression CI
make ci                    # one cycle by hand (FRESH_BUILD=0 = quick)
make jenkins-up            # start the scheduler → http://localhost:8088 (admin/admin)
make jenkins-down

# Lifecycle
make ps | make logs | make down       # down keeps volumes
make clean | make clean-all            # clean-all drops volumes (vectors, jenkins)
```

**Remote access to the Jenkins UI** (from a laptop, over SSH):
```bash
ssh -L 8088:localhost:8088 <user>@<benchmark-box>
# then open http://localhost:8088  (admin / admin)
```
