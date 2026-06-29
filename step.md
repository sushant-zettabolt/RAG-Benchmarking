# Step-by-step setup guide

A detailed, beginner-friendly walkthrough to get this RAG evaluation stack running
on **your own machine** from scratch. Each step says **what** you do, **why**, and
**how to check it worked** before moving on.

If you just want the short version, see the Quick start in [`README.md`](README.md).
For the design/architecture, see [`DOC.md`](DOC.md); for the exact prompts, judge,
and runtime settings, see [`info.md`](info.md).

---

## 0. What you need before you start

| Requirement | Why | How to check |
|---|---|---|
| **Docker Engine + Docker Compose v2** | the whole stack runs in containers | `docker compose version` prints a v2.x version |
| **A few GB of free disk** | container images + built llama.cpp + the vector DB | `df -h .` |
| **Your own model files (GGUF)** | the chat + embedding models are **never** downloaded — you supply them | you have a chat GGUF and an embedding GGUF on disk |
| **Internet access (first run only)** | pulls base images and, for ingest, the dataset | — |
| **(Optional) A multi-core / multi-socket CPU** | for realistic CPU-inference benchmarking + NUMA pinning | `lscpu` |

> **No Docker / no root?** There is a Docker-free twin under `native/` that runs the
> same pipeline as plain user processes. See [`native/README.md`](native/README.md).
> The rest of this guide covers the Docker stack.

---

## 1. Get the code

```bash
git clone <repository-url>
cd <repository-directory>
```

**Check:** you can see `docker-compose.yml`, `Makefile`, `.env.example`, and the
`src/` directory.

---

## 2. Create your configuration (`.env`)

All configuration lives in a single `.env` file — nothing is hardcoded. Start from
the template:

```bash
cp .env.example .env
```

Open `.env` and set, at minimum:

| Variable | Set it to | Notes |
|---|---|---|
| `MODELS_DIR` | the host folder that holds your GGUF files | mounted read-only into the containers at `/models` |
| `CHAT_MODEL_PATH` | the chat model's path **under** `/models` | e.g. `/models/<your-chat-model>.gguf` |
| `EMBED_MODEL_PATH` | the embedding model's path under `/models` | e.g. `/models/<your-embedding-model>.gguf` |

Everything else has a sensible default. Tune later if you want:
- **Context / batch sizes:** `CHAT_CTX`, `EMBED_CTX`, `*_BATCH`.
- **CPU / NUMA pinning:** the `*_CPUSET` and `*_MEMBIND` variables — leave empty for
  the portable default (no pinning). See [§8](#8-optional-tune-cpu--numa-pinning).
- **Judge:** `JUDGE_MODEL` / `JUDGE_BASE_URL` / `JUDGE_THRESHOLD` — by default an
  LLM-as-judge grades answers; you can point it at a local or hosted model.

> **Secrets:** keep API keys (judge key, app keys) in `.env` only. `.env` is
> gitignored — never commit it.

**Check:** `grep -E 'MODELS_DIR|CHAT_MODEL_PATH|EMBED_MODEL_PATH' .env` shows your values.

---

## 3. Put your model files in place

Copy or symlink your chat and embedding GGUFs into `MODELS_DIR` so that
`MODELS_DIR/<CHAT_MODEL_PATH minus /models>` and the embedding equivalent exist.

**Check:** the files referenced by `CHAT_MODEL_PATH` / `EMBED_MODEL_PATH` are present
under `MODELS_DIR`. (If a path is wrong, the `llama-chat` / `llama-embed` containers
exit immediately in step 4 with a clear "model not found" error.)

---

## 4. Bring the stack up

```bash
./setup.sh          # or: docker compose up -d
```

What this does:
- builds the **harness** image and the **baseline** llama.cpp image (the first build
  compiles llama.cpp from source — this takes a few minutes),
- pulls the public images (LiteLLM, AnythingLLM, Prometheus, Grafana, pushgateway),
- starts every service,
- runs a one-shot **`seed`** container that configures AnythingLLM automatically
  (API key, provider, chunking) by writing to its database — so there is **no manual
  UI setup**.

**Check:**
```bash
docker compose ps                       # services should be "running"/"healthy"
curl -s http://localhost:8081/health    # chat server   (CHAT_PORT)
curl -s http://localhost:8082/health    # embed server  (EMBED_PORT)
```
The AnythingLLM UI is at `http://localhost:3001`, Grafana at `http://localhost:3000`.

---

## 5. Ingest the corpus (one time)

```bash
make ingest
```

What this does: reads the document corpus, embeds every chunk against the embedding
server, and writes the resulting vectors **straight into AnythingLLM's vector store**.
It also builds the evaluation question set. This is a **one-time** step — the corpus
is then frozen and reused for every benchmark, so retrieval is identical across runs.

First ingest downloads the dataset, so it needs internet and some disk for the cache.

**Check:** `make ingest` finishes without errors and reports how many documents and
questions were ingested. You can confirm vectors exist by running a query (next step).

---

## 6. Evaluate and produce a report

```bash
make evaluate       # run the questions, capture timings, grade answers
make report         # render data/results/report.md + report.json
```

For each question the harness asks AnythingLLM (which embeds the query, retrieves the
top chunks, builds a prompt, and calls the chat model), records per-stage timing and
throughput straight from llama.cpp's own metrics counters, then grades the answer with
the LLM-as-judge.

`make all` runs **ingest → evaluate → report** in one go.

**Check:** open `data/results/report.md` — you should see per-query and aggregate
latency/throughput and accuracy.

---

## 7. (Optional) Run the ZenDNN A/B benchmark

This compares two llama.cpp backends — a plain **baseline** build vs one built with
AMD's **ZenDNN** acceleration — on the *identical* pipeline (same model, documents,
questions), so only the inference backend differs.

