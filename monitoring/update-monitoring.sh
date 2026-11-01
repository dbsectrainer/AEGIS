#!/usr/bin/env bash
#
# Revalidate monitoring configuration, rebuild the manifest, and report which
# files changed since the prior manifest. Does not deploy to a cloud provider.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="development"

usage() {
    cat <<'USAGE'
Usage: update-monitoring.sh [options]

Options:
  -e, --environment <env>    Environment label (development|staging|production)
  -h, --help                 Display this help message

Runs init-monitoring.sh, then compares the new manifest with the previous one.
USAGE
    exit 0
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -e|--environment)
            [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 1; }
            ENVIRONMENT="$2"
            shift 2
            ;;
        -h|--help)        usage ;;
        *)                echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
    esac
done

manifest="${SCRIPT_DIR}/generated/monitoring-manifest-${ENVIRONMENT}.json"
previous=""
if [ -f "$manifest" ]; then
    previous="$(mktemp "${TMPDIR:-/tmp}/aegis-monitoring.XXXXXX")"
    cp "$manifest" "$previous"
fi

"${SCRIPT_DIR}/init-monitoring.sh" -e "$ENVIRONMENT"

if [ -n "$previous" ]; then
    echo "Changed monitoring files:"
    jq -r '.files[] | "\(.path) \(.sha256)"' "$previous" | sort > "${previous}.old"
    jq -r '.files[] | "\(.path) \(.sha256)"' "$manifest" | sort > "${previous}.new"
    if diff -u "${previous}.old" "${previous}.new"; then
        echo "No monitoring configuration changes detected."
    fi
    rm -f "$previous" "${previous}.old" "${previous}.new"
else
    echo "No previous manifest; created the initial monitoring manifest."
fi
