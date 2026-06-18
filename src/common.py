"""Shared helpers for the RAG eval harness: config, AnythingLLM client,
llama.cpp metric scraping, and the LiteLLM judge call.

Everything is configured through environment variables (set in docker-compose.yml
from .env). Nothing is hardcoded to a host/port.
"""
import os
import re
import json
import time
import requests

# ── config (env only) ────────────────────────────────────────────────────────
ALLM_URL          = os.environ.get("ALLM_URL", "http://anythingllm:3001").rstrip("/")
LITELLM_URL       = os.environ.get("LITELLM_URL", "http://litellm:4000").rstrip("/")
LITELLM_METRICS_URL = LITELLM_URL + "/metrics/"   # trailing slash: /metrics 307-redirects
PROM_URL          = os.environ.get("PROM_URL", "http://prometheus:9090").rstrip("/")
CHAT_METRICS_URL  = os.environ.get("CHAT_METRICS_URL", "http://llama-chat:8080/metrics")
EMBED_METRICS_URL = os.environ.get("EMBED_METRICS_URL", "http://llama-embed:8080/metrics")
ALLM_KEY          = os.environ.get("ALLM_KEY", "")
LITELLM_KEY       = os.environ.get("LITELLM_MASTER_KEY", "sk-bench-master")
SLUG              = os.environ.get("SLUG", "nq-bench")
# External judge. When JUDGE_BASE_URL is set, judge_answer() posts to that
# endpoint instead of routing through LiteLLM. Auth: either Bearer token
# (JUDGE_API_KEY) or subscription-key header (JUDGE_SUBSCRIPTION_KEY).
JUDGE_BASE_URL    = os.environ.get("JUDGE_BASE_URL", "").rstrip("/")
JUDGE_API_KEY     = os.environ.get("JUDGE_API_KEY", "")
JUDGE_SUB_KEY     = os.environ.get("JUDGE_SUBSCRIPTION_KEY", "")
DATA_DIR          = os.environ.get("DATA_DIR", "/data")

DOCS_DIR      = os.path.join(DATA_DIR, "docs")
RESULTS_DIR   = os.path.join(DATA_DIR, "results")
EVAL_FILE     = os.path.join(DATA_DIR, "eval.jsonl")
INGEST_META   = os.path.join(DATA_DIR, "ingest_metadata.json")

ALLM_HEADERS = {"Authorization": f"Bearer {ALLM_KEY}"}


def envi(name, default):
    v = os.environ.get(name, "")
    return int(v) if str(v).strip() else int(default)


def envf(name, default):
    v = os.environ.get(name, "")
    return float(v) if str(v).strip() else float(default)


def ensure_dirs():
    os.makedirs(DOCS_DIR, exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)


# ── llama.cpp Prometheus-text metric scraping ────────────────────────────────
# llama.cpp exposes counters like `llamacpp:prompt_tokens_total`,
# `llamacpp:tokens_predicted_total`, `llamacpp:prompt_seconds_total`,
# `llamacpp:tokens_predicted_seconds_total`. We snapshot before/after each query
# and diff to get per-query token usage and per-stage timing.
_METRIC_RE = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+([0-9eE.+-]+)\s*$")


def scrape_metrics(url):
    """Return {metric_name: float} for all unlabeled samples at a /metrics URL.
    Returns {} on any failure (caller treats missing metrics as n/a)."""
    out = {}
    try:
        r = requests.get(url, timeout=5)
        for line in r.text.splitlines():
            if not line or line.startswith("#"):
                continue
            m = _METRIC_RE.match(line)
            if not m:
                continue
            name, _labels, val = m.group(1), m.group(2), m.group(3)
            try:
                out[name] = float(val)
            except ValueError:
                continue
    except Exception:
        pass
    return out


def metric_delta(after, before, name):
    """Counter delta for `name`; None if absent in either snapshot."""
    if name in after and name in before:
        return after[name] - before[name]
    return None


