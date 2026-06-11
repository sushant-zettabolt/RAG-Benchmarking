#!/usr/bin/env bash
# Load stack images previously exported by save_images.sh (after `git lfs pull`).
# Lets a teammate run the stack with no registry access.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d images ] || ! ls images/*.tar >/dev/null 2>&1; then
    echo "No images/*.tar found. Run 'git lfs pull' first (or ./scripts/save_images.sh)." >&2
    exit 1
fi

for tar in images/*.tar; do
    echo "[load] $tar"
    docker load -i "$tar"
done
echo "[load] done. Now: ./setup.sh"
