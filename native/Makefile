# Native (no-Docker) RAG eval stack — convenience wrappers.
#   make -C native setup     one-time: install toolchains + build AnythingLLM
#   make -C native up        start the whole stack (processes, no Docker)
#   make -C native ingest    one-time: load + embed the corpus
#   make -C native bench      repeatable: evaluate + report (no re-ingest)
#   make -C native ab        ZenDNN A/B (baseline vs zendnn) + report
#   make -C native down      stop everything
SHELL := /bin/bash
HERE  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help setup up down status ingest evaluate report bench all ab logs
help:
	@echo "Native stack targets (all no-Docker):"
	@echo "  setup     install local toolchains (node/prom/grafana/pushgw) + build AnythingLLM"
	@echo "  up        start all services as background processes + seed AnythingLLM"
	@echo "  down      stop all services"
	@echo "  status    show running state + health of each service"
	@echo "  ingest    ONE-TIME: download NQ + bulk-embed corpus into AnythingLLM's LanceDB"
	@echo "  bench     REPEATABLE: evaluate + report (run this again and again; no re-ingest)"
	@echo "  evaluate  run eval queries + LLM judge only"
	@echo "  report    write data/results/report.md only"
	@echo "  all       full first run = ingest + bench"
	@echo "  ab        ZenDNN A/B (baseline vs zendnn build) + report_ab"
	@echo "  logs      tail all service logs"

setup:    ; bash "$(HERE)setup.sh"
up:       ; bash "$(HERE)up.sh"
down:     ; bash "$(HERE)down.sh"
status:   ; bash "$(HERE)status.sh"
ingest:   ; bash "$(HERE)ingest.sh"
evaluate: ; bash "$(HERE)evaluate.sh"
report:   ; bash "$(HERE)report.sh"
# eval + report, always one after another — the repeatable measurement run.
bench: evaluate report
# full first-time run: ingest once, then bench.
all: ingest bench
ab:       ; bash "$(HERE)run_ab.sh"
logs:     ; tail -n +1 -F "$(HERE)logs/"*.log
