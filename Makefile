# Convenience wrappers around docker compose. Host needs only docker + compose.
DC := docker compose
RUN := $(DC) run --rm harness python

.PHONY: help setup up down logs ps ingest evaluate report all clean clean-all \
        build build-llama save-images load-images

help:
	@echo "Targets:"
	@echo "  make up           build+start the full stack; seed auto-configures AnythingLLM"
	@echo "  make build-llama  build BOTH llama.cpp images (baseline + zendnn) from source"
	@echo "  make ingest       download Google NQ + ingest documents"
	@echo "  make evaluate     run queries against AnythingLLM + LLM judge"
	@echo "  make report       generate results/report.md + report.json"
	@echo "  make all          ingest + evaluate + report"
	@echo "  make ab           ZenDNN A/B: baseline vs zendnn (sequential) + report"
	@echo "  make down | logs | ps         stack lifecycle"
	@echo "  make save-images / load-images   export/import images for git-lfs"
	@echo "  make clean        remove generated data/results (keeps volumes)"
	@echo "  make clean-all    also remove docker volumes (models, vectors)"

setup:
	./setup.sh

# Bring up the whole stack (builds the baseline llama image + harness on first run,
# pulls public images, and runs the one-shot `seed` service to configure AnythingLLM).
up:
	$(DC) up -d

# Build BOTH llama.cpp images from public source at the SAME commit (fair A/B).
# Honors LLAMA_CPP_REF in .env if set; otherwise resolves master's HEAD once.
build-llama:
	@set -e; \
	get() { grep -E "^$$1=" .env 2>/dev/null | head -1 | cut -d= -f2-; }; \
	REPO="$$(get LLAMA_CPP_REPO)"; REPO="$${REPO:-https://github.com/ggml-org/llama.cpp}"; \
	BASE_IMG="$$(get LLAMA_BASELINE_IMAGE)"; BASE_IMG="$${BASE_IMG:-nqrag-llama:baseline}"; \
	ZEN_IMG="$$(get LLAMA_ZENDNN_IMAGE)"; ZEN_IMG="$${ZEN_IMG:-nqrag-llama:zendnn}"; \
	REF="$$(get LLAMA_CPP_REF)"; \
	if [ -z "$$REF" ]; then \
	  REF="$$(git ls-remote "$$REPO" HEAD | awk '{print $$1}')"; \
	  echo "[build-llama] resolved latest master HEAD = $$REF"; \
	else \
	  echo "[build-llama] using pinned LLAMA_CPP_REF = $$REF"; \
	fi; \
	echo "[build-llama] building $$BASE_IMG (GGML_ZENDNN=OFF) ..."; \
	docker build -t "$$BASE_IMG" --build-arg GGML_ZENDNN=OFF \
	  --build-arg LLAMA_CPP_REPO="$$REPO" --build-arg LLAMA_CPP_REF="$$REF" docker/llama; \
	echo "[build-llama] building $$ZEN_IMG (GGML_ZENDNN=ON) ..."; \
	docker build -t "$$ZEN_IMG" --build-arg GGML_ZENDNN=ON \
	  --build-arg LLAMA_CPP_REPO="$$REPO" --build-arg LLAMA_CPP_REF="$$REF" docker/llama

down:
	$(DC) down

logs:
	$(DC) logs -f --tail 100

ps:
	$(DC) ps

build:
	$(DC) build harness

ingest: build
	./run_ingest.sh

evaluate: build
	$(RUN) evaluate.py

report: build
	$(RUN) report.py

all: ingest evaluate report

ab: build
	./run_ab.sh

report-ab: build
	$(RUN) report_ab.py

save-images:
	./scripts/save_images.sh

load-images:
	./scripts/load_images.sh

clean:
	rm -rf data/docs data/results data/eval.jsonl data/ingest_metadata.json

clean-all: down
	$(DC) down -v
