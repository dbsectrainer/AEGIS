# Cloud Infrastructure Makefile

.PHONY: init plan apply test security docs clean

# Variables
ENV ?= development
REGION ?= northeast
TF_DIR = terraform/environments/$(ENV)/$(REGION)

# Infrastructure Commands
init:
	@echo "Initializing Terraform for $(ENV) environment in $(REGION) region..."
	cd $(TF_DIR) && terraform init

plan:
	@echo "Planning Terraform changes for $(ENV) environment in $(REGION) region..."
	cd $(TF_DIR) && terraform plan -out=tfplan

apply:
	@echo "Applying Terraform changes for $(ENV) environment in $(REGION) region..."
	cd $(TF_DIR) && terraform apply tfplan

# Testing Commands
test: test-terraform test-security test-performance

test-terraform:
	@echo "Running Terraform format check and validation..."
	terraform fmt -recursive -check terraform
	cd terraform/environments/production/southeast && terraform init -backend=false -input=false && terraform validate
	@if [ -d tests/terraform ]; then cd tests/terraform && go test -v ./...; fi

test-security:
	@echo "Running security tests..."
	@if [ -d tests/security ]; then cd tests/security && go test -v ./...; else echo "No tests/security suite present; skipping"; fi

test-performance:
	@echo "Running performance tests..."
	@if [ -d tests/performance ]; then cd tests/performance && go test -v ./...; else echo "No tests/performance suite present; skipping"; fi

# Security Commands
security: security-scan security-audit security-compliance

security-scan:
	@echo "Running security scans..."
	./automation/security/scanning/run-scans.sh -e $(ENV)

security-audit:
	@echo "Running security audit..."
	./automation/security/scanning/run-audit.sh -e $(ENV)

security-compliance:
	@echo "Running compliance checks..."
	./automation/compliance/audit/run-compliance.sh -e $(ENV)

# Documentation Commands
docs:
	@echo "Generating documentation..."
	cd docs && ./generate-docs.sh

docs-lint:
	@echo "Linting documentation..."
	markdownlint '**/*.md' --ignore node_modules

# Monitoring Commands
monitoring-init:
	@echo "Initializing monitoring stack..."
	cd monitoring && ./init-monitoring.sh -e $(ENV)

monitoring-update:
	@echo "Updating monitoring configurations..."
	cd monitoring && ./update-monitoring.sh -e $(ENV)

# Deployment Commands
deploy: deploy-infra deploy-apps deploy-monitoring

deploy-infra:
	@echo "Deploying infrastructure..."
	./automation/deployment/infrastructure/deploy.sh -e $(ENV) -r $(REGION)

deploy-apps:
	@echo "Deploying applications..."
	./automation/deployment/applications/deploy.sh -e $(ENV) -r $(REGION)

deploy-monitoring:
	@echo "Deploying monitoring stack..."
	./automation/deployment/monitoring/deploy.sh -e $(ENV) -r $(REGION)

# Maintenance Commands
maintenance: cleanup backup optimize

cleanup:
	@echo "Running cleanup tasks..."
	./automation/maintenance/cleanup/cleanup.sh -e $(ENV)

backup:
	@echo "Running backup tasks..."
	./automation/maintenance/backup/backup.sh -e $(ENV)

optimize:
	@echo "Running optimization tasks..."
	./automation/maintenance/optimization/optimize.sh -e $(ENV)

# Clean Commands
clean:
	@echo "Cleaning temporary files..."
	find . -name "*.tfplan" -type f -delete
	find . -name "*.tfstate.backup" -type f -delete
	find . -name ".terraform" -type d -exec rm -rf {} +

# Help Command
help:
	@echo "Cloud Infrastructure Makefile Commands:"
	@echo ""
	@echo "Infrastructure Commands:"
	@echo "  make init ENV=<env> REGION=<region>    - Initialize Terraform"
	@echo "  make plan ENV=<env> REGION=<region>    - Plan Terraform changes"
	@echo "  make apply ENV=<env> REGION=<region>   - Apply Terraform changes"
	@echo ""
	@echo "Testing Commands:"
	@echo "  make test                              - Run all tests"
	@echo "  make test-terraform                    - Run Terraform tests"
	@echo "  make test-security                     - Run security tests"
	@echo "  make test-performance                  - Run performance tests"
	@echo ""
	@echo "Security Commands:"
	@echo "  make security                          - Run all security checks"
	@echo "  make security-scan                     - Run security scans"
	@echo "  make security-audit                    - Run security audit"
	@echo "  make security-compliance               - Run compliance checks"
	@echo ""
	@echo "Documentation Commands:"
	@echo "  make docs                              - Generate documentation"
	@echo "  make docs-lint                         - Lint documentation"
	@echo ""
	@echo "Monitoring Commands:"
	@echo "  make monitoring-init                   - Initialize monitoring"
	@echo "  make monitoring-update                 - Update monitoring"
	@echo ""
	@echo "Deployment Commands:"
	@echo "  make deploy                            - Deploy all components"
	@echo "  make deploy-infra                      - Deploy infrastructure"
	@echo "  make deploy-apps                       - Deploy applications"
	@echo "  make deploy-monitoring                 - Deploy monitoring"
	@echo ""
	@echo "Maintenance Commands:"
	@echo "  make maintenance                       - Run all maintenance tasks"
	@echo "  make cleanup                           - Run cleanup tasks"
	@echo "  make backup                            - Run backup tasks"
	@echo "  make optimize                          - Run optimization tasks"
	@echo ""
	@echo "Clean Commands:"
	@echo "  make clean                             - Clean temporary files"
