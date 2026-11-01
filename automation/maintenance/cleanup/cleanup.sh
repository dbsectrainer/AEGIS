#!/usr/bin/env bash
#
# Remove generated local artifacts. The default is a dry run; pass --yes to
# delete. Tracked source files and evidence under docs/evidence are never removed.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
CONFIRM=false

usage() {
    cat <<'USAGE'
Usage: cleanup.sh [options]

Options:
  -y, --yes        Delete generated artifacts (default: dry run)
  -h, --help       Display this help message

Removes: Terraform caches and plans, docs/site, security-reports,
compliance-reports, and monitoring/generated. Source and docs/evidence are kept.
USAGE
    exit 0
}

log() {
    printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -y|--yes) CONFIRM=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
    esac
done

TARGETS=(
    "docs/site"
    "security-reports"
    "compliance-reports"
    "monitoring/generated"
)

for target in "${TARGETS[@]}"; do
    if [ -e "${REPO_ROOT}/${target}" ]; then
        if [ "$CONFIRM" = true ]; then
            rm -rf "${REPO_ROOT:?}/${target}"
            log "Removed ${target}"
        else
            log "[DRY RUN] Would remove ${target}"
        fi
    fi
done

while IFS= read -r path; do
    if [ "$CONFIRM" = true ]; then
        rm -rf "$path"
        log "Removed ${path#"$REPO_ROOT"/}"
    else
        log "[DRY RUN] Would remove ${path#"$REPO_ROOT"/}"
    fi
done < <(find "$REPO_ROOT/terraform" \( -name '.terraform' -o -name '*.tfplan' -o -name 'tfplan' \) -print 2>/dev/null)

if [ "$CONFIRM" != true ]; then
    log "Dry run complete. Re-run with --yes to delete."
fi
