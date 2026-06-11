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


def build_corpus(questions, passages):
    """Choose DOC_N passages, preferring ones that contain a reference answer.
    Marks each question answerable if a passage carrying its answer is included."""
    lowered = [(p["title"] + " " + p["text"]).lower() for p in passages]
    chosen_idx = []          # passage indices, in selection order
    seen = set()

    if CORPUS_SCAN:
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

    # cap answer-bearing passages at DOC_N, then top up with leading passages
    chosen_idx = chosen_idx[:DOC_N]
    chosen_set = set(chosen_idx)
    for pi in range(len(passages)):
        if len(chosen_idx) >= DOC_N:
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
        docs.append((idx_to_doc[pi], body))
    return docs


def write_docs(docs):
    for old in glob.glob(os.path.join(C.DOCS_DIR, "*.txt")):
        os.remove(old)
    for fname, body in docs:
        with open(os.path.join(C.DOCS_DIR, fname), "w") as f:
            f.write(body)
    print(f"[ingest] wrote {len(docs)} document files to {C.DOCS_DIR}")


def get_or_create_workspace():
    r = requests.post(f"{C.ALLM_URL}/api/v1/workspace/new",
                      headers={**C.ALLM_HEADERS, "Content-Type": "application/json"},
                      json={"name": C.SLUG}, timeout=60)
    try:
        slug = r.json().get("workspace", {}).get("slug")
    except Exception:
        slug = None
    if not slug:
        # already exists — look it up
        ws = requests.get(f"{C.ALLM_URL}/api/v1/workspaces",
                          headers=C.ALLM_HEADERS, timeout=60).json()
        for w in ws.get("workspaces", []):
            if w.get("slug") == C.SLUG or w.get("name") == C.SLUG:
                slug = w["slug"]
                break
    if not slug:
        raise RuntimeError(f"could not create or find workspace '{C.SLUG}'")
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
