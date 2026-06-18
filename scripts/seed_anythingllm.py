"""Seed AnythingLLM's SQLite DB with an API key, the LLM/embedder provider
settings, and the text-splitter chunking knobs. DB values override env vars, so
this must run regardless of the anythingllm container's environment. Idempotent.

Two ways it runs (DB path comes from ALLM_DB):
  - `seed` sidecar (default on `up`): mounts the anythingllm named volume and
    seeds ALLM_DB=/allm-storage/anythingllm.db. By the time anythingllm is
    healthy, Prisma has created the DB + tables, so the upsert is safe.
  - legacy, inside the anythingllm container:
    docker compose exec -T -e ALLM_KEY=... anythingllm python3 - < scripts/seed_anythingllm.py
"""
import os
import sqlite3

DB = os.environ.get("ALLM_DB", "/app/server/storage/anythingllm.db")
conn = sqlite3.connect(DB)
cur = conn.cursor()

key = os.environ["ALLM_KEY"]
cur.execute("SELECT COUNT(*) FROM api_keys WHERE secret = ?", (key,))
if cur.fetchone()[0] == 0:
    cur.execute(
        "INSERT INTO api_keys (secret, name, createdAt, lastUpdatedAt) "
        "VALUES (?, 'bench-key', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", (key,))
    print("api key inserted")
else:
    print("api key already present")

# LiteLLM is reachable from the anythingllm container as the compose service name
base = "http://litellm:4000/v1"
mk   = os.environ["LITELLM_MASTER_KEY"]
ctx  = os.environ.get("CHAT_CTX", "8192")

# Chunking. AnythingLLM's RecursiveCharacterTextSplitter measures in CHARACTERS
# (not tokens/words) and only splits on paragraph/line/word boundaries (never
# mid-word). We expose the knobs in WORDS and convert at ~6 chars/word. Passages
# shorter than the chunk size stay a single chunk; only longer docs get split,
# with `overlap` chars shared on BOTH sides of each interior chunk.
# EmbeddingModelMaxChunkLength is the binding char cap — keep it >= chunk size.
CHARS_PER_WORD   = 6
chunk_words      = int(os.environ.get("EMBED_CHUNK_WORDS", "512"))
overlap_words    = int(os.environ.get("EMBED_CHUNK_OVERLAP_WORDS", "100"))
chunk_chars      = str(chunk_words * CHARS_PER_WORD)        # 512 words -> 3072 chars
overlap_chars    = str(overlap_words * CHARS_PER_WORD)      # 100 words ->  600 chars
max_chunk_chars  = os.environ.get("EMBED_MAX_CHUNK_CHARS", "8192")

settings = [
    ("LLMProvider",                  "generic-openai"),
    ("EmbeddingEngine",              "generic-openai"),
    ("LLMPreference",                "chat-model"),
    ("EmbeddingModel",               "embed-model"),
    ("GenericOpenAiBasePath",        base),
    ("GenericOpenAiKey",             mk),
    ("GenericOpenAiModelPref",       "chat-model"),
    ("GenericOpenAiTokenLimit",      ctx),
    ("EmbeddingBasePath",            base),
    ("EmbeddingModelMaxChunkLength", max_chunk_chars),
    ("GenericOpenAiEmbeddingApiKey", mk),
    ("text_splitter_chunk_size",     chunk_chars),
    ("text_splitter_chunk_overlap",  overlap_chars),
]
for label, value in settings:
    cur.execute(
        "INSERT INTO system_settings (label, value) VALUES (?, ?) "
        "ON CONFLICT(label) DO UPDATE SET value=excluded.value", (label, value))

conn.commit()
conn.close()
print("provider settings written")
