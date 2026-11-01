#!/usr/bin/env bash
#
# Reproducible verification suite. Writes logs, screenshots, and a machine-readable
# verification snapshot under docs/evidence/. CI and local operators run this.

set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
EVIDENCE="${REPO_ROOT}/docs/evidence"
RESULTS="${EVIDENCE}/test-results"
STATUS_FILE="${RESULTS}/status.tsv"
cd "$REPO_ROOT" || exit 1

mkdir -p "$RESULTS" "${EVIDENCE}/screenshots" "${EVIDENCE}/build-results"
: > "$STATUS_FILE"

failures=0
records=()

record() {
    local name=$1
    local status=$2
    local detail=${3:-}
    records+=("${name}|${status}|${detail}")
    printf '%s\t%s\t%s\n' "$name" "$status" "$detail" >> "$STATUS_FILE"
    if [ "$status" = "FAIL" ]; then
        failures=$((failures + 1))
    fi
}

run_step() {
    local name=$1
    shift
    local slug
    slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr ' /' '--' | tr -cd 'a-z0-9._-')
    local log="$RESULTS/${slug}.log"
    printf '\n== %s ==\n' "$name"
    if "$@" > "$log" 2>&1; then
        printf 'PASS: %s (%s)\n' "$name" "${log#"$REPO_ROOT"/}"
        record "$name" PASS "${log#"$REPO_ROOT"/}"
    else
        printf 'FAIL: %s (%s)\n' "$name" "${log#"$REPO_ROOT"/}"
        tail -20 "$log" || true
        record "$name" FAIL "${log#"$REPO_ROOT"/}"
    fi
}

run_shellcheck() {
    shellcheck \
        "${REPO_ROOT}/automation/deployment/infrastructure/deploy.sh" \
        "${REPO_ROOT}/automation/security/scanning/run-scans.sh" \
        "${REPO_ROOT}/automation/security/scanning/run-audit.sh" \
        "${REPO_ROOT}/automation/compliance/audit/run-compliance.sh" \
        "${REPO_ROOT}/automation/maintenance/backup/backup.sh" \
        "${REPO_ROOT}/automation/maintenance/cleanup/cleanup.sh" \
        "${REPO_ROOT}/docs/generate-docs.sh" \
        "${REPO_ROOT}/monitoring/init-monitoring.sh" \
        "${REPO_ROOT}/monitoring/update-monitoring.sh" \
        "${REPO_ROOT}/tests/run-tests.sh" \
        "${REPO_ROOT}/tests/localstack/run-localstack-tests.sh"
}

run_checkov() {
    if command -v checkov >/dev/null 2>&1; then
        checkov -d "${REPO_ROOT}/terraform" --quiet --compact || true
    else
        echo "checkov is not installed; advisory scan skipped"
    fi
}

run_advisory_step() {
    local name=$1
    shift
    local slug
    slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr ' /' '--' | tr -cd 'a-z0-9._-')
    local log="$RESULTS/${slug}.log"
    printf '\n== %s (advisory) ==\n' "$name"
    if "$@" > "$log" 2>&1; then
        local findings
        findings=$(grep -oE 'Failed checks: [0-9]+' "$log" | tail -1 | grep -oE '[0-9]+' || true)
        findings=${findings:-0}
        printf 'ADVISORY: %s (%s findings; %s)\n' "$name" "$findings" "${log#"$REPO_ROOT"/}"
        record "$name" ADVISORY "${findings} findings; ${log#"$REPO_ROOT"/}"
    else
        printf 'ADVISORY: %s could not run (%s)\n' "$name" "${log#"$REPO_ROOT"/}"
        record "$name" ADVISORY "scan unavailable; ${log#"$REPO_ROOT"/}"
    fi
}

echo "AEGIS verification suite"
echo "Repository: ${REPO_ROOT}"
echo "Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

