#!/usr/bin/env bash
#
# Validate monitoring configuration and build a checksummed local manifest.
# This script does not deploy dashboards to a cloud provider; it prepares a
# reviewable bundle for the monitoring backend of record.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="development"
OUTPUT_DIR="${SCRIPT_DIR}/generated"

usage() {
    cat <<'USAGE'
Usage: init-monitoring.sh [options]

Options:
  -e, --environment <env>    Environment label (development|staging|production)
  -o, --output <dir>         Output directory (default: monitoring/generated)
  -h, --help                 Display this help message

Validates monitoring/alerts/**, monitoring/dashboards/**, and
monitoring/logging/** JSON, then writes manifest.json with SHA-256 digests.
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

while [ "$#" -gt 0 ]; do
    case "$1" in
        -e|--environment) [ "$#" -ge 2 ] || die "Missing value for $1"; ENVIRONMENT="$2"; shift 2 ;;
        -o|--output)      [ "$#" -ge 2 ] || die "Missing value for $1"; OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)        usage ;;
        *)                die "Unknown option: $1 (use --help)" ;;
    esac
done

case "$ENVIRONMENT" in
    development|staging|production) ;;
    *) die "Invalid environment: $ENVIRONMENT (expected development|staging|production)" ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is required but not installed."

json_files=()
while IFS= read -r file; do
    json_files+=("$file")
done < <(find "${SCRIPT_DIR}/alerts" "${SCRIPT_DIR}/dashboards" "${SCRIPT_DIR}/logging" -type f -name '*.json' | sort)

[ "${#json_files[@]}" -gt 0 ] || die "No monitoring JSON configuration found."

mkdir -p "$OUTPUT_DIR"
manifest="$OUTPUT_DIR/monitoring-manifest-$ENVIRONMENT.json"
tmp="$manifest.tmp"

{
    printf '{\n  "environment": %s,\n  "generated_at": %s,\n  "files": [\n' \
        "$(jq -Rn --arg v "$ENVIRONMENT" '$v')" \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ' | jq -Rn '.')"
    first=true
    for file in "${json_files[@]}"; do
        jq empty "$file" || die "Invalid JSON: ${file#"$SCRIPT_DIR"/}"
        rel="${file#"$SCRIPT_DIR"/}"
        if command -v shasum >/dev/null 2>&1; then
            digest=$(shasum -a 256 "$file" | awk '{print $1}')
        else
            digest=$(sha256sum "$file" | awk '{print $1}')
        fi
        if [ "$first" = true ]; then
            first=false
        else
            printf ',\n'
        fi
        printf '    {"path": %s, "sha256": %s}' \
            "$(jq -Rn --arg v "$rel" '$v')" \
            "$(jq -Rn --arg v "$digest" '$v')"
    done
    printf '\n  ]\n}\n'
} > "$tmp"

jq empty "$tmp" || die "Generated manifest is not valid JSON"
mv "$tmp" "$manifest"

log "Validated ${#json_files[@]} monitoring file(s)"
log "Manifest written to ${manifest#"$SCRIPT_DIR"/} for environment $ENVIRONMENT"
log "This bundle has not been deployed. Apply it with the monitoring backend of record after review."
