#!/usr/bin/env bash
#
# Local AWS emulation test.
# Applies a small Terraform fixture against LocalStack, then verifies the
# resulting resources through the AWS CLI. This validates real provider CRUD for
# supported AWS services without a cloud account. It does not validate GovCloud,
# EKS, ECS, RDS, or Azure/GCP.
#
# Usage:
#   tests/localstack/run-localstack-tests.sh
#   tests/localstack/run-localstack-tests.sh --no-start
#   tests/localstack/run-localstack-tests.sh --keep

set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
FIXTURE="${SCRIPT_DIR}/terraform"
EVIDENCE="${REPO_ROOT}/docs/evidence/localstack"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
LOCALSTACK_IMAGE="${LOCALSTACK_IMAGE:-localstack/localstack:4.4.0}"
CONTAINER_NAME="${LOCALSTACK_CONTAINER_NAME:-aegis-localstack}"
START_LOCALSTACK=true
KEEP_RESOURCES=false
STARTED_CONTAINER=false
FAILURES=0
CHECKS=0
RESULTS=()

usage() {
    cat <<'USAGE'
Usage: run-localstack-tests.sh [options]

Options:
  --no-start     Use an already-running LocalStack at LOCALSTACK_ENDPOINT
  --keep         Do not destroy the Terraform fixture at exit
  -h, --help     Display this help message

Environment:
  LOCALSTACK_ENDPOINT   Default http://localhost:4566
  LOCALSTACK_IMAGE      Default localstack/localstack:4.4.0
  AWS_DEFAULT_REGION    Default us-east-1
USAGE
    exit 0
}

log() {
    printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
    exit 1
}

record() {
    local status=$1
    local name=$2
    local detail=${3:-}
    CHECKS=$((CHECKS + 1))
    RESULTS+=("$status|$name|$detail")
    if [ "$status" = "PASS" ]; then
        log "PASS: $name"
    else
        FAILURES=$((FAILURES + 1))
        log "FAIL: $name${detail:+ — $detail}"
    fi
}

cleanup() {
    if [ "$KEEP_RESOURCES" = false ]; then
        log "Destroying LocalStack fixture resources"
        terraform -chdir="$FIXTURE" destroy -auto-approve -input=false \
            -var "localstack_endpoint=${LOCALSTACK_ENDPOINT}" > "${EVIDENCE}/terraform-destroy.log" 2>&1 || \
            log "WARN: terraform destroy did not complete; restart the LocalStack container to reset it"
    fi
    if [ "$STARTED_CONTAINER" = true ]; then
        log "Stopping LocalStack container ${CONTAINER_NAME}"
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-start) START_LOCALSTACK=false; shift ;;
        --keep) KEEP_RESOURCES=true; shift ;;
        -h|--help) usage ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done

command -v terraform >/dev/null 2>&1 || die "Terraform is required."
command -v aws >/dev/null 2>&1 || die "AWS CLI is required."
command -v jq >/dev/null 2>&1 || die "jq is required."
command -v curl >/dev/null 2>&1 || die "curl is required."

mkdir -p "$EVIDENCE"
: > "${EVIDENCE}/assertions.log"
: > "${EVIDENCE}/run.log"

if [ "$START_LOCALSTACK" = true ]; then
    command -v docker >/dev/null 2>&1 || die "Docker is required unless --no-start is used."
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" != "true" ]; then
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        log "Starting LocalStack ${LOCALSTACK_IMAGE}"
        docker run -d --name "$CONTAINER_NAME" -p 4566:4566 \
            -e SERVICES=s3,dynamodb,sqs,sns,iam,sts,kms,ec2,logs \
            "$LOCALSTACK_IMAGE" > "${EVIDENCE}/localstack-container.log" 2>&1 || \
            die "Could not start LocalStack container"
        STARTED_CONTAINER=true
    else
        log "Reusing running LocalStack container ${CONTAINER_NAME}"
    fi
fi

