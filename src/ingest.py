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
# Retrieval: how many chunks to stuff into each prompt. Higher topN (and a low
# similarity threshold so they actually get included) yields larger prompts =
# a heavier, more representative prefill workload for the ZenDNN A/B.
RETRIEVAL_TOPN = C.envi("RETRIEVAL_TOPN", 20)
RETRIEVAL_SIM_THRESHOLD = C.envf("RETRIEVAL_SIM_THRESHOLD", 0.0)
# Bulk ingest: embed chunks ourselves + write vectors directly into AnythingLLM's
# LanceDB (scales to the full corpus). 0 = legacy per-doc HTTP upload path.
BULK_INGEST = os.environ.get("BULK_INGEST", "1").strip().lower() not in ("", "0", "false", "no")


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
    # DOC_N / CORPUS_SCAN == 0 (or empty) means "no cap". If both are unbounded we
    # load the WHOLE corpus (the full BeIR/nq is ~2.68M passages); otherwise we
    # load the larger of the two bounds.
    bounds = [v for v in (CORPUS_SCAN, DOC_N) if v]
    n = max(bounds) if bounds else 0           # 0 -> all
    split = "corpus" if n == 0 else f"corpus[:{n}]"
    print(f"[ingest] loading {'ALL' if n == 0 else f'up to {n}'} "
          f"passages from {CORPUS_DATASET} corpus ...")
    ds = _load(CORPUS_DATASET, "corpus", split=split)
    out = []
    for r in ds:
        out.append({"id": str(r.get("_id", len(out))),
                    "title": (r.get("title") or "").strip(),
                    "text": (r.get("text") or "").strip()})
    return out


def build_corpus(questions, passages):
    """Choose up to DOC_N passages, preferring ones that contain a reference answer.
    DOC_N == 0 means no cap — every loaded passage is ingested. Marks each question
    answerable if a passage carrying its answer is included."""
    # DOC_N == 0 -> ingest all loaded passages (cap = full set).
    cap = DOC_N if DOC_N else len(passages)
    lowered = [(p["title"] + " " + p["text"]).lower() for p in passages]
    chosen_idx = []          # passage indices, in selection order
    seen = set()

    # Scan for answer-bearing passages whenever we have questions to match (this is
    # what makes retrieval evaluable). CORPUS_SCAN == 0 still scans — it means
    # "whole corpus" here, not "skip".
    if questions:
        for q in questions:
            terms = [a.lower() for a in q["answers"] if len(a) >= 3]
            if not terms:
                continue
            for pi, hay in enumerate(lowered):
                if pi in seen:
                    if any(t in lowered[pi] for t in terms):
                        q["doc_idx"] = pi
                        q["answerable"] = True
                        break
                    continue
                if any(t in hay for t in terms):
                    seen.add(pi)
                    chosen_idx.append(pi)
                    q["doc_idx"] = pi
                    q["answerable"] = True
                    break

    # cap answer-bearing passages at `cap`, then top up with leading passages
    chosen_idx = chosen_idx[:cap]
    chosen_set = set(chosen_idx)
    for pi in range(len(passages)):
        if len(chosen_idx) >= cap:
            break
        if pi not in chosen_set:
            chosen_idx.append(pi)
            chosen_set.add(pi)

    # map passage index -> output doc filename, finalize answerable flags
    idx_to_doc = {pi: f"doc_{n:04d}.txt" for n, pi in enumerate(chosen_idx)}
    for q in questions:
        di = q.get("doc_idx")
        q["answerable"] = di in idx_to_doc if di is not None else False
        q["doc_file"] = idx_to_doc.get(di) if q["answerable"] else None
        q.pop("doc_idx", None)

    docs = []
    for pi in chosen_idx:
        p = passages[pi]
        body = (f"# {p['title']}\n\n{p['text']}\n" if p["title"] else p["text"] + "\n")
        docs.append((idx_to_doc[pi], body, p["title"]))
    return docs


def write_docs(docs):
    for old in glob.glob(os.path.join(C.DOCS_DIR, "*.txt")):
        os.remove(old)
    for fname, body, *_ in docs:
        with open(os.path.join(C.DOCS_DIR, fname), "w") as f:
            f.write(body)
    print(f"[ingest] wrote {len(docs)} document files to {C.DOCS_DIR}")


def get_or_create_workspace():
    # REUSE an existing workspace with our slug first. Creating with a duplicate
    # name makes AnythingLLM mint a NEW suffixed slug (e.g. nq-bench-70783785),
    # which would not match SLUG (what evaluate.py queries) and would leave the
    # vectors in an orphan table. So check before creating (idempotent re-ingest).
    slug = None
    try:
        ws = requests.get(f"{C.ALLM_URL}/api/v1/workspaces",
                          headers=C.ALLM_HEADERS, timeout=60).json()
        for w in ws.get("workspaces", []):
            if w.get("slug") == C.SLUG:
                slug = w["slug"]
                print(f"[ingest] reusing existing workspace '{slug}'")
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
        if slug and slug != C.SLUG:
            # AnythingLLM slugified/suffixed the name — warn loudly; evaluate.py
            # queries SLUG, so a mismatch means retrieval would find nothing.
            print(f"[ingest] WARNING: created workspace slug '{slug}' != SLUG '{C.SLUG}'. "
                  f"Set SLUG={slug} or remove the conflicting workspace.")
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
    for i, (fname, *_rest) in enumerate(docs, 1):
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

    with open(C.EVAL_FILE, "w") as f:
        for q in questions:
            f.write(json.dumps(q) + "\n")
    answerable = sum(1 for q in questions if q["answerable"])
    print(f"[ingest] eval set: {len(questions)} questions, {answerable} answerable from corpus")

    # Workspace must exist (slug == LanceDB table name) and carries topN/threshold.
    slug = get_or_create_workspace()

    meta = {
        "timestamp": time.time(),
        "eval_dataset": EVAL_DATASET,
        "corpus_dataset": CORPUS_DATASET,
        "workspace_slug": slug,
        "docs_requested": DOC_N,
        "docs_written": len(docs),
        "eval_questions": len(questions),
        "answerable_questions": answerable,
        "corpus_scanned": len(passages),
    }

    if BULK_INGEST:
        # Scalable path: embed chunks ourselves and write vectors straight into
        # AnythingLLM's LanceDB (no per-doc files, no per-doc HTTP uploads).
        import bulk_ingest
        n_rows, dim = bulk_ingest.bulk_store(slug, docs)
        meta.update({"ingest_mode": "bulk", "embedded": n_rows, "vector_dim": dim,
                     "docs_uploaded_ok": len(docs), "docs_failed": 0, "failures": []})
        print(f"[ingest] done (bulk). {len(docs)} docs -> {n_rows} vectors in LanceDB "
              f"table '{slug}'. metadata -> {C.INGEST_META}")
    else:
        # Legacy path: write files + upload + embed one document at a time.
        write_docs(docs)
        locations, failures = upload_documents(docs)
        embedded = embed_documents(slug, locations)
        meta.update({"ingest_mode": "api", "embedded": embedded,
                     "docs_uploaded_ok": len(locations), "docs_failed": len(failures),
                     "failures": failures})
        print(f"[ingest] done. {len(locations)}/{len(docs)} docs uploaded, "
              f"{embedded} embedded. metadata -> {C.INGEST_META}")
        if failures:
            print(f"[ingest] {len(failures)} upload failure(s) recorded in metadata.")

    with open(C.INGEST_META, "w") as f:
        json.dump(meta, f, indent=2)


if __name__ == "__main__":
    main()