```bash
make build-llama    # build BOTH images (baseline + zendnn) from public source,
                    # pinned to the same llama.cpp commit so the A/B is fair
make ab             # run the baseline job, then the zendnn job, then the A/B report
```

`run_ab.sh` swaps only the chat image between jobs and runs them **strictly
sequentially**, so they never compete for CPU.

**Check:** `data/results/report_ab.md` shows baseline-vs-zendnn per-stage latency,
throughput, and speedup ratios (plus a guard that flags a backend that got
*faster but wrong*).

---

## 8. (Optional) Tune CPU / NUMA pinning

On a multi-socket (NUMA) machine, CPU LLM decode is memory-bandwidth bound: if the
chat server's threads roam across sockets and pull weights over the inter-socket link,
throughput drops. The fix is to pin each service to a distinct, non-overlapping set of
cores and bind the llama servers' **memory** to the same NUMA node as their CPUs.

This is **optional** — leave the variables empty for the portable default. To enable
it, set in `.env`, sized to *your* CPU topology (run `lscpu` to see your nodes/cores):

- `CHAT_CPUSET` / `EMBED_CPUSET` and the `*_CPUSET` for support services — the CPUs
  each container may use (Docker `cpuset`).
- `CHAT_MEMBIND` / `EMBED_MEMBIND` — the NUMA memory node for each llama server.

A worked example for a generic 2-socket box is in [`README.md`](README.md#numa--cpu-pinning).
The llama services need the `SYS_NICE` capability for memory binding — it is already
granted in the compose file.

---

## 9. (Optional) Automate it with the Jenkins regression watch

llama.cpp and ZenDNN are moving projects; a rebuild from latest source can quietly make
ZenDNN faster or slower than last week. The bundled Jenkins CI catches this: on a
schedule it does a fresh-pull rebuild and re-runs the A/B for every model you list,
flagging regressions.

```bash
make jenkins-up     # build + start the controller → http://localhost:8088 (admin/admin)
```

It comes up fully configured (Configuration-as-Code) with one job,
`zendnn-regression-watch`, on a weekly schedule. Click **Build Now** to run immediately.
Set `CHAT_MODELS_DIR` (the dir of chat models to sweep) and `CI_ARTIFACT_DIR` (where all
run history + Jenkins state lives) in `.env` first. Full details are in
[`README.md`](README.md#zendnn-regression-watch-jenkins-ci).

**Remote access to the UI** (from a laptop, over SSH):
```bash
ssh -L 8088:localhost:8088 <user>@<host>
# then open http://localhost:8088
```

---

## 10. Day-to-day lifecycle

```bash
make ps             # status
make logs           # follow logs
make down           # stop containers (keeps volumes / your vector DB)
make clean          # remove generated data + results
make clean-all      # also drop docker volumes (vector DB, etc.)
```

---

## Troubleshooting

Common issues (model path wrong, empty answers, `set_mempolicy` permission errors,
port clashes) and their fixes are listed in the **Troubleshooting** section of
[`README.md`](README.md#troubleshooting).