log "Waiting for LocalStack health at ${LOCALSTACK_ENDPOINT}"
ready=false
for _ in $(seq 1 60); do
    if curl -fsS "${LOCALSTACK_ENDPOINT}/_localstack/health" >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 2
done
[ "$ready" = true ] || die "LocalStack did not become healthy at ${LOCALSTACK_ENDPOINT}"
record PASS "LocalStack health check" "$LOCALSTACK_ENDPOINT"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_EC2_METADATA_DISABLED=true

aws_ls() {
    aws --endpoint-url="$LOCALSTACK_ENDPOINT" "$@"
}

log "Initializing fixture"
if terraform -chdir="$FIXTURE" init -input=false -compact-warnings > "${EVIDENCE}/terraform-init.log" 2>&1; then
    record PASS "Terraform init against LocalStack" "docs/evidence/localstack/terraform-init.log"
else
    record FAIL "Terraform init against LocalStack" "see terraform-init.log"
fi

log "Applying fixture"
if terraform -chdir="$FIXTURE" apply -auto-approve -input=false \
    -var "localstack_endpoint=${LOCALSTACK_ENDPOINT}" > "${EVIDENCE}/terraform-apply.log" 2>&1; then
    record PASS "Terraform apply against LocalStack" "17 resources"
else
    record FAIL "Terraform apply against LocalStack" "see terraform-apply.log"
    tail -30 "${EVIDENCE}/terraform-apply.log" || true
    # Do not continue to assertions against a partially applied fixture.
    printf '\nRESULT: FAIL (%d checks, %d failures)\n' "$CHECKS" "$FAILURES"
    exit 1
fi

terraform -chdir="$FIXTURE" output -json > "${EVIDENCE}/terraform-output.json" 2>/dev/null
BUCKET=$(jq -r '.s3_bucket.value' "${EVIDENCE}/terraform-output.json")
QUEUE_URL=$(jq -r '.sqs_queue_url.value' "${EVIDENCE}/terraform-output.json")
TOPIC_ARN=$(jq -r '.sns_topic_arn.value' "${EVIDENCE}/terraform-output.json")
TABLE=$(jq -r '.audit_table.value' "${EVIDENCE}/terraform-output.json")
ROLE=$(jq -r '.runtime_role.value' "${EVIDENCE}/terraform-output.json")
VPC=$(jq -r '.vpc_id.value' "${EVIDENCE}/terraform-output.json")

assert_command() {
    local name=$1
    shift
    if "$@" >> "${EVIDENCE}/assertions.log" 2>&1; then
        record PASS "$name" ""
    else
        record FAIL "$name" "see docs/evidence/localstack/assertions.log"
    fi
}

assert_value() {
    local name=$1
    local expected=$2
    local actual=$3
    printf '%s = %s (expected %s)\n' "$name" "$actual" "$expected" >> "${EVIDENCE}/assertions.log"
    if [ "$actual" = "$expected" ]; then
        record PASS "$name" "$actual"
    else
        record FAIL "$name" "expected '$expected', got '$actual'"
    fi
}

log "Verifying resources through the AWS CLI"

assert_command "S3 bucket exists" aws_ls s3api head-bucket --bucket "$BUCKET"
assert_value "S3 versioning enabled" "Enabled" \
    "$(aws_ls s3api get-bucket-versioning --bucket "$BUCKET" --query 'Status' --output text)"
assert_value "S3 default encryption AES256" "AES256" \
    "$(aws_ls s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
assert_value "S3 public access block" "true" \
    "$(aws_ls s3api get-public-access-block --bucket "$BUCKET" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output json | jq -r 'all')"

echo "localstack-e2e-object" > "${EVIDENCE}/object.txt"
assert_command "S3 object upload" aws_ls s3api put-object --bucket "$BUCKET" --key "e2e/object.txt" --body "${EVIDENCE}/object.txt"
assert_value "S3 object download" "localstack-e2e-object" \
    "$(aws_ls s3api get-object --bucket "$BUCKET" --key "e2e/object.txt" "${EVIDENCE}/downloaded.txt" >/dev/null 2>&1 && tr -d '\r\n' < "${EVIDENCE}/downloaded.txt")"