run_step "Repository contract tests" python3 -m unittest discover -s "${REPO_ROOT}/tests" -p 'test_*.py' -v
run_step "Terraform format validate and mock tests" make -C "$REPO_ROOT" test-terraform
run_step "Offline Trivy security scan" make -C "$REPO_ROOT" test-security
run_step "ShellCheck" run_shellcheck
run_step "Markdown lint" make -C "$REPO_ROOT" docs-lint
run_step "Offline compliance audit" make -C "$REPO_ROOT" security-compliance
run_step "Documentation portal build" make -C "$REPO_ROOT" docs
run_step "Monitoring manifest validation" make -C "$REPO_ROOT" monitoring-init
run_step "Deployment dry run" make -C "$REPO_ROOT" deploy-dry-run
run_step "Security scan dry run" ./automation/security/scanning/run-scans.sh -e production --dry-run
run_step "Security audit dry run" ./automation/security/scanning/run-audit.sh -e production --dry-run
run_step "Backup dry run" ./automation/maintenance/backup/backup.sh --dry-run
run_advisory_step "Checkov advisory scan" run_checkov

# Functional E2E against the generated portal, before the verification snapshot
# exists. This proves navigation, search, responsive layout, and link integrity.
run_step "Documentation portal E2E" python3 "${REPO_ROOT}/tests/e2e/test_docs_portal.py"

# Build the machine-readable snapshot and re-render the portal with it.
python3 "${REPO_ROOT}/tests/write_verification.py" "$STATUS_FILE" "$REPO_ROOT" || failures=$((failures + 1))
run_step "Documentation portal rebuild with verification snapshot" make -C "$REPO_ROOT" docs

# Capture the final screenshots against the snapshot-bearing portal.
if [ -x "${REPO_ROOT}/tests/e2e/test_docs_portal.py" ] || [ -f "${REPO_ROOT}/tests/e2e/test_docs_portal.py" ]; then
    if python3 "${REPO_ROOT}/tests/e2e/test_docs_portal.py" --screenshots-only > "$RESULTS/documentation-portal-screenshots.log" 2>&1; then
        printf 'PASS: Final screenshots (%s)\n' "${RESULTS#"$REPO_ROOT"/}/documentation-portal-screenshots.log"
        record "Final screenshots" PASS "docs/evidence/test-results/documentation-portal-screenshots.log"
    else
        printf 'FAIL: Final screenshots\n'
        tail -20 "$RESULTS/documentation-portal-screenshots.log" || true
        record "Final screenshots" FAIL "docs/evidence/test-results/documentation-portal-screenshots.log"
    fi
fi

# Refresh snapshot with the final screenshot count/status.
python3 "${REPO_ROOT}/tests/write_verification.py" "$STATUS_FILE" "$REPO_ROOT" || true

# Keep the key build outputs alongside the test logs.
cp "$RESULTS/terraform-format-validate-and-mock-tests.log" "${EVIDENCE}/build-results/terraform-fmt-validate-test.log"
cp "$RESULTS/documentation-portal-build.log" "${EVIDENCE}/build-results/documentation-portal-build.log"
cp "$RESULTS/offline-trivy-security-scan.log" "${EVIDENCE}/build-results/trivy-scan.log"
cp "$RESULTS/checkov-advisory-scan.log" "${EVIDENCE}/build-results/checkov-advisory.log"

printf '\nVerification summary\n'
printf '%-52s %s\n' "Check" "Status"
printf '%-52s %s\n' "----------------------------------------------------" "------"
for record in "${records[@]}"; do
    IFS='|' read -r name status detail <<< "$record"
    printf '%-52s %s\n' "$name" "$status"
done
printf '\nEvidence: %s\n' "${EVIDENCE#"$REPO_ROOT"/}"
printf 'Snapshot: %s\n' "${EVIDENCE#"$REPO_ROOT"/}/verification.json"

if [ "$failures" -gt 0 ]; then
    printf '\nRESULT: FAIL (%d failed check(s))\n' "$failures"
    exit 1
fi

printf '\nRESULT: PASS\n'
