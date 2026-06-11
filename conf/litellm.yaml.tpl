model_list:
  - model_name: chat-model
    litellm_params:
      model: openai/local-chat
      api_base: http://127.0.0.1:${CHAT_PORT}/v1
      api_key: "sk-noauth"
  - model_name: embed-model
    litellm_params:
      model: openai/local-embed
      api_base: http://127.0.0.1:${EMBED_PORT}/v1
      api_key: "sk-noauth"
    # REQUIRED: without mode: embedding LiteLLM health-probes this endpoint
    # with a chat completion, flags it unhealthy, and AnythingLLM silently
    # returns empty answers (textResponse=None).
    model_info:
      mode: embedding
litellm_settings:
  callbacks: ["prometheus"]
  drop_params: true
  require_auth_for_metrics_endpoint: false
general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