# llama.cpp's embed server does not populate prompt_seconds_total, so embedding
# latency is taken from LiteLLM's per-model request-latency histogram instead.
def scrape_litellm_latency(model):
    """Return (sum_seconds, count) of litellm_request_total_latency_metric for
    requested_model=`model`. (None, None) on failure."""
    sum_v = cnt_v = None
    try:
        r = requests.get(LITELLM_METRICS_URL, timeout=5)
        for line in r.text.splitlines():
            if line.startswith("#") or f'requested_model="{model}"' not in line:
                continue
            try:
                val = float(line.rsplit(None, 1)[1])
            except (ValueError, IndexError):
                continue
            if line.startswith("litellm_request_total_latency_metric_sum"):
                sum_v = val
            elif line.startswith("litellm_request_total_latency_metric_count"):
                cnt_v = val
    except Exception:
        pass
    return sum_v, cnt_v


# ── AnythingLLM ──────────────────────────────────────────────────────────────
def allm_stream_chat(question, mode="query", timeout=600, session_id=None):
    """Send one query to AnythingLLM /stream-chat and parse the SSE stream.

    AnythingLLM emits incremental `textResponse` chunks, then a `close:true`
    chunk, and finally a trailing event carrying the retrieved `sources` array.
    We must keep reading past the first close to capture sources & final text.

    `session_id` scopes the conversation thread. Pass a UNIQUE id per query so
    AnythingLLM does not carry prior answers forward as chat history — otherwise
    each prompt grows by the previous answer's length, inflating prompt_tokens
    and prefill latency and making them diverge between A/B jobs whenever the two
    backends produce different-length answers. Omit only if you intentionally
    want a running conversation.

    Returns dict: {answer, n_sources, wall_s, ttft_s, ok, error}.
    """
    t0 = time.time()
    answer, n_sources, ttft, t_close, ok, err = "", None, None, None, False, None
    url = f"{ALLM_URL}/api/v1/workspace/{SLUG}/stream-chat"
    headers = {**ALLM_HEADERS, "Content-Type": "application/json"}
    body = {"message": question, "mode": mode}
    if session_id is not None:
        body["sessionId"] = session_id
    try:
        with requests.post(url, headers=headers,
                           json=body,
                           stream=True, timeout=timeout) as resp:
            ok = resp.status_code == 200
            if not ok:
                err = f"HTTP {resp.status_code}: {resp.text[:200]}"
            for raw in resp.iter_lines():
                if not raw:
                    continue
                line = raw.decode("utf-8") if isinstance(raw, bytes) else raw
                if not line.startswith("data: "):
                    continue
                try:
                    ev = json.loads(line[6:])
                except Exception:
                    continue
                if ev.get("error"):
                    ok, err = False, str(ev.get("error"))
                txt = ev.get("textResponse")
                if txt:
                    if ttft is None:
                        ttft = time.time() - t0
                    answer += txt
                if isinstance(ev.get("sources"), list) and ev["sources"]:
                    n_sources = len(ev["sources"])
                if ev.get("close") and t_close is None:
                    t_close = time.time()
    except Exception as e:
        ok, err = False, str(e)
    return {
        "answer": answer.strip(),
        "n_sources": n_sources,
        "wall_s": (t_close or time.time()) - t0,
        "ttft_s": ttft,
        "ok": ok and bool(answer.strip()),
        "error": err,
    }


# ── LiteLLM judge ────────────────────────────────────────────────────────────
_JUDGE_SYS = (
    "You are a strict grader for a question-answering system. You are given a "
    "QUESTION, one or more REFERENCE answers considered correct, and a CANDIDATE "
    "answer produced by the system. Decide whether the CANDIDATE is correct: it "
    "is correct if it conveys the same factual answer as any REFERENCE, even if "
    "phrased differently or with extra context. It is incorrect if it states a "
    "different fact, refuses, or says it cannot find the answer. Respond with ONLY "
    "a compact JSON object: {\"score\": <0.0-1.0>, \"verdict\": \"correct\"|"
    "\"incorrect\"|\"partial\", \"reason\": \"<one short sentence>\"}."
)


