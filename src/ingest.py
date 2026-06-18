"""Ingestion: pull Google Natural Questions, build an answerable document corpus,
upload it into an AnythingLLM workspace, embed it, and record metadata.

Data sources (both are Google NQ derivatives, configurable via env):
  - EVAL_DATASET  (default nq_open):   questions + short reference answers
  - CORPUS_DATASET(default BeIR/nq):   Wikipedia passages used as documents

To make retrieval meaningful, we prefer passages that actually contain one of
the reference answers, so the ingested corpus can answer the eval questions.
"""
import os
import json
import time
import glob
import requests
from datasets import load_dataset

import common as C


def _load(*args, **kwargs):
    """load_dataset that tolerates both parquet and script-based hub datasets
    across datasets versions (some require trust_remote_code for loading scripts)."""
    try:
        return load_dataset(*args, **kwargs)
    except Exception as e:
        msg = str(e).lower()
        if "trust_remote_code" in msg or "loading script" in msg or "custom code" in msg:
            return load_dataset(*args, trust_remote_code=True, **kwargs)
        raise


EVAL_DATASET   = os.environ.get("EVAL_DATASET", "nq_open")
CORPUS_DATASET = os.environ.get("CORPUS_DATASET", "BeIR/nq")
DOC_N          = C.envi("DOC_N", 100)
EVAL_N         = C.envi("EVAL_N", 100)
CORPUS_SCAN    = C.envi("CORPUS_SCAN", 20000)
# NQ passages are short (~120 tokens), so one passage per document never fills a
# 512-token chunk. We pack consecutive passages into each document until it is at
# least DOC_TARGET_TOKENS, so the embedder splits it into full ~512-token chunks;
# retrieving topN of those then yields a multi-thousand-token prompt (heavy
# prefill). topN * chunk_size sets the prompt size: 8 * 512 ~= 4096 tokens.
DOC_TARGET_TOKENS = C.envi("DOC_TARGET_TOKENS", 4096)
# Retrieval: how many chunks to stuff into each prompt. With ~512-token chunks
# (set in scripts/seed_anythingllm.py), topN=6-8 yields a ~3-4k-token prompt =
# a solid, representative prefill workload. A low similarity threshold ensures
# the chunks actually get included.
RETRIEVAL_TOPN = C.envi("RETRIEVAL_TOPN", 8)
RETRIEVAL_SIM_THRESHOLD = C.envf("RETRIEVAL_SIM_THRESHOLD", 0.0)


def load_eval_questions():
    print(f"[ingest] loading {EVAL_N} eval questions from {EVAL_DATASET} ...")
    ds = _load(EVAL_DATASET, split=f"validation[:{EVAL_N}]")
    rows = []
    for i, r in enumerate(ds):
        q = r.get("question") or r.get("text") or ""
        ans = r.get("answer") or r.get("answers") or []
        if isinstance(ans, str):
            ans = [ans]
        rows.append({"id": i, "question": q.strip(), "answers": [a for a in ans if a]})
    return rows


def load_corpus_passages():
    n = max(CORPUS_SCAN, DOC_N) if CORPUS_SCAN else DOC_N
    print(f"[ingest] loading up to {n} passages from {CORPUS_DATASET} corpus ...")
    ds = _load(CORPUS_DATASET, "corpus", split=f"corpus[:{n}]")
    out = []
    for r in ds:
        out.append({"id": str(r.get("_id", len(out))),
                    "title": (r.get("title") or "").strip(),
                    "text": (r.get("text") or "").strip()})
    return out


def _est_tokens(text):
    """Rough token count (~0.75 words/token) — only used to size documents."""
    return int(len(text.split()) / 0.75)


def build_corpus(questions, passages):
    """Pack NQ passages into DOC_N documents of >= DOC_TARGET_TOKENS each, so the
    embedder splits them into full ~512-token chunks and retrieving topN yields a
    multi-thousand-token prompt (a heavy prefill). Answer-bearing passages are
    packed first so questions stay answerable, and we track which document each
    answer landed in."""
    lowered = [(p["title"] + " " + p["text"]).lower() for p in passages]

    # 1. order passages: answer-bearing first (deduped), then the rest in corpus
    #    order. Each question records the passage index that answers it.
    ordered, seen = [], set()
    if CORPUS_SCAN:
        for q in questions:
            terms = [a.lower() for a in q["answers"] if len(a) >= 3]
            if not terms:
                continue
            for pi, hay in enumerate(lowered):
                if any(t in hay for t in terms):
                    if pi not in seen:
                        seen.add(pi)
                        ordered.append(pi)
                    q["doc_idx"] = pi
                    break
    for pi in range(len(passages)):
        if pi not in seen:
            seen.add(pi)
            ordered.append(pi)

    # 2. greedily pack passages into documents of >= DOC_TARGET_TOKENS tokens.
    docs, pidx_to_doc = [], {}
    parts, pidxs, tok = [], [], 0

    def flush():
        nonlocal parts, pidxs, tok
        if not parts:
            return
        fname = f"doc_{len(docs):04d}.txt"
        docs.append((fname, "\n\n".join(parts) + "\n"))
        for pi in pidxs:
            pidx_to_doc[pi] = fname
        parts, pidxs, tok = [], [], 0

    for pi in ordered:
        if len(docs) >= DOC_N:
            break
        p = passages[pi]
        part = f"# {p['title']}\n\n{p['text']}" if p["title"] else p["text"]
        parts.append(part)
        pidxs.append(pi)
        tok += _est_tokens(part)
        if tok >= DOC_TARGET_TOKENS:
            flush()
    if len(docs) < DOC_N:
        flush()   # trailing partial document

    # 3. finalize answerable flags: a question is answerable iff its answer
    #    passage actually landed in one of the written documents.
    for q in questions:
        di = q.pop("doc_idx", None)
        q["doc_file"] = pidx_to_doc.get(di) if di is not None else None
        q["answerable"] = q["doc_file"] is not None

    return docs


