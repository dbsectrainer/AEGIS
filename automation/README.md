# Automation Framework

The automation scripts provide safe local validation and credentialed cloud
operations. Every script supports `--help`; destructive or credentialed paths
fail fast when prerequisites are missing.

## Directory layout

```text
automation/
├── compliance/audit/run-compliance.sh
├── deployment/infrastructure/deploy.sh
├── maintenance/backup/backup.sh
├── maintenance/cleanup/cleanup.sh
└── security/scanning/
    ├── run-audit.sh
    └── run-scans.sh
```

## Commands

```bash
# Deployment: validate locally, then plan/apply with credentials
./automation/deployment/infrastructure/deploy.sh -e production -r southeast --dry-run
./automation/deployment/infrastructure/deploy.sh -e production -r southeast

# Security scans and read-only AWS posture audit
./automation/security/scanning/run-scans.sh -e production --dry-run
./automation/security/scanning/run-scans.sh -e production --fail-on-findings
./automation/security/scanning/run-audit.sh -e production
./automation/security/scanning/run-audit.sh -e production --dry-run

# Offline compliance evidence
./automation/compliance/audit/run-compliance.sh -e production

# Maintenance
./automation/maintenance/backup/backup.sh --dry-run
./automation/maintenance/cleanup/cleanup.sh            # dry run
./automation/maintenance/cleanup/cleanup.sh --yes      # delete generated files
```

## Behavior and safety

- **`deploy.sh`** resolves the environment directory, validates inputs, runs
  `terraform fmt -check`, and supports component targeting. A real apply requires
  cloud credentials, a provisioned backend, and either an interactive
  confirmation or `--auto-approve`. `--dry-run` never reads cloud state.
- **`run-scans.sh`** requires AWS credentials and Trivy for live scans. It scans
  Terraform, ECR repositories when present, AWS Config, S3 ACLs, security groups,
  and IAM password policy, then writes a consolidated report. Use
  `--fail-on-findings` to fail the command on HIGH/CRITICAL results.
- **`run-audit.sh`** performs read-only AWS posture checks and records JSON plus
  Markdown evidence. Collection failures are counted and never silently ignored.
- **`run-compliance.sh`** is fully offline. It validates Terraform, required
  authorization artifacts, control families, JSON, shell syntax, secret patterns,
  and state hygiene.
- **`backup.sh`** archives configuration and documentation, excludes secrets and
  state, verifies the archive, and writes a SHA-256 file.
- **`cleanup.sh`** is dry-run by default and preserves tracked sources and
  `docs/evidence`.

## Credentials

Never commit credentials. Use an AWS profile/SSO session, Azure service-principal
environment variables, and GCP application credentials. For Terraform secrets,
prefer `TF_VAR_*` environment variables or a secret manager over `terraform.tfvars`.

## Known gaps

- Application and monitoring deployment scripts do not exist because the
  repository has no application or monitoring backend deployment target. The
  monitoring scripts validate and package configuration only.
- Live scans and deployments were not executed during the audit; their dry-run
  paths were verified. See `docs/evidence/verification-report.md`.
