#!/bin/bash

# Security Scanning Script
# This script orchestrates various security scans across the infrastructure

set -e

# Default values
ENVIRONMENT="development"
SCAN_TYPE="all"
SEVERITY="high"
VERBOSE=false
DRY_RUN=false
OUTPUT_DIR="security-reports"

# Function to display usage information
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -e, --environment <env>    Environment to scan (development|staging|production)"
    echo "  -t, --type <type>         Type of scan (all|vulnerability|compliance|configuration)"
    echo "  -s, --severity <level>    Minimum severity level (low|medium|high|critical)"
    echo "  -o, --output <dir>        Output directory for reports"
    echo "  -v, --verbose             Enable verbose output"
    echo "  -d, --dry-run             Perform a dry run without making changes"
    echo "  -h, --help                Display this help message"
    exit 1
}

# Function to log messages
log() {
    local level=$1
    shift
    local message=$@
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

# Function to validate environment
validate_environment() {
    case $ENVIRONMENT in
        development|staging|production)
            return 0
            ;;
        *)
            log "ERROR" "Invalid environment: $ENVIRONMENT"
            exit 1
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check for required tools
    command -v aws >/dev/null 2>&1 || { log "ERROR" "AWS CLI is required but not installed."; exit 1; }
    command -v trivy >/dev/null 2>&1 || { log "ERROR" "Trivy is required but not installed."; exit 1; }
    command -v tfsec >/dev/null 2>&1 || { log "ERROR" "tfsec is required but not installed."; exit 1; }
    
    # Check for required environment variables
    [[ -z "${AWS_ACCESS_KEY_ID}" ]] && { log "ERROR" "AWS_ACCESS_KEY_ID is not set"; exit 1; }
    [[ -z "${AWS_SECRET_ACCESS_KEY}" ]] && { log "ERROR" "AWS_SECRET_ACCESS_KEY is not set"; exit 1; }
    
    # Create output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"
    
    log "INFO" "Prerequisites check passed"
}

# Function to send Slack notification on high severity findings
notify_slack() {
    local message=$1
    if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
        curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$message\"}" "$SLACK_WEBHOOK_URL"
    else
        log "WARN" "SLACK_WEBHOOK_URL not set; skipping Slack notification."
    fi
}

# Function to run vulnerability scan
run_vulnerability_scan() {
    log "INFO" "Running vulnerability scan..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would run vulnerability scan"
        return 0
    fi

    # Scan infrastructure code (JSON and SARIF)
    log "INFO" "Scanning infrastructure code..."
    trivy config --severity $SEVERITY \
        --format json \
        --output "$OUTPUT_DIR/vulnerability-terraform-$ENVIRONMENT.json" \
        ./terraform
    trivy config --severity $SEVERITY \
        --format sarif \
        --output "$OUTPUT_DIR/trivy-terraform-$ENVIRONMENT.sarif" \
        ./terraform

    # Scan container images (JSON and SARIF)
    log "INFO" "Scanning container images..."
    trivy image --severity $SEVERITY \
        --format json \
        --output "$OUTPUT_DIR/vulnerability-containers-$ENVIRONMENT.json" \
        $(aws ecr describe-repositories --query 'repositories[*].repositoryUri' --output text)
    trivy image --severity $SEVERITY \
        --format sarif \
        --output "$OUTPUT_DIR/trivy-containers-$ENVIRONMENT.sarif" \
        $(aws ecr describe-repositories --query 'repositories[*].repositoryUri' --output text)

    log "INFO" "Vulnerability scan completed"
}

# Function to run compliance scan
run_compliance_scan() {
    log "INFO" "Running compliance scan..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would run compliance scan"
        return 0
    fi

    # Run tfsec for compliance checks (JSON and SARIF)
    log "INFO" "Running infrastructure compliance checks..."
    tfsec ./terraform \
        --format json \
        --out "$OUTPUT_DIR/compliance-terraform-$ENVIRONMENT.json" \
        --minimum-severity $SEVERITY
    tfsec ./terraform \
        --format sarif \
        --out "$OUTPUT_DIR/tfsec-$ENVIRONMENT.sarif" \
        --minimum-severity $SEVERITY

    # Run AWS Config rules check
    log "INFO" "Checking AWS Config rules..."
    aws configservice describe-compliance-by-config-rule \
        --output json > "$OUTPUT_DIR/compliance-aws-config-$ENVIRONMENT.json"

    log "INFO" "Compliance scan completed"
}

