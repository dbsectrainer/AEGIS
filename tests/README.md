# Testing Framework

This directory contains the offline and browser test suites for AEGIS. The
repository has no long-running application; the test layers are:

| Layer | Tool | What it verifies |
| --- | --- | --- |
| Repository contracts | Python `unittest` | Required files, Makefile/script contracts, JSON/CSV/XML, shell syntax, secret/state hygiene, provider configuration |
| Terraform | `terraform validate` + `terraform test` | Formatting, provider schema, full-stack mock plan, validation failures |
| Security | Trivy, tfsec, Checkov (advisory) | IaC misconfigurations and policy findings |
| Compliance | `automation/compliance/audit/run-compliance.sh` | 35 artifact, control, configuration, and hygiene checks |
| Documentation | `make docs` | 66-page static portal generation |
| Browser E2E | Playwright + Chromium | Navigation, search, links, mobile layout, console/network cleanliness, screenshots |

## Directory layout

```text
tests/
├── test_repository.py          # 21 offline repository tests
├── run-tests.sh                # full verification runner (evidence collection)
├── write_verification.py       # machine-readable verification snapshot
└── e2e/
    └── test_docs_portal.py     # Playwright E2E + screenshots
```

## Prerequisites

```bash
python3 -m pip install -r docs/requirements.txt
python3 -m pip install playwright
python3 -m playwright install chromium
```

Also required for the full runner: Terraform 1.12+, `jq`, `shellcheck`, `trivy`,
and `markdownlint-cli`. `tfsec` and `checkov` are optional/advisory.

## Commands

```bash
# Fast repository contract tests
make test-repository

# Terraform format, offline validate, and mock-provider tests
make test-terraform

# Trivy HIGH/CRITICAL IaC scan
make test-security

# Documentation portal + Playwright E2E + screenshots
make test-e2e

# Full evidence-collection suite
make verify
```

`make test` runs the repository, Terraform, and Trivy gates. `make verify` also
runs ShellCheck, Markdown lint, compliance, monitoring validation, deployment
dry runs, documentation E2E, and writes `docs/evidence/verification.json`.

## Evidence outputs

- `docs/evidence/test-results/`: one log per check plus `status.tsv`
- `docs/evidence/build-results/`: Terraform, docs, Trivy, and Checkov build logs
- `docs/evidence/screenshots/`: browser screenshots
- `docs/evidence/verification.json`: status, counts, artifact paths
- `docs/evidence/verification-report.md`: human-readable audit report

## Scope limitations

- Tests run offline. They do not prove live cloud behavior, IAM permissions, or
  control effectiveness.
- Terraform tests use mock providers; they validate wiring and schema, not
  provider API responses.
- Checkov is advisory and may report findings or false positives; inspect the
  log rather than treating the label as a pass/fail security certification.
- Browser E2E covers the documentation portal, which is the only rendered UI in
  this repository.
