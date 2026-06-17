# Convenience wrappers around docker compose. Host needs only docker + compose.
DC := docker compose
RUN := $(DC) run --rm harness python

.PHONY: help setup up down logs ps ingest evaluate report all clean clean-all \
        build build-llama save-images load-images

help:
	@echo "Targets:"
	@echo "  make setup        bring up the stack + seed AnythingLLM (run this first)"
	@echo "  make ingest       download Google NQ + ingest documents"
	@echo "  make evaluate     run queries against AnythingLLM + LLM judge"
	@echo "  make report       generate results/report.md + report.json"
	@echo "  make all          ingest + evaluate + report"
	@echo "  make build-llama  fetch + build llama.cpp backends (ggml-cpu + zendnn) for the A/B"
	@echo "  make ab           ZenDNN A/B: baseline vs zendnn (sequential) + report"
	@echo "  make up | down | logs | ps    stack lifecycle"
	@echo "  make save-images / load-images   export/import images for git-lfs"
	@echo "  make clean        remove generated data/results (keeps volumes)"
	@echo "  make clean-all    also remove docker volumes (models, vectors)"

setup:
	./setup.sh

up:
	$(DC) up -d llama-chat llama-embed litellm prometheus anythingllm

down:
	$(DC) down

logs:
	$(DC) logs -f --tail 100

ps:
	$(DC) ps

build:
	$(DC) build harness

ingest: build
	$(RUN) ingest.py

evaluate: build
	$(RUN) evaluate.py

report: build
	$(RUN) report.py

all: ingest evaluate report

build-llama:
	./scripts/build_llama.sh

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