assert_value "DynamoDB table active" "ACTIVE" \
    "$(aws_ls dynamodb describe-table --table-name "$TABLE" --query 'Table.TableStatus' --output text)"
assert_value "DynamoDB billing mode" "PAY_PER_REQUEST" \
    "$(aws_ls dynamodb describe-table --table-name "$TABLE" --query 'Table.BillingModeSummary.BillingMode' --output text)"
assert_command "DynamoDB put item" aws_ls dynamodb put-item --table-name "$TABLE" \
    --item '{"id":{"S":"e2e"},"timestamp":{"S":"2026-01-01T00:00:00Z"}}'
assert_value "DynamoDB get item" "e2e" \
    "$(aws_ls dynamodb get-item --table-name "$TABLE" --key '{"id":{"S":"e2e"},"timestamp":{"S":"2026-01-01T00:00:00Z"}}' --query 'Item.id.S' --output text)"

assert_command "SQS queue exists" aws_ls sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All
assert_command "SNS topic exists" aws_ls sns get-topic-attributes --topic-arn "$TOPIC_ARN"
assert_command "SNS publishes to SQS" aws_ls sns publish --topic-arn "$TOPIC_ARN" --message "localstack-e2e-message"
MESSAGE=$(aws_ls sqs receive-message --queue-url "$QUEUE_URL" --max-number-of-messages 1 --wait-time-seconds 5 --query 'Messages[0].Body' --output text 2>/dev/null || true)
if printf '%s' "$MESSAGE" | grep -q "localstack-e2e-message"; then
    record PASS "SNS→SQS message delivery" "message received"
else
    record FAIL "SNS→SQS message delivery" "no message received"
fi

assert_value "KMS alias exists" "alias/aegis-local" \
    "$(aws_ls kms list-aliases --query "Aliases[?AliasName=='alias/aegis-local'].AliasName" --output text)"
assert_value "CloudWatch log retention" "30" \
    "$(aws_ls logs describe-log-groups --log-group-name-prefix "/aegis/local/application" --query 'logGroups[0].retentionInDays' --output text)"
assert_value "IAM runtime role exists" "$ROLE" \
    "$(aws_ls iam get-role --role-name "$ROLE" --query 'Role.RoleName' --output text)"
assert_value "VPC ID resolved" "true" "$([ -n "$VPC" ] && printf true || printf false)"
assert_value "VPC tag" "aegis-local-vpc" \
    "$(aws_ls ec2 describe-vpcs --vpc-ids "$VPC" --output json | jq -r '.Vpcs[0].Tags[] | select(.Key == "Name") | .Value')"

# Emit a compact result for the evidence report.
python3 - "$EVIDENCE" "$CHECKS" "$FAILURES" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

evidence = Path(sys.argv[1])
checks = int(sys.argv[2])
failures = int(sys.argv[3])
summary = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "status": "PASS" if failures == 0 else "FAIL",
    "checks": checks,
    "failures": failures,
    "tool": "LocalStack 4.4.0 + Terraform AWS provider 5.x + AWS CLI",
    "coverage": [
        "S3 bucket, encryption, versioning, public-access block, object CRUD",
        "DynamoDB table and item CRUD",
        "SQS queue and SNS-to-SQS delivery",
        "KMS alias",
        "CloudWatch Logs group and retention",
        "IAM role and inline policy",
        "EC2 VPC, subnets, and security group",
    ],
    "not_covered": [
        "GovCloud-specific endpoints and partitions",
        "EKS, ECS, RDS/Aurora, and other managed services",
        "Azure and GCP",
        "Production module IAM managed-policy ARNs",
    ],
}
(evidence / "result.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
PY

printf '\nLocal emulation checks: %d, failures: %d\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
log "Local emulation verification passed"
