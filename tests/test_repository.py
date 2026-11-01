"""Repository contract tests for AEGIS.

These tests are intentionally offline and fast. They validate repository
structure, documented automation entry points, configuration syntax, and secret
hygiene. Terraform provider validation and native plan tests live in the
Makefile's test-terraform target; browser E2E tests live under tests/e2e.
"""

from __future__ import annotations

import csv
import json
import re
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REQUIRED_FILES = [
    "README.md",
    "LICENSE",
    "Makefile",
    ".gitignore",
    ".markdownlint.json",
    "terraform/environments/production/southeast/main.tf",
    "terraform/environments/production/southeast/providers.tf",
    "terraform/environments/production/southeast/variables.tf",
    "terraform/environments/production/southeast/tests/production.tftest.hcl",
    "terraform/environments/production/southeast/terraform.tfvars.example",
    "docs/evidence/verification-report.md",
    "docs/generate-docs.sh",
    "docs/requirements.txt",
    "tests/run-tests.sh",
    "automation/security/scanning/run-scans.sh",
    "automation/security/scanning/run-audit.sh",
    "automation/compliance/audit/run-compliance.sh",
    "monitoring/init-monitoring.sh",
    "monitoring/update-monitoring.sh",
]

SHELL_SCRIPTS = [
    "automation/deployment/infrastructure/deploy.sh",
    "automation/security/scanning/run-scans.sh",
    "automation/security/scanning/run-audit.sh",
    "automation/compliance/audit/run-compliance.sh",
    "automation/maintenance/backup/backup.sh",
    "automation/maintenance/cleanup/cleanup.sh",
    "docs/generate-docs.sh",
    "monitoring/init-monitoring.sh",
    "monitoring/update-monitoring.sh",
    "tests/run-tests.sh",
]

JSON_FILES = [
    "monitoring/alerts/security/main.json",
    "monitoring/dashboards/infrastructure/main.json",
    "monitoring/logging/infrastructure/config.json",
    "itsm_templates/jira-import.json",
    "itsm_templates/servicenow-import.json",
]


