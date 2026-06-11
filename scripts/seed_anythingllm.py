"""Seed AnythingLLM's SQLite DB with an API key and the LLM/embedder provider
settings. Run INSIDE the anythingllm container (env vars alone are not enough —
DB values override them). Idempotent. Invoked by setup.sh via:

    docker compose exec -T -e ALLM_KEY=... anythingllm python3 - < scripts/seed_anythingllm.py
"""
import os
import sqlite3

DB = "/app/server/storage/anythingllm.db"
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
    ("EmbeddingModelMaxChunkLength", ctx),
    ("GenericOpenAiEmbeddingApiKey", mk),
]
for label, value in settings:
    cur.execute(
        "INSERT INTO system_settings (label, value) VALUES (?, ?) "
        "ON CONFLICT(label) DO UPDATE SET value=excluded.value", (label, value))

conn.commit()
conn.close()
print("provider settings written")
