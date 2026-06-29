# Convenience wrappers around docker compose. Host needs only docker + compose.
DC := docker compose
RUN := $(DC) run --rm harness python

.PHONY: help setup up down logs ps ingest evaluate report all clean clean-all \
        build build-llama save-images load-images \
        ci jenkins-up jenkins-down jenkins-logs

# -p forces an isolated project name. Without it, COMPOSE_PROJECT_NAME from .env
# overrides the compose file's `name:` and Jenkins would share the benchmark
# stack's project (causing "orphan container" churn on `make down`).
DC_JENKINS := docker compose -p nqrag-ci -f docker-compose.jenkins.yml

help:
	@echo "Targets:"
	@echo "  make setup        bring up the stack + seed AnythingLLM (run this first)"
	@echo "  make ingest       download Google NQ + ingest documents"
	@echo "  make evaluate     run queries against AnythingLLM + LLM judge"
	@echo "  make report       generate results/report.md + report.json"
	@echo "  make all          ingest + evaluate + report"
	@echo "  make build-llama  build llama.cpp backend IMAGES (baseline + zendnn) from source for the A/B"
	@echo "  make ab           ZenDNN A/B: baseline vs zendnn (sequential) + report"
	@echo "  make ci           run ONE regression-watch cycle now (rebuild+eval+compare)"
	@echo "  make jenkins-up   build + start the Jenkins CI controller (weekly cron: zendnn watch)"
	@echo "  make jenkins-down | jenkins-logs    Jenkins lifecycle"
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
	./run_ingest.sh

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

# ── ZenDNN regression CI ─────────────────────────────────────────────────────
# One cycle by hand (Jenkins runs this same script on a schedule). FRESH_BUILD=0
# skips the no-cache rebuild for a quick wiring test.
ci:
	bash ci/run_ci.sh

jenkins-up:
	$(DC_JENKINS) up -d --build

jenkins-down:
	$(DC_JENKINS) down

jenkins-logs:
	$(DC_JENKINS) logs -f --tail 100

save-images:
	./scripts/save_images.sh

load-images:
	./scripts/load_images.sh

clean:
	rm -rf data/docs data/results data/eval.jsonl data/ingest_metadata.json

clean-all: down
	$(DC) down -v
