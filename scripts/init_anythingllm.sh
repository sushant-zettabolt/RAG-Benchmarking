#!/usr/bin/env bash
# First-time AnythingLLM initialization: write the API key and LLM/embedder
# provider settings directly into its SQLite DB (env vars alone are NOT
# enough — DB values override them), then restart the container.
# Idempotent — safe to re-run.
# usage: scripts/init_anythingllm.sh
set -eo pipefail
. "$(dirname "$0")/lib.sh"

[ -n "$ALLM_KEY" ] || die "ALLM_KEY is empty — run setup.sh (it generates one) or set it in config.env"

docker exec \
    -e ALLM_KEY="$ALLM_KEY" \
    -e LITELLM_PORT="$LITELLM_PORT" \
    -e LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
    -e CHAT_CTX="$CHAT_CTX" \
    "$ALLM_CONTAINER" python3 -c "
import os, sqlite3
conn = sqlite3.connect('/app/server/storage/anythingllm.db')
cur = conn.cursor()

key = os.environ['ALLM_KEY']
cur.execute('SELECT COUNT(*) FROM api_keys WHERE secret = ?', (key,))
if cur.fetchone()[0] == 0:
    cur.execute('''INSERT INTO api_keys (secret, name, createdAt, lastUpdatedAt)
                   VALUES (?, 'bench-key', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)''', (key,))
    print('api key inserted')
else:
    print('api key already present')

base = 'http://127.0.0.1:%s/v1' % os.environ['LITELLM_PORT']
mk = os.environ['LITELLM_MASTER_KEY']
ctx = os.environ['CHAT_CTX']
settings = [
    ('LLMProvider',                  'generic-openai'),
    ('EmbeddingEngine',              'generic-openai'),
    ('LLMPreference',                'chat-model'),
    ('EmbeddingModel',               'embed-model'),
    ('GenericOpenAiBasePath',        base),
    ('GenericOpenAiKey',             mk),
    ('GenericOpenAiModelPref',       'chat-model'),
    ('GenericOpenAiTokenLimit',      ctx),
    ('EmbeddingBasePath',            base),
    ('EmbeddingModelMaxChunkLength', ctx),
    ('GenericOpenAiEmbeddingApiKey', mk),
]
for label, value in settings:
    cur.execute('''INSERT INTO system_settings (label, value) VALUES (?, ?)
                   ON CONFLICT(label) DO UPDATE SET value=excluded.value''', (label, value))
conn.commit(); conn.close()
print('provider settings written')
"

docker restart "$ALLM_CONTAINER" >/dev/null
wait_http "http://127.0.0.1:$ALLM_PORT/api/ping" 120 || die "anythingllm did not come back after restart"
log "anythingllm initialized and restarted"
