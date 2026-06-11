#!/usr/bin/env bash
# Export all stack images to images/*.tar so they can be committed via git-lfs
# and shipped to machines without registry access. Pair with load_images.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
set -a; [ -f .env ] && . ./.env; set +a

LLAMA_IMAGE="${LLAMA_IMAGE:-ghcr.io/ggml-org/llama.cpp:server}"
LITELLM_IMAGE="${LITELLM_IMAGE:-ghcr.io/berriai/litellm:main-stable}"
PROM_IMAGE="${PROM_IMAGE:-prom/prometheus:latest}"
ALLM_IMAGE="${ALLM_IMAGE:-mintplexlabs/anythingllm:latest}"

mkdir -p images
echo "[save] building harness image ..."
docker compose build harness

echo "[save] pulling service images (if missing) ..."
for img in "$LLAMA_IMAGE" "$LITELLM_IMAGE" "$PROM_IMAGE" "$ALLM_IMAGE"; do
    docker image inspect "$img" >/dev/null 2>&1 || docker pull "$img"
done

save() {  # save IMAGE FILE
    echo "[save] $1 -> images/$2"
    docker save "$1" -o "images/$2"
}
save "$LLAMA_IMAGE"   "llama-cpp-server.tar"
save "$LITELLM_IMAGE" "litellm.tar"
save "$PROM_IMAGE"    "prometheus.tar"
save "$ALLM_IMAGE"    "anythingllm.tar"
save "nqrag-harness:local" "harness.tar"

echo "[save] done. Commit images/*.tar with git-lfs (see .gitattributes)."
du -h images/*.tar
