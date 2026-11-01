#!/usr/bin/env bash
#
# Offline compliance audit
# Validates the repository's Terraform, documentation, configuration, and secret
# hygiene without requiring cloud credentials. This is evidence of repository
# readiness, not an authorization decision.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/environments/production/southeast"

ENVIRONMENT="production"
OUTPUT_DIR="${REPO_ROOT}/compliance-reports"
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: run-compliance.sh [options]

Options:
  -e, --environment <env>    Environment label (development|staging|production)
  -o, --output <dir>         Output directory for the report
  -d, --dry-run              List checks without executing them
  -h, --help                 Display this help message

Checks are offline: Terraform formatting/validation, required authorization
artifacts, control-family mapping, JSON configuration, shell syntax, and
secret-pattern hygiene.
EOF
    exit 0
}

log() {
    local level=$1
    shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

die() {
    log "ERROR" "$*"
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -e|--environment) [ "$#" -ge 2 ] || die "Missing value for $1"; ENVIRONMENT="$2"; shift 2 ;;
        -o|--output)      [ "$#" -ge 2 ] || die "Missing value for $1"; OUTPUT_DIR="$2"; shift 2 ;;
        -d|--dry-run)     DRY_RUN=true; shift ;;
        -h|--help)        usage ;;
        *)                die "Unknown option: $1 (use --help)" ;;
    esac
done

case "$ENVIRONMENT" in
    development|staging|production) ;;
    *) die "Invalid environment: $ENVIRONMENT (expected development|staging|production)" ;;
esac

if [ "$DRY_RUN" = true ]; then
    log "INFO" "[DRY RUN] Would validate Terraform format/configuration, authorization artifacts,"
    log "INFO" "[DRY RUN] control families, JSON configuration, shell syntax, and secret hygiene."
    log "INFO" "[DRY RUN] Would write a Markdown report to ${OUTPUT_DIR#"$REPO_ROOT"/}."
    exit 0
fi

command -v terraform >/dev/null 2>&1 || die "Terraform is required but not installed."
command -v jq >/dev/null 2>&1 || die "jq is required but not installed."

mkdir -p "$OUTPUT_DIR"
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
REPORT="$OUTPUT_DIR/compliance-$ENVIRONMENT-$STAMP.md"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aegis-compliance.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

CHECKS=0
FAILURES=0
RESULTS=()

record() {
    local status=$1
    local label=$2
    local detail=${3:-}
    CHECKS=$((CHECKS + 1))
    RESULTS+=("$status|$label|$detail")
    if [ "$status" = "PASS" ]; then
        log "INFO" "PASS: $label"
    else
        FAILURES=$((FAILURES + 1))
        log "ERROR" "FAIL: $label${detail:+ — $detail}"
    fi
}

check_file() {
    local label=$1
    local path=$2
    if [ -s "$REPO_ROOT/$path" ]; then
        record PASS "$label" "$path"
    else
        record FAIL "$label" "missing or empty: $path"
    fi
}

check_command() {
    local label=$1
    shift
    local log_file="$WORK_DIR/check-$CHECKS.log"
    if "$@" > "$log_file" 2>&1; then
        record PASS "$label" ""
    else
        record FAIL "$label" "see command output in report"
        {
            printf '\n### Failed check: %s\n\n```text\n' "$label"
            sed -n '1,40p' "$log_file"
            printf '```\n'
        } >> "$WORK_DIR/failures.md"
    fi
}

# 1. Required authorization and operations artifacts
REQUIRED_ARTIFACTS=(
    "templates/SSP_TEMPLATE.md"
    "templates/POAM_TEMPLATE.md"
    "templates/SAR_TEMPLATE.md"
    "templates/RAR_TEMPLATE.md"
    "templates/AUTHORIZATION_PACKAGE.md"
    "templates/CCI_MAPPING.md"
    "docs/compliance/COMPLIANCE_MAPPING.md"
    "docs/compliance/fedramp/FEDRAMP_COMPLIANCE.md"
    "docs/compliance/fedramp/INHERITED_CONTROLS.md"
    "docs/security/policies/INCIDENT_RESPONSE_PLAN.md"
    "docs/security/policies/DR_BC_DETAILED_PLAN.md"
    "docs/security/implementation/SECURITY_METRICS.md"
    "docs/architecture/ZERO_TRUST_ARCHITECTURE.md"
    "docs/iam/IAM_GOVERNANCE.md"
    "monitoring/alerts/security/main.json"
    "monitoring/dashboards/infrastructure/main.json"
    "monitoring/logging/infrastructure/config.json"
)
for artifact in "${REQUIRED_ARTIFACTS[@]}"; do
    check_file "Required artifact: $artifact" "$artifact"
done

# 2. Terraform formatting and validation
check_command "Terraform formatting (recursive)" terraform fmt -check -recursive "$REPO_ROOT/terraform"
check_command "Terraform production root validation" bash -c \
    "cd '$TF_DIR' && terraform init -backend=false -input=false -compact-warnings >/dev/null && terraform validate -no-color"

