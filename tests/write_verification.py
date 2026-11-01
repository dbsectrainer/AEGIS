"""Write docs/evidence/verification.json from the verification status table."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

status_file = Path(sys.argv[1])
repo = Path(sys.argv[2]).resolve()
docs_site = repo / "docs" / "site"
evidence = repo / "docs" / "evidence"

checks = []
required_failures = 0
for line in status_file.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    name, status, detail = line.split("\t", 2)
    checks.append({"name": name, "status": status, "detail": detail})
    if status == "FAIL":
        required_failures += 1

docs_count = 0
if (docs_site / "manifest.json").is_file():
    try:
        docs_count = len(json.loads((docs_site / "manifest.json").read_text(encoding="utf-8"))["documents"])
    except (json.JSONDecodeError, KeyError):
        docs_count = 0

terraform_files = list((repo / "terraform").rglob("*.tf"))
resource_count = sum(
    len(re.findall(r'^resource\s+"', path.read_text(encoding="utf-8"), re.MULTILINE))
    for path in terraform_files
)
module_count = len(list((repo / "terraform" / "modules").glob("*/")))
screenshots = sorted((evidence / "screenshots").glob("*.png")) if (evidence / "screenshots").is_dir() else []
test_count = 0
for log in (evidence / "test-results").glob("*.log"):
    match = re.search(r"Ran (\d+) tests?", log.read_text(encoding="utf-8", errors="replace"))
    if match:
        test_count = max(test_count, int(match.group(1)))

control_refs = set()
for path in (repo / "docs").rglob("*.md"):
    if "site" in path.parts or "evidence" in path.parts:
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    control_refs.update(re.findall(r"\b[A-Z]{2}-\d{1,2}(?:\(\d+\))?\b", text))

checkov_findings = 0
checkov_log = evidence / "test-results" / "checkov-advisory-scan.log"
if checkov_log.is_file():
    match = re.search(r"Failed checks: (\d+)", checkov_log.read_text(encoding="utf-8", errors="replace"))
    if match:
        checkov_findings = int(match.group(1))

status = "PASS" if required_failures == 0 else "FAIL"
snapshot = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "status": status,
    "checks": checks,
    "counts": {
        "documents": docs_count,
        "terraform_resource_blocks": resource_count,
        "terraform_modules": module_count,
        "control_references": len(control_refs),
        "test_cases": test_count,
        "screenshots": len(screenshots),
        "checkov_findings": checkov_findings,
    },
    "artifacts": {
        "verification_report": "docs/evidence/verification-report.md",
        "screenshots": [f"docs/evidence/screenshots/{path.name}" for path in screenshots],
        "test_results": "docs/evidence/test-results/",
        "build_results": "docs/evidence/build-results/",
    },
}
(evidence / "verification.json").write_text(
    json.dumps(snapshot, indent=2) + "\n", encoding="utf-8"
)
print(f"Wrote {evidence / 'verification.json'} ({status})")