def judge_answer(question, references, candidate, model, timeout=120):
    """LLM-as-judge via OpenAI-compatible chat completion. Returns
    {score, verdict, reason, raw, usage} (best-effort parse; never raises).

    When JUDGE_BASE_URL + JUDGE_API_KEY are set, calls that endpoint directly
    (e.g. DeepSeek: JUDGE_BASE_URL=https://api.deepseek.com/v1,
    JUDGE_MODEL=deepseek-chat). Otherwise routes through the local LiteLLM proxy.

    We fold grading instructions into a single user turn — some chat templates
    (e.g. Gemma) don't support a system role and silently return empty content.
    We allow enough tokens for reasoning models that emit a preamble before JSON,
    and fall back to reasoning_content when content is empty.
    """
    refs = " | ".join(r for r in references if r) or "(no reference provided)"
    user = (f"{_JUDGE_SYS}\n\nQUESTION: {question}\nREFERENCE(S): {refs}\n"
            f"CANDIDATE: {candidate or '(empty)'}\n\nGrade now.")
    body = {
        "model": model,
        "messages": [{"role": "user", "content": user}],
        "temperature": 0,
        "max_completion_tokens": 2048,
    }
    if JUDGE_BASE_URL and (JUDGE_API_KEY or JUDGE_SUB_KEY):
        url = f"{JUDGE_BASE_URL}/chat/completions"
        hdrs = {"Content-Type": "application/json"}
        if JUDGE_SUB_KEY:
            hdrs["Ocp-Apim-Subscription-Key"] = JUDGE_SUB_KEY
            hdrs["user"] = os.environ.get("USER", "bench")
        if JUDGE_API_KEY:
            hdrs["Authorization"] = f"Bearer {JUDGE_API_KEY}"
    else:
        url = f"{LITELLM_URL}/v1/chat/completions"
        hdrs = {"Authorization": f"Bearer {LITELLM_KEY}",
                "Content-Type": "application/json"}
    try:
        r = requests.post(url, headers=hdrs, json=body, timeout=timeout)
        data = r.json()
        msg = data["choices"][0]["message"]
        content = msg.get("content") or msg.get("reasoning_content") or msg.get("reasoning") or ""
        usage = data.get("usage", {})
        parsed = _parse_judge(content)
        parsed["raw"] = content
        parsed["usage"] = usage
        return parsed
    except Exception as e:
        return {"score": None, "verdict": "error", "reason": str(e),
                "raw": None, "usage": {}}


def _parse_judge(content):
    """Pull a JSON object out of the judge text, tolerating code fences / prose."""
    m = re.search(r"\{.*\}", content, re.DOTALL)
    if m:
        try:
            obj = json.loads(m.group(0))
            score = obj.get("score")
            score = float(score) if score is not None else None
            if score is not None:
                score = max(0.0, min(1.0, score))
            verdict = str(obj.get("verdict", "")).lower().strip() or None
            return {"score": score, "verdict": verdict,
                    "reason": str(obj.get("reason", ""))[:300]}
        except Exception:
            pass
    # fallback: keyword heuristic
    low = content.lower()
    if "incorrect" in low:
        return {"score": 0.0, "verdict": "incorrect", "reason": "parsed from text"}
    if "correct" in low:
        return {"score": 1.0, "verdict": "correct", "reason": "parsed from text"}
    return {"score": None, "verdict": "unparsed", "reason": content[:200]}


def contains_reference(answer, references):
    """Model-independent lexical check: does the answer contain any reference
    answer string (case-insensitive, whitespace-normalized)? A useful ground-truth
    signal alongside the LLM judge."""
    if not answer:
        return False
    a = " ".join(answer.lower().split())
    for ref in references or []:
        r = " ".join(str(ref).lower().split())
        if r and r in a:
            return True
    return False


def wait_http(url, tries=60, delay=2, ok_codes=(200,)):
    for _ in range(tries):
        try:
            if requests.get(url, timeout=5).status_code in ok_codes:
                return True
        except Exception:
            pass
        time.sleep(delay)
    return False