# Function to run configuration scan
run_configuration_scan() {
    log "INFO" "Running configuration scan..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would run configuration scan"
        return 0
    fi

    # Check S3 bucket configurations
    log "INFO" "Checking S3 bucket configurations..."
    aws s3api list-buckets --query 'Buckets[*].Name' --output text | \
    while read -r bucket; do
        aws s3api get-bucket-acl --bucket "$bucket" > "$OUTPUT_DIR/config-s3-$bucket-$ENVIRONMENT.json"
    done

    # Check security group configurations
    log "INFO" "Checking security group configurations..."
    aws ec2 describe-security-groups \
        --output json > "$OUTPUT_DIR/config-security-groups-$ENVIRONMENT.json"

    # Check IAM configurations
    log "INFO" "Checking IAM configurations..."
    aws iam get-account-password-policy \
        --output json > "$OUTPUT_DIR/config-iam-password-policy-$ENVIRONMENT.json"

    log "INFO" "Configuration scan completed"
}

# Function to generate report
generate_report() {
    log "INFO" "Generating consolidated report..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would generate report"
        return 0
    fi

    # Create report header
    cat << EOF > "$OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"
# Security Scan Report

Environment: $ENVIRONMENT
Date: $(date '+%Y-%m-%d %H:%M:%S')
Scan Type: $SCAN_TYPE
Minimum Severity: $SEVERITY

## Summary

EOF

    # Add vulnerability scan summary
    if [ -f "$OUTPUT_DIR/vulnerability-terraform-$ENVIRONMENT.json" ]; then
        echo "### Vulnerability Scan" >> "$OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"
        jq -r '.Results | length' "$OUTPUT_DIR/vulnerability-terraform-$ENVIRONMENT.json" >> "$OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"
        # Notify Slack if high/critical findings
        high_count=$(jq '[.Results[] | select(.Severity=="HIGH" or .Severity=="CRITICAL")] | length' "$OUTPUT_DIR/vulnerability-terraform-$ENVIRONMENT.json")
        if [ "$high_count" -gt 0 ]; then
            notify_slack "[$ENVIRONMENT] High or Critical vulnerabilities found: $high_count. See $OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"
        fi
    fi

    # Add compliance scan summary
    if [ -f "$OUTPUT_DIR/compliance-terraform-$ENVIRONMENT.json" ]; then
        echo "### Compliance Scan" >> "$OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"
        jq -r '.Results | length' "$OUTPUT_DIR/compliance-terraform-$ENVIRONMENT.json" >> "$OUTPUT_DIR/security-scan-report-$ENVIRONMENT.md"
    fi

    log "INFO" "Report generation completed"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -t|--type)
            SCAN_TYPE="$2"
            shift 2
            ;;
        -s|--severity)
            SEVERITY="$2"
            shift 2
            ;;
        -o|--output)
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
        -h|--help)
            usage
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            ;;
    esac
done

# Main execution
main() {
    log "INFO" "Starting security scan"
    log "INFO" "Environment: $ENVIRONMENT"
    log "INFO" "Scan type: $SCAN_TYPE"
    log "INFO" "Severity level: $SEVERITY"
    
    # Validate inputs
    validate_environment
    
    # Check prerequisites
    check_prerequisites
    
    # Run scans based on type
    case $SCAN_TYPE in
        all)
            run_vulnerability_scan
            run_compliance_scan
            run_configuration_scan
            ;;
        vulnerability)
            run_vulnerability_scan
            ;;
        compliance)
            run_compliance_scan
            ;;
        configuration)
            run_configuration_scan
            ;;
        *)
            log "ERROR" "Invalid scan type: $SCAN_TYPE"
            exit 1
            ;;
    esac
    
    # Generate consolidated report
    generate_report
    
    log "INFO" "Security scan completed successfully"
}

# Execute main function
main