def run(args: list[str], timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


class RepositoryStructureTests(unittest.TestCase):
    def test_required_files_exist(self) -> None:
        for rel in REQUIRED_FILES:
            with self.subTest(path=rel):
                path = ROOT / rel
                self.assertTrue(path.is_file(), f"missing required file: {rel}")
                self.assertGreater(path.stat().st_size, 0, f"empty required file: {rel}")

    def test_shell_scripts_are_executable(self) -> None:
        for rel in SHELL_SCRIPTS:
            with self.subTest(path=rel):
                path = ROOT / rel
                self.assertTrue(path.is_file(), f"missing script: {rel}")
                self.assertTrue(
                    path.stat().st_mode & 0o111,
                    f"script is not executable: {rel}",
                )

    def test_readme_relative_links_resolve(self) -> None:
        text = (ROOT / "README.md").read_text(encoding="utf-8")
        links = re.findall(r"\[[^\]]*\]\(([^)]+)\)", text)
        for target in links:
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = target.split("#", 1)[0]
            with self.subTest(target=target):
                self.assertTrue((ROOT / target).exists(), f"broken README link: {target}")

    def test_makefile_commands_reference_existing_scripts(self) -> None:
        makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
        referenced = set(re.findall(r"\./(?:automation|monitoring|docs|tests)/[A-Za-z0-9_./-]+", makefile))
        for rel in referenced:
            with self.subTest(path=rel):
                self.assertTrue((ROOT / rel).exists(), f"Makefile references missing script: {rel}")

    def test_gitignore_protects_state_and_secrets(self) -> None:
        text = (ROOT / ".gitignore").read_text(encoding="utf-8")
        for pattern in ("*.tfstate", "*.tfplan", "*.tfvars", ".terraform/", "docs/site/"):
            with self.subTest(pattern=pattern):
                self.assertIn(pattern, text)


class ConfigurationSyntaxTests(unittest.TestCase):
    def test_json_configuration_is_valid(self) -> None:
        for rel in JSON_FILES:
            with self.subTest(path=rel):
                with (ROOT / rel).open(encoding="utf-8") as handle:
                    json.load(handle)

    def test_itsm_xml_is_well_formed(self) -> None:
        ET.parse(ROOT / "itsm_templates/remedy-import.xml")

    def test_jira_csv_is_well_formed(self) -> None:
        for rel in ("data/JIRA_IMPORT.csv", "data/JIRA_IMPORT_UPDATED.csv"):
            with self.subTest(path=rel):
                with (ROOT / rel).open(newline="", encoding="utf-8") as handle:
                    rows = list(csv.reader(handle))
                self.assertGreaterEqual(len(rows), 2, f"{rel} has no data rows")
                width = len(rows[0])
                self.assertTrue(all(len(row) == width for row in rows), f"ragged CSV: {rel}")

    def test_shell_scripts_parse(self) -> None:
        for rel in SHELL_SCRIPTS:
            with self.subTest(path=rel):
                result = run(["bash", "-n", rel])
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_terraform_templates_parse(self) -> None:
        result = run(["bash", "-n", "terraform/modules/compute/aws/templates/ecs-userdata.sh"])
        self.assertEqual(result.returncode, 0, result.stderr)


class AutomationContractTests(unittest.TestCase):
    def test_help_paths_exit_zero(self) -> None:
        scripts = [
            "automation/deployment/infrastructure/deploy.sh",
            "automation/security/scanning/run-scans.sh",
            "automation/security/scanning/run-audit.sh",
            "automation/compliance/audit/run-compliance.sh",
            "automation/maintenance/backup/backup.sh",
            "automation/maintenance/cleanup/cleanup.sh",
            "monitoring/init-monitoring.sh",
            "monitoring/update-monitoring.sh",
        ]
        for rel in scripts:
            with self.subTest(path=rel):
                result = run([rel, "--help"])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Usage:", result.stdout)

    def test_dry_run_paths_exit_zero_without_credentials(self) -> None:
        commands = [
            ["automation/deployment/infrastructure/deploy.sh", "--dry-run"],
            ["automation/security/scanning/run-scans.sh", "--dry-run"],
            ["automation/security/scanning/run-audit.sh", "--dry-run"],
            ["automation/maintenance/backup/backup.sh", "--dry-run"],
        ]
        for command in commands:
            with self.subTest(command=" ".join(command)):
                result = run(command)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                self.assertIn("[DRY RUN]", result.stdout)

    def test_deploy_rejects_missing_environment(self) -> None:
        result = run(
            [
                "automation/deployment/infrastructure/deploy.sh",
                "--environment",
                "development",
                "--region",
                "northeast",
                "--dry-run",
            ]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No Terraform environment", result.stdout + result.stderr)


class SecretAndStateHygieneTests(unittest.TestCase):
    def test_no_state_or_plan_artifacts_are_tracked(self) -> None:
        result = run(["git", "ls-files"])
        if result.returncode != 0:
            self.skipTest("git is unavailable")
        tracked = result.stdout.splitlines()
        deleted = set(run(["git", "ls-files", "--deleted"]).stdout.splitlines())
        forbidden = [
            path
            for path in tracked
            if path not in deleted
            and (
                path.endswith((".tfstate", ".tfstate.backup", ".tfplan", "tfplan"))
                or path.endswith(".tfvars")
            )
        ]
        self.assertEqual(forbidden, [], f"state/secret-bearing files are tracked: {forbidden}")

    def test_no_high_confidence_secret_patterns(self) -> None:
        pattern = re.compile(
            r"AKIA[0-9A-Z]{16}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|"
            r"ghp_[A-Za-z0-9]{36}|REPLACE_WITH_" r"SECURE_PASSWORD"
        )
        excluded_parts = {".git", ".terraform", "node_modules", "site", "security-reports", "compliance-reports"}
        allowed_examples = {"AKIA" "IOSFODNN7EXAMPLE"}
        findings: list[str] = []
        for path in ROOT.rglob("*"):
            if not path.is_file() or any(part in excluded_parts for part in path.parts):
                continue
            if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".zip", ".gz", ".woff", ".woff2"}:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for match in pattern.finditer(text):
                if match.group(0) in allowed_examples:
                    continue
                findings.append(f"{path.relative_to(ROOT)}: {match.group(0)[:24]}")
        self.assertEqual(findings, [], "secret-like values found:\n" + "\n".join(findings))


class TerraformContractTests(unittest.TestCase):
    def test_production_root_has_explicit_providers(self) -> None:
        providers = (ROOT / "terraform/environments/production/southeast/providers.tf").read_text(encoding="utf-8")
        for provider in ('provider "aws"', 'provider "azurerm"', 'provider "google"'):
            with self.subTest(provider=provider):
                self.assertIn(provider, providers)
        self.assertIn('source  = "hashicorp/tls"', providers)
        self.assertIn("usgovernment", providers)

    def test_production_tfvars_example_contains_no_secrets(self) -> None:
        text = (
            ROOT / "terraform/environments/production/southeast/terraform.tfvars.example"
        ).read_text(encoding="utf-8")
        self.assertNotIn("REPLACE_WITH", text)
        self.assertNotIn("password =", text.lower())

    def test_provider_reference_configs_are_present(self) -> None:
        for rel in (
            "terraform/providers/aws/govcloud.tf",
            "terraform/providers/azure/government.tf",
            "terraform/providers/gcp/main.tf",
        ):
            with self.subTest(path=rel):
                self.assertTrue((ROOT / rel).is_file())


class VerificationEvidenceTests(unittest.TestCase):
    def test_verification_report_links_resolve(self) -> None:
        report = ROOT / "docs/evidence/verification-report.md"
        text = report.read_text(encoding="utf-8")
        for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = target.split("#", 1)[0]
            with self.subTest(target=target):
                self.assertTrue(
                    (report.parent / target).resolve().exists(),
                    f"broken verification-report link: {target}",
                )

    def test_verification_report_required_sections(self) -> None:
        text = (ROOT / "docs/evidence/verification-report.md").read_text(encoding="utf-8")
        for heading in (
            "## 1. Executive summary",
            "## 2. Scope and methodology",
            "## 4. Fixes implemented",
            "## 5. Verification results",
            "## 8. Remaining issues and limitations",
            "## 10. Quality-gate accounting",
        ):
            with self.subTest(heading=heading):
                self.assertIn(heading, text)

    def test_verification_snapshot_is_valid(self) -> None:
        snapshot = ROOT / "docs/evidence/verification.json"
        data = json.loads(snapshot.read_text(encoding="utf-8"))
        self.assertIn(data["status"], {"PASS", "FAIL"})
        self.assertGreaterEqual(data["counts"]["documents"], 60)
        self.assertGreaterEqual(data["counts"]["screenshots"], 5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
