#!/usr/bin/env bash
#
# Create a verified local archive of repository configuration and documentation.
# This is not a cloud data backup. Secrets, Terraform state, generated reports,
# and provider caches are excluded.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
BACKUP_DIR="${REPO_ROOT}/backups"
DRY_RUN=false

usage() {
    cat <<'USAGE'
Usage: backup.sh [options]

Options:
  -o, --output <dir>    Destination directory (default: backups/)
  -d, --dry-run         Print the archive plan without writing
  -h, --help            Display this help message
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
        -o|--output) [ "$#" -ge 2 ] || die "Missing value for $1"; BACKUP_DIR="$2"; shift 2 ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
done

STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
ARCHIVE="${BACKUP_DIR}/aegis-config-${STAMP}.tar.gz"

INCLUDES=(
    README.md
    Makefile
    .gitignore
    automation
    data
    docs
    itsm_templates
    monitoring
    raci
    security-reference
    templates
    terraform
    tests
)

for item in "${INCLUDES[@]}"; do
    [ -e "${REPO_ROOT}/${item}" ] || die "Required backup item is missing: $item"
done

if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Would create ${ARCHIVE#"$REPO_ROOT"/}"
    log "[DRY RUN] Included: ${INCLUDES[*]}"
    log "[DRY RUN] Excluded: .git, .terraform, *.tfstate, *.tfplan, *.tfvars, security-reports, compliance-reports, backups, docs/site"
    exit 0
fi

mkdir -p "$BACKUP_DIR"
tar -czf "$ARCHIVE" \
    --exclude='.git' \
    --exclude='.terraform' \
    --exclude='*.tfstate' \
    --exclude='*.tfstate.backup' \
    --exclude='*.tfplan' \
    --exclude='tfplan' \
    --exclude='*.tfvars' \
    --exclude='security-reports' \
    --exclude='compliance-reports' \
    --exclude='backups' \
    --exclude='docs/site' \
    --exclude='node_modules' \
    -C "$REPO_ROOT" "${INCLUDES[@]}"

tar -tzf "$ARCHIVE" >/dev/null || die "Backup archive failed verification: $ARCHIVE"

if command -v shasum >/dev/null 2>&1; then
    DIGEST=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
else
    DIGEST=$(sha256sum "$ARCHIVE" | awk '{print $1}')
fi
printf '%s  %s\n' "$DIGEST" "$(basename "$ARCHIVE")" > "${ARCHIVE}.sha256"

log "Verified backup created: ${ARCHIVE#"$REPO_ROOT"/}"
log "SHA-256: $DIGEST"
