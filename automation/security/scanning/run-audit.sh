#!/usr/bin/env bash
#
# AWS Security Audit Script
# Collects read-only AWS posture evidence for a GovCloud account.
# All calls are read-only. Live execution requires AWS credentials; --dry-run
# demonstrates the command path without contacting AWS.

set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

ENVIRONMENT="production"
AWS_REGION="${AWS_REGION:-us-gov-east-1}"
OUTPUT_DIR="${REPO_ROOT}/security-reports/audit"
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: run-audit.sh [options]

Read-only AWS posture checks: identity, root account, IAM password policy,
CloudTrail, GuardDuty, Security Hub, AWS Config, and S3 account public access.

Options:
  -e, --environment <env>    Environment label (development|staging|production)
  -r, --region <region>      AWS region (default: us-gov-east-1)
  -o, --output <dir>         Output directory
  -d, --dry-run              Print planned checks without AWS calls
  -h, --help                 Display this help message
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
        -r|--region)      [ "$#" -ge 2 ] || die "Missing value for $1"; AWS_REGION="$2"; shift 2 ;;
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
    log "INFO" "[DRY RUN] Environment: $ENVIRONMENT; region: $AWS_REGION"
    log "INFO" "[DRY RUN] Would collect: sts identity, IAM summary/password policy, CloudTrail, GuardDuty, Security Hub, AWS Config, S3 public access block"
    log "INFO" "[DRY RUN] Would write JSON and a Markdown report to ${OUTPUT_DIR#"$REPO_ROOT"/}"
    log "INFO" "[DRY RUN] No AWS calls were made."
    exit 0
fi

command -v aws >/dev/null 2>&1 || die "AWS CLI is required but not installed."
command -v jq >/dev/null 2>&1 || die "jq is required but not installed."
aws sts get-caller-identity >/dev/null 2>&1 || die "No usable AWS credentials. Configure a profile/SSO session or use --dry-run."

mkdir -p "$OUTPUT_DIR"
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
REPORT="$OUTPUT_DIR/aws-security-audit-$ENVIRONMENT-$STAMP.md"
ERRORS=0

collect() {
    local name=$1
    shift
    if "$@" > "$OUTPUT_DIR/$name.json" 2> "$OUTPUT_DIR/$name.err"; then
        rm -f "$OUTPUT_DIR/$name.err"
        log "INFO" "Collected $name"
    else
        ERRORS=$((ERRORS + 1))
        printf '{"error":"collection failed","check":"%s"}\n' "$name" > "$OUTPUT_DIR/$name.json"
        log "WARN" "Could not collect $name (see ${OUTPUT_DIR#"$REPO_ROOT"/}/$name.err)"
    fi
}

collect identity aws sts get-caller-identity
collect account-summary aws iam get-account-summary
collect password-policy aws iam get-account-password-policy
collect cloudtrail aws cloudtrail describe-trails
collect guardduty aws guardduty list-detectors --region "$AWS_REGION"
collect securityhub aws securityhub describe-hub --region "$AWS_REGION"
collect config-recorders aws configservice describe-configuration-recorders --region "$AWS_REGION"
collect s3-public-access aws s3api get-public-access-block

# CloudTrail status for the first trail, when one exists.
TRAIL_NAME=$(jq -r '.trailList[0].Name // empty' "$OUTPUT_DIR/cloudtrail.json" 2>/dev/null || true)
if [ -n "$TRAIL_NAME" ]; then
    collect cloudtrail-status aws cloudtrail get-trail-status --name "$TRAIL_NAME"
else
    log "WARN" "No CloudTrail trail found"
fi

# Derived summary values
ACCOUNT=$(jq -r '.Account // "unknown"' "$OUTPUT_DIR/identity.json" 2>/dev/null || printf 'unknown')
ROOT_MFA=$(jq -r '.SummaryMap.AccountMFAEnabled // 0' "$OUTPUT_DIR/account-summary.json" 2>/dev/null || printf '0')
PASSWORD_MIN=$(jq -r '.PasswordPolicy.MinimumPasswordLength // "not-set"' "$OUTPUT_DIR/password-policy.json" 2>/dev/null || printf 'not-set')
TRAIL_COUNT=$(jq -r '.trailList | length' "$OUTPUT_DIR/cloudtrail.json" 2>/dev/null || printf '0')
MULTI_REGION_TRAIL=$(jq -r '[.trailList[]? | select(.IsMultiRegionTrail == true)] | length' "$OUTPUT_DIR/cloudtrail.json" 2>/dev/null || printf '0')
GUARDDUTY_COUNT=$(jq -r '.DetectorIds | length' "$OUTPUT_DIR/guardduty.json" 2>/dev/null || printf '0')
SECURITYHUB=$(jq -r 'if .HubArn then "enabled" else "disabled" end' "$OUTPUT_DIR/securityhub.json" 2>/dev/null || printf 'unknown')
CONFIG_RECORDERS=$(jq -r '.ConfigurationRecorders | length' "$OUTPUT_DIR/config-recorders.json" 2>/dev/null || printf '0')

cat > "$REPORT" << EOF
# AWS Security Audit

- Environment: $ENVIRONMENT
- AWS region: $AWS_REGION
- AWS account: $ACCOUNT
- Collected (UTC): $STAMP
- Collection errors: $ERRORS

## Posture summary

| Check | Observed value | Interpretation |
| --- | --- | --- |
| Root account MFA | $ROOT_MFA | 1 is enabled; 0 requires action |
| IAM minimum password length | $PASSWORD_MIN | Compare with policy (14+ recommended) |
| CloudTrail trails | $TRAIL_COUNT | At least one multi-region trail is expected |
| Multi-region trails | $MULTI_REGION_TRAIL | 0 requires action |
| GuardDuty detectors | $GUARDDUTY_COUNT | 0 means GuardDuty is not enabled |
| Security Hub | $SECURITYHUB | disabled requires action |
| AWS Config recorders | $CONFIG_RECORDERS | 0 means no recorder is configured |

## Evidence files

EOF

for f in "$OUTPUT_DIR"/*.json; do
    printf -- '- %s\n' "\`${f#"$REPO_ROOT"/}\`" >> "$REPORT"
done

cat >> "$REPORT" << 'EOF'

## Scope and limitations

This audit only reports the API responses observed at collection time. It does not
prove that controls remain effective, and it does not inspect workload or data-plane
configuration. Collection failures are recorded in the JSON artifacts and counted
above; they are not silently ignored.
EOF

log "INFO" "Audit report written to ${REPORT#"$REPO_ROOT"/}"
if [ "$ERRORS" -gt 0 ]; then
    log "WARN" "Completed with $ERRORS collection error(s)"
fi
