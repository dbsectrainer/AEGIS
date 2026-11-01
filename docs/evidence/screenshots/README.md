# Screenshot Evidence

Captured with Playwright/Chromium from the locally served documentation portal
and the repository's static security reference pages. These are genuine browser
captures, not mockups.

| File | Feature demonstrated |
| --- | --- |
| `homepage-desktop.png` | Portal hero, navigation, document count, verification status |
| `homepage-mobile.png` | Responsive 390×844 layout with no horizontal overflow |
| `feature-verification.png` | `FedRAMP` search filter applied; matching documents rendered |
| `verification-snapshot.png` | Verification JSON rendered as PASS with counts and checks |
| `readme-page.png` | Project README rendered inside the portal |
| `security-reference-aws.png` | AWS static security reference page |
| `security-reference-azure.png` | Azure static security reference page |
| `security-reference-gcp.png` | GCP static security reference page |

Limitations: screenshots demonstrate documentation UI behavior only. They are not
proof of live AWS/Azure/GCP infrastructure or backend functionality.

Regenerate with:

```bash
make docs
python3 tests/e2e/test_docs_portal.py
```
