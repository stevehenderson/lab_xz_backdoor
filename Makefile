# XZ Backdoor Labs — top-level entrypoints.
# Real entrypoints live in lab1-inspect/ and lab2-detonate/; this just orchestrates.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- Config -----------------------------------------------------------------
# BACKEND: multipass | docker  (keep the value clean — Make keeps trailing
# spaces before an inline comment, which would corrupt the value)
BACKEND ?= multipass
VM_NAME ?= xz-lab

# --- Meta -------------------------------------------------------------------
.PHONY: help setup lab1 lab2 clean check-safety

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Vars: BACKEND=$(BACKEND) (multipass|docker), VM_NAME=$(VM_NAME)"

setup: ## Preflight: check deps and refuse unsafe state
	@bash common/preflight.sh

# --- Lab 1: static inspection ----------------------------------------------
lab1: setup ## Run the inspection lab (no payload execution)
	@echo ">> Lab 1: inspection sandbox (BACKEND=$(BACKEND))"
	@bash lab1-inspect/run.sh --backend "$(BACKEND)" --vm "$(VM_NAME)"

# --- Lab 2: controlled detonation (three-VM isolated network) ---------------
lab2: setup check-safety ## Set up the detonation lab (3 VMs, isolated net, your key)
	@echo ">> Lab 2: building the isolated three-VM network"
	@bash lab2-detonate/setup.sh
	@echo ">> Ready. Drive the demo from: multipass shell analyst  (see ~/demo/)"

check-safety: ## Interactive confirmation before running real malware
	@echo "!! Lab 2 backdoors a REAL sshd inside an isolated Multipass network."
	@echo "!! The compromised VM is taken offline and uses only your own key."
	@read -p "Type 'isolated' to confirm you want to proceed: " ans; \
		if [ "$$ans" != "isolated" ]; then echo "Aborting."; exit 1; fi

clean: ## Tear down the lab VMs, delete pcaps and generated keys
	@echo ">> Tearing down lab artifacts"
	@-bash lab2-detonate/teardown.sh 2>/dev/null || true
	@-multipass delete --purge "$(VM_NAME)" 2>/dev/null || true
	@-rm -f *.pcap **/*.pcap 2>/dev/null || true
	@echo ">> Done."
