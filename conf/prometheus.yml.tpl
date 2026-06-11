global:
  scrape_interval: 5s
scrape_configs:
  - job_name: litellm
    # trailing slash matters: /metrics returns a 307 redirect
    metrics_path: /metrics/
    authorization:
      credentials: ${LITELLM_MASTER_KEY}
    static_configs:
      - targets: ['127.0.0.1:${LITELLM_PORT}']
  - job_name: llamacpp_chat
    static_configs:
      - targets: ['127.0.0.1:${CHAT_PORT}']
  - job_name: llamacpp_embed
    static_configs:
      - targets: ['127.0.0.1:${EMBED_PORT}']
