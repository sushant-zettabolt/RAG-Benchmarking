"""Bulk ingest: embed document chunks against llama-embed in parallel and write
the vectors STRAIGHT into AnythingLLM's LanceDB table (table name = workspace
slug), bypassing the per-document HTTP upload path so the full corpus scales.

Why this is safe (verified against the AnythingLLM image, @lancedb/lancedb 0.15.0):
  * query-mode RAG is gated only on `VectorDb.hasNamespace(slug)` +
    `namespaceCount(slug)` (== LanceDB `table.countRows()`) and retrieval reads
    the LanceDB table directly — SQLite document_vectors/workspace_documents are
    NOT consulted. So a populated table named after the workspace slug is enough.
  * each row is a flat object {id, vector, text, ...metadata}; similarityResponse
    reads `text` for context and spreads the rest as the source. `vector` must be
    a fixed-size float32 list of the embedder's dimension.

Everything is env-driven (see the harness service in docker-compose.yml).
"""
import os
import time
import uuid
import threading
from concurrent.futures import ThreadPoolExecutor

import requests

# One or more embed endpoints. run_ingest.sh sets EMBED_URLS to a comma-separated
# list of data-parallel instances; batches are round-robined across them. Falls
# back to the single EMBED_URL (the persistent llama-embed) if EMBED_URLS is unset.
EMBED_URLS = [u.strip().rstrip("/") for u in
              os.environ.get("EMBED_URLS",
                             os.environ.get("EMBED_URL", "http://llama-embed:8080/v1")).split(",")
              if u.strip()]
EMBED_MODEL_NAME  = os.environ.get("EMBED_MODEL_NAME", "embed-model")
EMBED_REQ_BATCH   = int(os.environ.get("EMBED_REQ_BATCH", "") or 64)      # inputs per request
EMBED_CONCURRENCY = int(os.environ.get("EMBED_CONCURRENCY", "") or 8)     # parallel requests
ALLM_STORAGE      = os.environ.get("ALLM_STORAGE", "/allm-storage")

# Chunking mirrors what the `seed` service writes into AnythingLLM's text splitter
# (words -> chars at ~6 chars/word), capped by the embedder's real capacity so a
# chunk never overflows the embed context (which would 500 / silently truncate).
CHARS_PER_WORD  = 6
CHUNK_WORDS     = int(os.environ.get("EMBED_CHUNK_WORDS", "") or 512)
OVERLAP_WORDS   = int(os.environ.get("EMBED_CHUNK_OVERLAP_WORDS", "") or 100)
MAX_CHUNK_CHARS = int(os.environ.get("EMBED_MAX_CHUNK_CHARS", "") or 8192)
CHUNK_CHARS     = min(CHUNK_WORDS * CHARS_PER_WORD, MAX_CHUNK_CHARS)
OVERLAP_CHARS   = min(OVERLAP_WORDS * CHARS_PER_WORD, max(CHUNK_CHARS - 1, 0))
# EMBED_NO_SPLIT=1 keeps each document as ONE whole chunk (no windowing). Used for
# corpora whose documents already fit the embed context whole (e.g. SQuAD contexts,
# <=653 words). The splitter below is left intact — this only bypasses it.
NO_SPLIT        = os.environ.get("EMBED_NO_SPLIT", "").strip().lower() in ("1", "true", "yes", "on")


def split_text(text, size=CHUNK_CHARS, overlap=OVERLAP_CHARS):
    """Char-window splitter with overlap, breaking on whitespace near the window
    edge. Passages shorter than `size` stay a single chunk (the common NQ case)."""
    text = (text or "").strip()
    if not text:
        return []
    if len(text) <= size:
        return [text]
    chunks, start, n = [], 0, len(text)
    while start < n:
        end = min(start + size, n)
        if end < n:
            br = text.rfind(" ", start + max(size - overlap, 1), end)
            if br > start:
                end = br
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end >= n:
            break
        start = max(end - overlap, start + 1)
    return chunks


def chunk_document(text):
    """Split `text` into chunks for embedding. With EMBED_NO_SPLIT the whole
    document is kept as a single chunk; otherwise the overlap-window splitter runs."""
    if NO_SPLIT:
        t = (text or "").strip()
        return [t] if t else []
    return split_text(text)


