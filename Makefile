# AEGIS Makefile
# Infrastructure, validation, documentation, and evidence targets.
#
# Safe local defaults:
#   make validate / make test / make docs / make security   do not change cloud state.
#   make plan / make apply / make deploy                   require cloud credentials.

SHELL := /bin/bash
.DEFAULT_GOAL := help

ENV ?= production
REGION ?= southeast
TF_DIR := terraform/environments/$(ENV)/$(REGION)
TF_BIN := terraform

.PHONY: help fmt validate init plan apply deploy deploy-dry-run \
        test test-repository test-terraform test-security test-e2e test-localstack \
        security security-scan-offline security-compliance security-live security-dry-run \
        docs docs-lint monitoring-init monitoring-update backup cleanup clean verify

help:
	@echo "AEGIS repository commands"
	@echo ""
	@echo "Validation and tests (no cloud credentials required):"
	@echo "  make fmt                               Format Terraform recursively"
	@echo "  make validate                          Format check + init -backend=false + validate + tests"
	@echo "  make test                              Repository tests, Terraform tests, offline security scan"
	@echo "  make test-repository                   Python repository/contract tests"
	@echo "  make test-terraform                    Terraform format, validate, and native tests"
	@echo "  make test-security                     Trivy HIGH/CRITICAL IaC scan (fails on findings)"
	@echo "  make test-e2e                          Build the docs portal and run Playwright E2E checks"
	@echo "  make test-localstack                   LocalStack AWS provider/integration test (Docker)"
	@echo "  make verify                            Run the full evidence-collection suite"
	@echo ""
	@echo "Infrastructure (requires credentials and remote state):"
	@echo "  make init ENV=production REGION=southeast       Initialize Terraform"
	@echo "  make plan ENV=production REGION=southeast       Create a saved plan"
	@echo "  make apply ENV=production REGION=southeast      Apply the saved plan"
	@echo "  make deploy ENV=production REGION=southeast     Deploy infrastructure"
	@echo "  make deploy-dry-run ...                        Validate deployment inputs offline"
	@echo ""
	@echo "Security and compliance:"
	@echo "  make security                          Offline Trivy scan + compliance audit"
	@echo "  make security-scan-offline             Trivy Terraform config scan"
	@echo "  make security-compliance               Offline compliance evidence report"
	@echo "  make security-live                     Trivy/tfsec/AWS scans and audit (credentials required)"
	@echo "  make security-dry-run                  Print live scan/audit command paths"
	@echo ""
	@echo "Documentation and monitoring:"
	@echo "  make docs                              Build the static documentation portal"
	@echo "  make docs-lint                         Lint Markdown"
	@echo "  make monitoring-init                   Validate monitoring JSON and build a manifest"
	@echo "  make monitoring-update                 Rebuild the manifest and show changes"
	@echo ""
	@echo "Maintenance:"
	@echo "  make backup                            Create a verified configuration archive"
	@echo "  make cleanup                           Dry-run generated-artifact cleanup"
	@echo "  make clean                             Remove Terraform caches and generated site"

guard-env:
	@if [ ! -d "$(TF_DIR)" ]; then \
		echo "ERROR: $(TF_DIR) does not exist. Available:"; \
		find terraform/environments -mindepth 2 -maxdepth 2 -type d | sort; \
		exit 1; \
	fi

fmt:
	$(TF_BIN) fmt -recursive terraform tests/localstack/terraform

validate: test-terraform

test: test-repository test-terraform test-security

test-repository:
	@echo "== Repository contract tests =="
	python3 -m unittest discover -s tests -p 'test_*.py' -v

test-terraform: guard-env
	@echo "== Terraform format check =="
	$(TF_BIN) fmt -recursive -check terraform
	@echo "== Terraform offline init and validate ($(ENV)/$(REGION)) =="
	cd $(TF_DIR) && $(TF_BIN) init -backend=false -input=false -compact-warnings
	cd $(TF_DIR) && $(TF_BIN) validate -no-color
	@echo "== Terraform native mock-provider tests =="
	cd $(TF_DIR) && $(TF_BIN) test -verbose

test-security:
	@echo "== Offline Trivy HIGH/CRITICAL scan =="
	@command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy is required for test-security"; exit 1; }
	trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL terraform

test-e2e: docs
	@echo "== Playwright documentation portal E2E =="
	python3 tests/e2e/test_docs_portal.py

test-localstack:
	@echo "== LocalStack AWS emulation tests =="
	./tests/localstack/run-localstack-tests.sh

security: security-scan-offline security-compliance

security-scan-offline:
	@command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy is required"; exit 1; }
	trivy config --exit-code 1 --severity HIGH,CRITICAL terraform

security-compliance:
	./automation/compliance/audit/run-compliance.sh -e $(ENV)

security-live:
	./automation/security/scanning/run-scans.sh -e $(ENV) --fail-on-findings
	./automation/security/scanning/run-audit.sh -e $(ENV)

security-dry-run:
	./automation/security/scanning/run-scans.sh -e $(ENV) --dry-run
	./automation/security/scanning/run-audit.sh -e $(ENV) --dry-run

init: guard-env
	@echo "Initializing Terraform for $(ENV)/$(REGION)"
	cd $(TF_DIR) && $(TF_BIN) init -input=false

plan: guard-env
	@echo "Planning Terraform changes for $(ENV)/$(REGION)"
	cd $(TF_DIR) && $(TF_BIN) plan -input=false -out=tfplan

apply: guard-env
	@if [ ! -f "$(TF_DIR)/tfplan" ]; then echo "ERROR: no saved plan. Run 'make plan ENV=$(ENV) REGION=$(REGION)' first."; exit 1; fi
	cd $(TF_DIR) && $(TF_BIN) apply -input=false tfplan

deploy: deploy-dry-run
	./automation/deployment/infrastructure/deploy.sh -e $(ENV) -r $(REGION)

deploy-dry-run:
	./automation/deployment/infrastructure/deploy.sh -e $(ENV) -r $(REGION) --dry-run

docs:
	@echo "Building documentation portal..."
	cd docs && ./generate-docs.sh

docs-lint:
	@echo "Linting documentation..."
	markdownlint '**/*.md' --ignore node_modules --ignore docs/site --config .markdownlint.json

monitoring-init:
	./monitoring/init-monitoring.sh -e $(ENV)

monitoring-update:
	./monitoring/update-monitoring.sh -e $(ENV)

backup:
	./automation/maintenance/backup/backup.sh

cleanup:
	./automation/maintenance/cleanup/cleanup.sh

clean:
	@echo "Cleaning generated local artifacts..."
	rm -rf docs/site security-reports compliance-reports monitoring/generated
	find terraform -name "*.tfplan" -type f -delete
	find terraform -name "tfplan" -type f -delete
	find terraform -name ".terraform" -type d -prune -exec rm -rf {} +

verify:
	./tests/run-tests.sh
