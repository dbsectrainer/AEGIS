#!/usr/bin/env bash
#
# Security Scanning Script
# Orchestrates infrastructure, image, compliance, and configuration scans.
#
# The script requires cloud credentials for live scans. Use --dry-run to verify
# the command path and output directory without credentials or external calls.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

# Defaults
ENVIRONMENT="development"
SCAN_TYPE="all"
SEVERITY="high"
VERBOSE=false
DRY_RUN=false
FAIL_ON_FINDINGS=false
OUTPUT_DIR="${REPO_ROOT}/security-reports"
AWS_REGION="${AWS_REGION:-us-gov-east-1}"

HIGH_FINDINGS=0

usage() {
    cat <<'EOF'
Usage: run-scans.sh [options]

Options:
  -e, --environment <env>    Environment to scan (development|staging|production)
  -t, --type <type>          Scan type (all|vulnerability|compliance|configuration)
  -s, --severity <level>     Minimum severity (low|medium|high|critical)
  -o, --output <dir>         Output directory for reports
  -v, --verbose              Echo commands and enable shell tracing
  -d, --dry-run              Validate inputs without credentials or external calls
  -f, --fail-on-findings     Exit non-zero when HIGH or CRITICAL findings exist
  -h, --help                 Display this help message

Environment:
  AWS_REGION                 AWS region for ECR/Config/AWS CLI (default: us-gov-east-1)
  SLACK_WEBHOOK_URL          Optional Slack incoming webhook for high findings
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

run() {
    if [ "$VERBOSE" = true ]; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
    fi
    "$@"
}

validate_environment() {
    case "$ENVIRONMENT" in
        development|staging|production) ;;
        *) die "Invalid environment: $ENVIRONMENT (expected development|staging|production)" ;;
    esac
}

validate_scan_type() {
    case "$SCAN_TYPE" in
        all|vulnerability|compliance|configuration) ;;
        *) die "Invalid scan type: $SCAN_TYPE (expected all|vulnerability|compliance|configuration)" ;;
    esac
}

validate_severity() {
    case "$SEVERITY" in
        low|medium|high|critical) ;;
        *) die "Invalid severity: $SEVERITY (expected low|medium|high|critical)" ;;
    esac
}

check_prerequisites() {
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "Dry run selected; external tools and AWS credentials are not required."
        return 0
    fi

    command -v jq >/dev/null 2>&1 || die "jq is required but not installed."
    command -v trivy >/dev/null 2>&1 || die "Trivy is required but not installed."
    command -v aws >/dev/null 2>&1 || die "AWS CLI is required but not installed."

    if [ "$SCAN_TYPE" = "all" ] || [ "$SCAN_TYPE" = "compliance" ]; then
        command -v tfsec >/dev/null 2>&1 || die "tfsec is required for compliance scans but not installed."
    fi

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        die "No usable AWS credentials. Configure a profile/SSO session or use --dry-run."
    fi

    mkdir -p "$OUTPUT_DIR"
    log "INFO" "Prerequisites check passed"
}

notify_slack() {
    local message=$1
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        local payload
        payload=$(jq -n --arg text "$message" '{text: $text}')
        if ! curl -fsS -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null; then
            log "WARN" "Slack notification failed; continuing."
        fi
    else
        log "WARN" "SLACK_WEBHOOK_URL not set; skipping Slack notification."
    fi
}

run_vulnerability_scan() {
    log "INFO" "Running vulnerability scan..."

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would scan ./terraform and ECR repositories in $AWS_REGION with Trivy"
        return 0
    fi

    run trivy config --severity "$SEVERITY" \
        --format json \
        --output "$OUTPUT_DIR/vulnerability-terraform-$ENVIRONMENT.json" \
        "${REPO_ROOT}/terraform"
    run trivy config --severity "$SEVERITY" \
        --format sarif \
        --output "$OUTPUT_DIR/trivy-terraform-$ENVIRONMENT.sarif" \
        "${REPO_ROOT}/terraform"

    local repositories
    repositories=$(aws ecr describe-repositories \
        --region "$AWS_REGION" \
        --query 'repositories[*].repositoryUri' \
        --output text 2>/dev/null || true)

    if [ -z "$repositories" ] || [ "$repositories" = "None" ]; then
        log "WARN" "No ECR repositories found in $AWS_REGION; skipping container image scan."
    else
        local repository
        while IFS= read -r repository; do
            [ -n "$repository" ] || continue
            log "INFO" "Scanning image repository: $repository"
            local slug
            slug=$(printf '%s' "$repository" | tr '/:@' '___')
            run trivy image --severity "$SEVERITY" \
                --format json \
                --output "$OUTPUT_DIR/vulnerability-image-${slug}-$ENVIRONMENT.json" \
                "$repository"
        done <<< "$repositories"
    fi

    log "INFO" "Vulnerability scan completed"
}

run_compliance_scan() {
    log "INFO" "Running compliance scan..."

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would run tfsec and aws configservice describe-compliance-by-config-rule"
        return 0
    fi

    run tfsec "${REPO_ROOT}/terraform" \
        --force-all-dirs \
        --soft-fail \
        --format json \
        --out "$OUTPUT_DIR/compliance-terraform-$ENVIRONMENT.json" \
        --minimum-severity "$SEVERITY"
    run tfsec "${REPO_ROOT}/terraform" \
        --force-all-dirs \
        --soft-fail \
        --format sarif \
        --out "$OUTPUT_DIR/tfsec-$ENVIRONMENT.sarif" \
        --minimum-severity "$SEVERITY"

    log "INFO" "Checking AWS Config rules..."
    if aws configservice describe-compliance-by-config-rule \
        --region "$AWS_REGION" \
        --output json > "$OUTPUT_DIR/compliance-aws-config-$ENVIRONMENT.json"; then
        log "INFO" "AWS Config results collected"
    else
        log "WARN" "AWS Config is unavailable or not authorized; continuing with IaC results only."
    fi

    log "INFO" "Compliance scan completed"
}