# 3. Control-family coverage in the compliance mapping
check_command "NIST 800-53 control families mapped" bash -c \
    "for family in AC AU CM CP IA IR RA SC SI; do grep -q \"\$family-\" '$REPO_ROOT/docs/compliance/COMPLIANCE_MAPPING.md' || { echo \"missing family \$family\"; exit 1; }; done"

# 4. Framework coverage statements
check_command "FedRAMP High coverage documented" grep -q "FedRAMP High" \
    "$REPO_ROOT/docs/compliance/fedramp/FEDRAMP_COMPLIANCE.md"
check_command "NIST 800-207 coverage documented" grep -q "800-207" \
    "$REPO_ROOT/docs/architecture/ZERO_TRUST_ARCHITECTURE.md"

# 5. Machine-readable configuration
for json_file in \
    monitoring/alerts/security/main.json \
    monitoring/dashboards/infrastructure/main.json \
    monitoring/logging/infrastructure/config.json \
    itsm_templates/jira-import.json \
    itsm_templates/servicenow-import.json; do
    check_command "Valid JSON: $json_file" jq empty "$REPO_ROOT/$json_file"
done

# 6. Shell syntax
for script in \
    automation/deployment/infrastructure/deploy.sh \
    automation/security/scanning/run-scans.sh \
    automation/security/scanning/run-audit.sh \
    automation/compliance/audit/run-compliance.sh \
    docs/generate-docs.sh \
    tests/run-tests.sh; do
    if [ -f "$REPO_ROOT/$script" ]; then
        check_command "Shell syntax: $script" bash -n "$REPO_ROOT/$script"
    else
        record FAIL "Shell syntax: $script" "missing"
    fi
done

# 7. Secret-pattern hygiene (tokens that should never be committed)
AWS_KEY_PREFIX='AKIA'
ASIA_KEY_PREFIX='ASIA'
PLACEHOLDER_PREFIX='REPLACE_WITH_'
PLACEHOLDER_SUFFIX='SECURE_PASSWORD'
SECRET_PATTERN="${AWS_KEY_PREFIX}[0-9A-Z]{16}|${ASIA_KEY_PREFIX}[0-9A-Z]{16}|-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----|${PLACEHOLDER_PREFIX}${PLACEHOLDER_SUFFIX}|ghp_[A-Za-z0-9]{36}"
if grep -RInE --exclude-dir=.git --exclude-dir=.terraform --exclude-dir=security-reports \
    --exclude-dir=compliance-reports --exclude='*.png' "$SECRET_PATTERN" "$REPO_ROOT" > "$WORK_DIR/secrets.log" 2>&1; then
    record FAIL "No committed secret patterns" "matches: $(wc -l < "$WORK_DIR/secrets.log" | tr -d ' ')"
    {
        printf '\n### Committed secret-pattern matches\n\n```text\n'
        sed -n '1,40p' "$WORK_DIR/secrets.log"
        printf '```\n'
    } >> "$WORK_DIR/failures.md"
else
    record PASS "No committed secret patterns" ""
fi

# 8. No state or plan files in the repository tree
if find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o \
    \( -name '*.tfstate' -o -name '*.tfstate.backup' -o -name '*.tfplan' -o -name 'tfplan' \) \
    -print -quit | grep -q .; then
    record FAIL "No Terraform state/plan artifacts committed" "found state or plan file"
else
    record PASS "No Terraform state/plan artifacts committed" ""
fi

# Write the report
{
    cat << EOF
# AEGIS Offline Compliance Audit

- Environment: $ENVIRONMENT
- Generated (UTC): $STAMP
- Checks: $CHECKS
- Failures: $FAILURES
- Result: $([ "$FAILURES" -eq 0 ] && printf 'PASS' || printf 'FAIL')

## Check results

| Status | Check | Detail |
| --- | --- | --- |
EOF
    for result in "${RESULTS[@]}"; do
        IFS='|' read -r status label detail <<< "$result"
        printf '| %s | %s | %s |\n' "$status" "${label//|/\\|}" "${detail//|/\\|}"
    done
    printf '\n## Scope and limitations\n\n'
    printf 'This audit validates repository artifacts and Terraform syntax/configuration. '
    printf 'It does not apply infrastructure, inspect live cloud state, prove control effectiveness, '
    printf 'or replace a 3PAO assessment.\n'
    if [ -f "$WORK_DIR/failures.md" ]; then
        cat "$WORK_DIR/failures.md"
    fi
} > "$REPORT"

log "INFO" "Report written to ${REPORT#"$REPO_ROOT"/}"
if [ "$FAILURES" -gt 0 ]; then
    log "ERROR" "$FAILURES of $CHECKS checks failed"
    exit 1
fi

log "INFO" "All $CHECKS checks passed"
