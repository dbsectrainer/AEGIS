#!/usr/bin/env bash
#
# Infrastructure Deployment Script
# Plans and applies the Terraform root module for an environment/region.
#
# Safety:
#   --dry-run validates the configuration and prints the operations that would
#   run. It never initializes a backend, plans, applies, or mutates cloud state.
#   A real deployment requires cloud credentials and a provisioned remote state
#   backend (see terraform/environments/<env>/<region>/main.tf).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

# Defaults
ENVIRONMENT="production"
REGION="southeast"
COMPONENTS="all"
VERBOSE=false
DRY_RUN=false
AUTO_APPROVE=false

usage() {
    cat <<'EOF'
Usage: deploy.sh [options]

Options:
  -e, --environment <env>    Environment (development|staging|production)
  -r, --region <region>      Region (northeast|southeast|west)
  -c, --components <comp>    Components (all|network|compute|database)
  -v, --verbose              Echo commands before running them
  -d, --dry-run              Validate locally without changing cloud state
  -y, --auto-approve         Do not prompt before terraform apply
  -h, --help                 Display this help message

Examples:
  ./deploy.sh -e production -r southeast --dry-run
  ./deploy.sh -e production -r southeast --components network
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

validate_region() {
    case "$REGION" in
        northeast|southeast|west) ;;
        *) die "Invalid region: $REGION (expected northeast|southeast|west)" ;;
    esac
}

validate_components() {
    case "$COMPONENTS" in
        all|network|compute|database) ;;
        *) die "Invalid components value: $COMPONENTS (expected all|network|compute|database)" ;;
    esac
}

resolve_tf_dir() {
    TF_DIR="${REPO_ROOT}/terraform/environments/${ENVIRONMENT}/${REGION}"
    [ -d "$TF_DIR" ] || die "No Terraform environment at ${TF_DIR#"$REPO_ROOT"/}."
    [ -f "$TF_DIR/main.tf" ] || die "Terraform environment ${TF_DIR#"$REPO_ROOT"/} has no main.tf."
}

component_targets() {
    case "$COMPONENTS" in
        all)
            TARGETS=()
            ;;
        network)
            TARGETS=(
                -target=module.aws_networking
                -target=module.azure_networking
                -target=module.gcp_networking
            )
            ;;
        compute)
            TARGETS=(
                -target=module.aws_compute
                -target=module.azure_compute
                -target=module.gcp_compute
            )
            ;;
        database)
            TARGETS=(
                -target=module.aws_database
                -target=module.azure_database
                -target=module.gcp_database
            )
            ;;
    esac
}

check_prerequisites() {
    command -v terraform >/dev/null 2>&1 || die "Terraform is required but not installed."
    command -v jq >/dev/null 2>&1 || die "jq is required but not installed."

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "Dry run selected; cloud credentials and AWS CLI are not required."
        return 0
    fi

    command -v aws >/dev/null 2>&1 || die "AWS CLI is required but not installed."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        die "No usable AWS credentials. Configure a profile/SSO session or use --dry-run."
    fi
}

dry_run() {
    log "INFO" "[DRY RUN] Environment: $ENVIRONMENT; region: $REGION; components: $COMPONENTS"
    log "INFO" "[DRY RUN] Terraform directory: ${TF_DIR#"$REPO_ROOT"/}"

    local fmt_status=0
    terraform fmt -check -recursive "$TF_DIR" || fmt_status=$?
    if [ "$fmt_status" -ne 0 ]; then
        die "Terraform formatting check failed; run 'terraform fmt -recursive terraform'."
    fi

    if [ "$COMPONENTS" = "all" ]; then
        log "INFO" "[DRY RUN] Would run: terraform init; terraform plan -out=tfplan; terraform apply tfplan"
    else
        log "INFO" "[DRY RUN] Would run: terraform init; terraform plan ${TARGETS[*]} -out=tfplan; terraform apply tfplan"
    fi
    log "INFO" "[DRY RUN] No cloud state was read or changed."
}

initialize() {
    log "INFO" "Initializing Terraform for $ENVIRONMENT/$REGION"
    ( cd "$TF_DIR" && run terraform init -input=false )
}

deploy() {
    log "INFO" "Planning infrastructure components: $COMPONENTS"

    local plan_args=()
    if [ "${#TARGETS[@]}" -gt 0 ]; then
        plan_args=("${TARGETS[@]}")
    fi

    (
        cd "$TF_DIR"
        run terraform plan "${plan_args[@]}" -out=tfplan
    )

    if [ "$AUTO_APPROVE" != true ]; then
        [ -t 0 ] || die "Refusing to apply non-interactively without --auto-approve."
        printf 'Apply the saved plan to %s/%s? [y/N] ' "$ENVIRONMENT" "$REGION"
        read -r reply
        case "$reply" in
            y|Y|yes|YES) ;;
            *) log "INFO" "Apply cancelled by operator."; exit 0 ;;
        esac
    fi

    (
        cd "$TF_DIR"
        run terraform apply -input=false tfplan
    )
}

validate_deployment() {
    log "INFO" "Resolving deployment outputs"
    (
        cd "$TF_DIR"
        run terraform output -json >/dev/null
    )
    log "INFO" "Terraform outputs resolved. Review them with: terraform -chdir=${TF_DIR#"$REPO_ROOT"/} output"
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -e|--environment)
                [ "$#" -ge 2 ] || die "Missing value for $1"
                ENVIRONMENT="$2"
                shift 2
                ;;
            -r|--region)
                [ "$#" -ge 2 ] || die "Missing value for $1"
                REGION="$2"
                shift 2
                ;;
            -c|--components)
                [ "$#" -ge 2 ] || die "Missing value for $1"
                COMPONENTS="$2"
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
            -y|--auto-approve)
                AUTO_APPROVE=true
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

    log "INFO" "Starting infrastructure deployment"
    validate_environment
    validate_region
    validate_components
    resolve_tf_dir
    component_targets
    check_prerequisites

    if [ "$DRY_RUN" = true ]; then
        dry_run
        log "INFO" "Dry run completed successfully"
        return 0
    fi

    initialize
    deploy
    validate_deployment
    log "INFO" "Infrastructure deployment completed successfully"
}

main "$@"
