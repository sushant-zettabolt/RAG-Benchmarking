"""Seed AnythingLLM's SQLite DB with an API key and the LLM/embedder provider
settings. DB values override env vars, so this runs regardless of the anythingllm
container's own environment. Idempotent. The DB path comes from ALLM_DB.

Two ways it runs (same script, same logic):
  - `seed` sidecar (default on `docker compose up`): mounts the anythingllm named
    volume and seeds ALLM_DB=/allm-storage/anythingllm.db. By the time anythingllm
    is healthy, Prisma has created the DB + tables, so the upsert is safe.
  - legacy, inside the anythingllm container (setup.sh):
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
# Chunking: split long documents into ~EMBED_CHUNK_WORDS-word chunks with
# EMBED_CHUNK_OVERLAP_WORDS words of overlap (the overlap is shared on BOTH sides
# of each interior chunk). Passages shorter than the chunk size stay a single
# chunk. With RETRIEVAL_TOPN chunks stuffed per query this sets the prompt size.
#
# IMPORTANT: AnythingLLM's text splitter is langchain's RecursiveCharacterText-
# Splitter with the DEFAULT length function = CHARACTER count, not words/tokens.
# It splits on paragraph/line/word boundaries (never mid-word), so a character
# budget yields chunks of ~N words landing on word boundaries. We express the
# knob in WORDS (user intent) and convert to characters here (~6 chars/word for
# English prose, including the trailing space).
CHARS_PER_WORD = 6
chunk_words   = int(os.environ.get("EMBED_CHUNK_WORDS", "512"))
overlap_words = int(os.environ.get("EMBED_CHUNK_OVERLAP_WORDS", "100"))
chunk_chars   = str(chunk_words * CHARS_PER_WORD)      # 512 words -> 3072 chars
overlap_chars = str(overlap_words * CHARS_PER_WORD)    # 100 words ->  600 chars
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
    # determineMaxChunkSize() caps the splitter chunk size at the embedder's max.
    # NOTE: the BINDING cap the splitter actually uses is the container env
    # EMBEDDING_MODEL_MAX_CHUNK_LENGTH (chars), not this stored value; we set this
    # too for UI consistency. Keep EMBEDDING_MODEL_MAX_CHUNK_LENGTH >= chunk_chars.
    ("EmbeddingModelMaxChunkLength", chunk_chars),
    ("text_splitter_chunk_size",     chunk_chars),
    ("text_splitter_chunk_overlap",  overlap_chars),
    ("GenericOpenAiEmbeddingApiKey", mk),
]
for label, value in settings:
    cur.execute(
        "INSERT INTO system_settings (label, value) VALUES (?, ?) "
        "ON CONFLICT(label) DO UPDATE SET value=excluded.value", (label, value))

conn.commit()
conn.close()
print("provider settings written")