def write_docs(docs):
    for old in glob.glob(os.path.join(C.DOCS_DIR, "*.txt")):
        os.remove(old)
    for fname, body in docs:
        with open(os.path.join(C.DOCS_DIR, fname), "w") as f:
            f.write(body)
    print(f"[ingest] wrote {len(docs)} document files to {C.DOCS_DIR}")


def get_or_create_workspace():
    # Check if the workspace already exists before creating — AnythingLLM does
    # NOT deduplicate by name; calling /workspace/new always creates a new slug.
    slug = None
    try:
        ws = requests.get(f"{C.ALLM_URL}/api/v1/workspaces",
                          headers=C.ALLM_HEADERS, timeout=60).json()
        for w in ws.get("workspaces", []):
            if w.get("slug") == C.SLUG or w.get("name") == C.SLUG:
                slug = w["slug"]
                break
    except Exception:
        pass
    if not slug:
        r = requests.post(f"{C.ALLM_URL}/api/v1/workspace/new",
                          headers={**C.ALLM_HEADERS, "Content-Type": "application/json"},
                          json={"name": C.SLUG}, timeout=60)
        try:
            slug = r.json().get("workspace", {}).get("slug")
        except Exception:
            slug = None
    if not slug:
        raise RuntimeError(f"could not create or find workspace '{C.SLUG}'")
    # Configure retrieval so prompts carry a substantial context (bigger prefill).
    try:
        requests.post(f"{C.ALLM_URL}/api/v1/workspace/{slug}/update",
                      headers={**C.ALLM_HEADERS, "Content-Type": "application/json"},
                      json={"topN": RETRIEVAL_TOPN,
                            "similarityThreshold": RETRIEVAL_SIM_THRESHOLD}, timeout=60)
        print(f"[ingest] retrieval: topN={RETRIEVAL_TOPN} "
              f"similarityThreshold={RETRIEVAL_SIM_THRESHOLD}")
    except Exception as e:
        print(f"[ingest] WARNING: could not set topN/threshold: {e}")
    print(f"[ingest] workspace: {slug}")
    return slug


def upload_documents(docs):
    """Upload each doc; return (locations, failures)."""
    locations, failures = [], []
    for i, (fname, _) in enumerate(docs, 1):
        fp = os.path.join(C.DOCS_DIR, fname)
        try:
            r = requests.post(f"{C.ALLM_URL}/api/v1/document/upload",
                              headers=C.ALLM_HEADERS,
                              files={"file": (fname, open(fp, "rb"), "text/plain")},
                              timeout=120)
            j = r.json()
            locs = [d["location"] for d in j.get("documents", []) if d.get("location")]
            if not locs:
                failures.append({"file": fname, "error": f"no location (HTTP {r.status_code})"})
            locations.extend(locs)
        except Exception as e:
            failures.append({"file": fname, "error": str(e)})
        print(f"  uploaded {i}/{len(docs)}  ok={len(locations)} fail={len(failures)}", end="\r")
    print()
    return locations, failures


def embed_documents(slug, locations):
    embedded = 0
    for i in range(0, len(locations), 50):
        batch = locations[i:i + 50]
        try:
            requests.post(f"{C.ALLM_URL}/api/v1/workspace/{slug}/update-embeddings",
                          headers={**C.ALLM_HEADERS, "Content-Type": "application/json"},
                          json={"adds": batch}, timeout=600)
            embedded += len(batch)
        except Exception as e:
            print(f"\n  [warn] embed batch {i} failed: {e}")
        print(f"  embedded {min(i + 50, len(locations))}/{len(locations)}", end="\r")
    print()
    return embedded


def main():
    C.ensure_dirs()
    if not C.ALLM_KEY:
        raise SystemExit("ALLM_KEY is empty — run ./setup.sh first (it generates one).")

    questions = load_eval_questions()
    passages  = load_corpus_passages()
    docs      = build_corpus(questions, passages)
    write_docs(docs)

    with open(C.EVAL_FILE, "w") as f:
        for q in questions:
            f.write(json.dumps(q) + "\n")
    answerable = sum(1 for q in questions if q["answerable"])
    print(f"[ingest] eval set: {len(questions)} questions, {answerable} answerable from corpus")

    slug = get_or_create_workspace()
    locations, failures = upload_documents(docs)
    embedded = embed_documents(slug, locations)

    meta = {
        "timestamp": time.time(),
        "eval_dataset": EVAL_DATASET,
        "corpus_dataset": CORPUS_DATASET,
        "workspace_slug": slug,
        "docs_requested": DOC_N,
        "docs_written": len(docs),
        "docs_uploaded_ok": len(locations),
        "docs_failed": len(failures),
        "failures": failures,
        "embedded": embedded,
        "eval_questions": len(questions),
        "answerable_questions": answerable,
        "corpus_scanned": len(passages),
    }
    with open(C.INGEST_META, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"[ingest] done. {len(locations)}/{len(docs)} docs uploaded, "
          f"{embedded} embedded. metadata -> {C.INGEST_META}")
    if failures:
        print(f"[ingest] {len(failures)} upload failure(s) recorded in metadata.")


if __name__ == "__main__":
    main()