def _embed_batch(texts, url):
    r = requests.post(
        f"{url}/embeddings",
        headers={"Authorization": "Bearer sk-noauth", "Content-Type": "application/json"},
        json={"model": EMBED_MODEL_NAME, "input": texts},
        timeout=600,
    )
    r.raise_for_status()
    data = sorted(r.json()["data"], key=lambda d: d.get("index", 0))
    return [d["embedding"] for d in data]


def embed_texts(texts, progress=None):
    """Embed `texts` preserving input order, round-robining batches across all
    EMBED_URLS (data-parallel instances) with a thread pool."""
    batches = list(enumerate(
        (i, texts[i:i + EMBED_REQ_BATCH]) for i in range(0, len(texts), EMBED_REQ_BATCH)))
    out = [None] * len(texts)
    done = {"n": 0}
    lock = threading.Lock()

    def work(k_item):
        k, (start, batch) = k_item
        url = EMBED_URLS[k % len(EMBED_URLS)]          # spread batches over instances
        vecs = _embed_batch(batch, url)
        for j, v in enumerate(vecs):
            out[start + j] = v
        with lock:
            done["n"] += len(batch)
            if progress:
                progress(done["n"], len(texts))

    # At least one worker per endpoint so every instance stays busy.
    workers = max(EMBED_CONCURRENCY, len(EMBED_URLS))
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(work, batches))

    missing = sum(1 for v in out if v is None)
    if missing:
        raise RuntimeError(f"{missing}/{len(texts)} chunks failed to embed")
    return out


def bulk_store(slug, docs, write_batch=2000):
    """Chunk -> embed -> write LanceDB table named `slug`.

    docs: list of (name, body, title). Returns (n_rows, dim).
    """
    import lancedb
    import pyarrow as pa

    # 1) chunk every document
    chunk_texts, metas = [], []
    for (name, body, title) in docs:
        for ci, ch in enumerate(chunk_document(body)):
            chunk_texts.append(ch)
            metas.append((title or "", f"{slug}/{name}#chunk{ci}"))
    if not chunk_texts:
        raise RuntimeError("no chunks to embed (empty corpus?)")
    print(f"[bulk] {len(docs)} docs -> {len(chunk_texts)} chunks; embedding across "
          f"{len(EMBED_URLS)} endpoint(s) (req_batch={EMBED_REQ_BATCH}) ...")

    # 2) embed in parallel
    t0 = time.time()

    def prog(done, total):
        if done % 5000 < EMBED_REQ_BATCH or done >= total:
            rate = done / (time.time() - t0 + 1e-9)
            print(f"  embedded {done}/{total} ({rate:.0f}/s)", end="\r")

    vectors = embed_texts(chunk_texts, progress=prog)
    print()
    dim = len(vectors[0])
    print(f"[bulk] embedded {len(vectors)} chunks (dim={dim}) in {time.time() - t0:.1f}s")

    # 3) write straight into AnythingLLM's LanceDB
    lance_dir = os.path.join(ALLM_STORAGE, "lancedb")
    os.makedirs(lance_dir, exist_ok=True)
    db = lancedb.connect(lance_dir)
    if slug in db.table_names():
        print(f"[bulk] dropping existing table '{slug}'")
        db.drop_table(slug)
    schema = pa.schema([
        pa.field("id", pa.string()),
        pa.field("vector", pa.list_(pa.float32(), dim)),   # fixed-size list = ANN-searchable
        pa.field("text", pa.string()),
        pa.field("title", pa.string()),
        pa.field("url", pa.string()),
    ])
    tbl = db.create_table(slug, schema=schema)

    rows = []
    written = 0
    for i, vec in enumerate(vectors):
        title, url = metas[i]
        rows.append({"id": str(uuid.uuid4()), "vector": vec,
                     "text": chunk_texts[i], "title": title, "url": url})
        if len(rows) >= write_batch:
            tbl.add(rows)
            written += len(rows)
            rows = []
            print(f"  wrote {written}/{len(vectors)} rows", end="\r")
    if rows:
        tbl.add(rows)
        written += len(rows)
    print()
    total = tbl.count_rows()
    print(f"[bulk] LanceDB table '{slug}' now holds {total} rows ({lance_dir})")
    return total, dim