run_configuration_scan() {
    log "INFO" "Running configuration scan..."

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would collect S3 ACLs, security groups, and IAM password policy from $AWS_REGION"
        return 0
    fi

    log "INFO" "Checking S3 bucket configurations..."
    local buckets
    if buckets=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text 2>/dev/null); then
        local bucket
        while IFS= read -r bucket; do
            [ -n "$bucket" ] || continue
            if ! aws s3api get-bucket-acl --bucket "$bucket" \
                > "$OUTPUT_DIR/config-s3-$bucket-$ENVIRONMENT.json" 2>/dev/null; then
                log "WARN" "Could not read ACL for bucket: $bucket"
            fi
        done <<< "$buckets"
    else
        log "WARN" "Could not list S3 buckets; skipping bucket ACL collection."
    fi

    log "INFO" "Checking security group configurations..."
    if ! aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --output json > "$OUTPUT_DIR/config-security-groups-$ENVIRONMENT.json"; then
        log "WARN" "Could not collect security groups."
    fi

    log "INFO" "Checking IAM configurations..."
    if ! aws iam get-account-password-policy \
        --output json > "$OUTPUT_DIR/config-iam-password-policy-$ENVIRONMENT.json"; then
        log "WARN" "Could not collect the IAM account password policy."
    fi

    log "INFO" "Configuration scan completed"
}

count_json_list() {
    local file=$1
    local jq_expression=$2
    if [ -f "$file" ]; then
        jq -r "$jq_expression" "$file" 2>/dev/null || printf '0'
    else
        printf '0'
    fi
}

generate_report() {
    log "INFO" "Generating consolidated report..."

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would write $OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"
        return 0
    fi

    local trivy_findings=0
    local tfsec_findings=0
    local report="$OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"

    trivy_findings=$(count_json_list \
        "$OUTPUT_DIR/vulnerability-terraform-$ENVIRONMENT.json" \
        '[.Results[]?.Misconfigurations[]? | select((.Severity|ascii_upcase) == "HIGH" or (.Severity|ascii_upcase) == "CRITICAL")] | length')
    tfsec_findings=$(count_json_list \
        "$OUTPUT_DIR/compliance-terraform-$ENVIRONMENT.json" \
        '[.results[]? | select((.severity|ascii_upcase) == "HIGH" or (.severity|ascii_upcase) == "CRITICAL")] | length')

    HIGH_FINDINGS=$((trivy_findings + tfsec_findings))

    cat > "$report" << EOF
# Security Scan Report

- Environment: $ENVIRONMENT
- Date: $(date '+%Y-%m-%d %H:%M:%S')
- Scan type: $SCAN_TYPE
- Minimum severity: $SEVERITY
- AWS region: $AWS_REGION

## Summary

| Source | HIGH/CRITICAL findings |
| --- | ---: |
| Trivy Terraform config | $trivy_findings |
| tfsec Terraform config | $tfsec_findings |
| **Total** | **$HIGH_FINDINGS** |

## Artifacts

EOF

    local artifact
    for artifact in "$OUTPUT_DIR"/*"$ENVIRONMENT"*; do
        [ -f "$artifact" ] || continue
        printf -- '- %s\n' "${artifact#"$REPO_ROOT"/}" >> "$report"
    done

    printf '\nScan type: %s. Results are limited to the tools and credentials available at execution time.\n' \
        "$SCAN_TYPE" >> "$report"

    if [ "$HIGH_FINDINGS" -gt 0 ]; then
        notify_slack "[$ENVIRONMENT] High or critical findings: $HIGH_FINDINGS. See ${report#"$REPO_ROOT"/}"
    fi

    log "INFO" "Report written to ${report#"$REPO_ROOT"/}"
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -e|--environment)
                [ "$#" -ge 2 ] || die "Missing value for $1"
                ENVIRONMENT="$2"
                shift 2
                ;;
            -t|--type)
                [ "$#" -ge 2 ] || die "Missing value for $1"
                SCAN_TYPE="$2"
                shift 2
                ;;
            -s|--severity)
                [ "$#" -ge 2 ] || die "Missing value for $1"
                SEVERITY="$2"
                shift 2
                ;;
            -o|--output)
                [ "$#" -ge 2 ] || die "Missing value for $1"
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--fail-on-findings)
                FAIL_ON_FINDINGS=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                die "Unknown option: $1 (use --help)"
                ;;
        esac
    done

    if [ "$VERBOSE" = true ]; then
        set -x
    fi

    log "INFO" "Starting security scan"
    log "INFO" "Environment: $ENVIRONMENT"
    log "INFO" "Scan type: $SCAN_TYPE"
    log "INFO" "Severity level: $SEVERITY"

    validate_environment
    validate_scan_type
    validate_severity
    check_prerequisites

    case "$SCAN_TYPE" in
        all)
            run_vulnerability_scan
            run_compliance_scan
            run_configuration_scan
            ;;
        vulnerability) run_vulnerability_scan ;;
        compliance) run_compliance_scan ;;
        configuration) run_configuration_scan ;;
    esac

    generate_report

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "Dry run completed successfully; no scans were executed."
        return 0
    fi

    if [ "$FAIL_ON_FINDINGS" = true ] && [ "$HIGH_FINDINGS" -gt 0 ]; then
        log "ERROR" "$HIGH_FINDINGS HIGH/CRITICAL finding(s) detected"
        exit 1
    fi

    log "INFO" "Security scan completed successfully"
}

main "$@"
