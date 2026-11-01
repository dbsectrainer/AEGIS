#!/usr/bin/env bash
#
# Build the static AEGIS documentation portal.
# Requires Python 3 and the Markdown package (see docs/requirements.txt).
# Generated output goes to docs/site/ and is intentionally not committed.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to build the documentation portal." >&2
    exit 1
fi

if ! python3 -c 'import markdown' >/dev/null 2>&1; then
    echo "ERROR: the Python Markdown package is required." >&2
    echo "Install it with: python3 -m pip install -r docs/requirements.txt" >&2
    exit 1
fi

exec python3 - "$REPO_ROOT" <<'PY'
from __future__ import annotations

import html
import json
import posixpath
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

import markdown

repo = Path(sys.argv[1])
docs_root = repo / "docs"
site = docs_root / "site"
pages = site / "pages"

if site.exists():
    shutil.rmtree(site)
pages.mkdir(parents=True)

CATEGORY_ORDER = [
    ("Executive", "Strategy, governance, and portfolio context"),
    ("Architecture", "System, network, identity, and Zero Trust design"),
    ("IAM", "Identity governance, roles, and access transition"),
    ("Compliance", "RMF, FedRAMP, control mapping, and reporting"),
    ("Operations", "Deployment, DevSecOps, CSPM, and eMaaS"),
    ("Security", "Policies, implementation, metrics, and supply chain"),
    ("Templates", "SSP, POAM, SAR, RAR, SCIP, and assessment artifacts"),
    ("ITSM", "ServiceNow, Jira, and Remedy workflow material"),
    ("RACI", "Federal enterprise cloud responsibility matrices"),
    ("Security references", "AWS, Azure, and GCP implementation guides"),
    ("Infrastructure", "Terraform module documentation"),
    ("Project", "Repository-level documentation"),
]

CATEGORY_BY_PREFIX = [
    ("docs/executive/", "Executive"),
    ("docs/architecture/", "Architecture"),
    ("docs/iam/", "IAM"),
    ("docs/compliance/", "Compliance"),
    ("docs/operations/", "Operations"),
    ("docs/security/", "Security"),
    ("templates/", "Templates"),
    ("itsm_templates/", "ITSM"),
    ("raci/", "RACI"),
    ("security-reference/", "Security references"),
    ("terraform/", "Infrastructure"),
]


def category_for(rel: str) -> str:
    for prefix, category in CATEGORY_BY_PREFIX:
        if rel.startswith(prefix):
            return category
    return "Project"


def slug_for(rel: str) -> str:
    slug = rel.removesuffix(".md").replace("/", "-")
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", slug).strip("-")
    return slug or "page"


def first_heading(text: str) -> str:
    match = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else "Untitled document"


def summary_for(text: str) -> str:
    body = re.sub(r"^#.*$", "", text, count=1, flags=re.MULTILINE)
    for block in re.split(r"\n\s*\n", body):
        clean = " ".join(
            line.strip()
            for line in block.splitlines()
            if line.strip()
            and not line.lstrip().startswith(
                ("#", "|", "```", "-", "*", ">", "![", "[![", "<a ", "<img", "│", "├", "└")
            )
        )
        clean = re.sub(r"!\[[^\]]*\]\([^)]+\)", "", clean)
        clean = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", clean)
        clean = re.sub(r"<[^>]+>", "", clean)
        clean = re.sub(r"[`*_]", "", clean).strip()
        if len(clean) > 40:
            return clean[:180].rsplit(" ", 1)[0] + "…"
    return "No summary available."


def word_count(text: str) -> int:
    return len(re.findall(r"\b\w+\b", text))


def render(md_text: str) -> str:
    return markdown.markdown(
        md_text,
        extensions=["fenced_code", "tables", "toc", "sane_lists", "attr_list"],
        output_format="html5",
    )


records = []

# Repository README
readme = repo / "README.md"
if readme.exists():
    text = readme.read_text(encoding="utf-8")
    records.append(
        {
            "rel": "README.md",
            "title": first_heading(text),
            "summary": summary_for(text),
            "category": "Project",
            "words": word_count(text),
            "text": text,
            "slug": "README",
        }
    )

# Documentation markdown, excluding generated and evidence material
for path in sorted(docs_root.rglob("*.md")):
    rel = path.relative_to(repo).as_posix()
    if rel.startswith("docs/site/") or rel.startswith("docs/evidence/"):
        continue
    text = path.read_text(encoding="utf-8")
    records.append(
        {
            "rel": rel,
            "title": first_heading(text),
            "summary": summary_for(text),
            "category": category_for(rel),
            "words": word_count(text),
            "text": text,
            "slug": slug_for(rel),
        }
    )

# Templates, ITSM, RACI, security references, and Terraform module docs
for prefix in ("templates", "itsm_templates", "raci", "security-reference", "terraform"):
    for path in sorted((repo / prefix).rglob("*.md")):
        rel = path.relative_to(repo).as_posix()
        if any(r["rel"] == rel for r in records):
            continue
        text = path.read_text(encoding="utf-8")
        records.append(
            {
                "rel": rel,
                "title": first_heading(text),
                "summary": summary_for(text),
                "category": category_for(rel),
                "words": word_count(text),
                "text": text,
                "slug": slug_for(rel),
            }
        )

# Verification report and snapshot
verification_report = docs_root / "evidence" / "verification-report.md"
verification_status = "NOT RUN"
verification_checks = []
verification_counts = {}
verification_snapshot = docs_root / "evidence" / "verification.json"
if verification_snapshot.exists():
    try:
        snapshot = json.loads(verification_snapshot.read_text(encoding="utf-8"))
        verification_status = snapshot.get("status", "UNKNOWN")
        verification_checks = snapshot.get("checks", [])
        verification_counts = snapshot.get("counts", {})
    except (json.JSONDecodeError, OSError):
        verification_status = "UNREADABLE"

if verification_report.exists():
    text = verification_report.read_text(encoding="utf-8")
    records.append(
        {
            "rel": "docs/evidence/verification-report.md",
            "title": first_heading(text),
            "summary": summary_for(text),
            "category": "Project",
            "words": word_count(text),
            "text": text,
            "slug": "verification-report",
        }
    )

slug_by_path = {record["rel"]: record["slug"] for record in records}


def rewrite_links(rendered: str, source_rel: str) -> str:
    source_dir = posixpath.dirname(source_rel)
    pattern = re.compile(r'(?P<attr>href|src)=(?P<quote>["\'])(?P<target>[^"\']+)(?P=quote)')

    def replace(match: re.Match[str]) -> str:
        target = match.group("target")
        if target.startswith(("http://", "https://", "/", "#", "mailto:", "data:", "javascript:")):
            return match.group(0)
        base, _, fragment = target.partition("#")
        if not base:
            return match.group(0)
        resolved = posixpath.normpath(posixpath.join(source_dir, base))
        if resolved in slug_by_path:
            new_target = f"{slug_by_path[resolved]}.html"
        else:
            new_target = posixpath.relpath(resolved, "docs/site/pages")
        if fragment:
            new_target = f"{new_target}#{fragment}"
        return f'{match.group("attr")}={match.group("quote")}{new_target}{match.group("quote")}'

    return pattern.sub(replace, rendered)


for record in records:
    record["html"] = rewrite_links(render(record["text"]), record["rel"])

by_category: dict[str, list[dict]] = {}
for record in records:
    by_category.setdefault(record["category"], []).append(record)

for record in records:
    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(record['title'])} · AEGIS Documentation</title>
<link rel="stylesheet" href="../assets/style.css">
</head>
<body class="doc-page">
<header class="topbar">
  <a class="brand" href="../index.html">AEGIS<span>docs</span></a>
  <nav><a href="../index.html">All documentation</a><a href="../index.html#verification">Verification</a></nav>
</header>
<main class="prose">
  <p class="breadcrumb">{html.escape(record['category'])} / <code>{html.escape(record['rel'])}</code></p>
  <article>{record['html']}</article>
  <footer class="doc-footer">Generated from the repository source. Source of truth: <code>{html.escape(record['rel'])}</code>.</footer>
</main>
</body>
</html>
"""
    (pages / f"{record['slug']}.html").write_text(page, encoding="utf-8")

# Screenshot gallery
screenshots_dir = docs_root / "evidence" / "screenshots"
screenshots = sorted(p for p in screenshots_dir.glob("*.png")) if screenshots_dir.exists() else []
gallery = "\n".join(
    f'<figure><a href="../evidence/screenshots/{html.escape(p.name)}"><img src="../evidence/screenshots/{html.escape(p.name)}" alt="{html.escape(p.stem.replace("-", " "))}" loading="lazy"></a>'
    f'<figcaption>{html.escape(p.stem.replace("-", " "))}</figcaption></figure>'
    for p in screenshots
)

cards_by_category = ""
for category, description in CATEGORY_ORDER:
    items = by_category.get(category, [])
    if not items:
        continue
    cards = "\n".join(
        f'<a class="card" href="pages/{html.escape(item["slug"])}.html" data-search="{html.escape((item["title"] + " " + item["summary"] + " " + item["rel"]).lower())}">'
        f'<span class="tag">{html.escape(category)}</span>'
        f'<h3>{html.escape(item["title"])}</h3>'
        f'<p>{html.escape(item["summary"])}</p>'
        f'<span class="meta">{item["words"]:,} words · {html.escape(item["rel"])}</span></a>'
        for item in items
    )
    cards_by_category += f"""
<section class="category" id="{html.escape(category.lower().replace(' ', '-'))}">
  <div class="section-head"><h2>{html.escape(category)}</h2><p>{html.escape(description)}</p></div>
  <div class="card-grid">{cards}</div>
</section>
"""

verification_checks_html = "\n".join(
    f'<li><span class="status {html.escape(str(c.get("status", "UNKNOWN")).lower())}">{html.escape(str(c.get("status", "UNKNOWN")))}</span>'
    f'<strong>{html.escape(str(c.get("name", "check")))}</strong>'
    f'<span>{html.escape(str(c.get("detail", "")))}</span></li>'
    for c in verification_checks
)
if not verification_checks_html:
    verification_checks_html = "<li><span class=\"status not-run\">NOT RUN</span><strong>No verification snapshot found.</strong><span>Run <code>tests/run-tests.sh</code> and regenerate the portal.</span></li>"

counts_html = "\n".join(
    f'<div class="stat"><strong>{html.escape(str(value))}</strong><span>{html.escape(str(key).replace("_", " "))}</span></div>'
    for key, value in verification_counts.items()
)
if not counts_html:
    counts_html = '<div class="stat"><strong>—</strong><span>verification counts</span></div>'

if verification_report.exists():
    verification_report_button = '<a class="button" href="pages/verification-report.html">Full verification report</a>'
else:
    verification_report_button = '<span class="button">Verification report pending</span>'

security_links = "\n".join(
    f'<a class="pill" href="../../security-reference/{html.escape(p.name)}">{html.escape(p.stem.replace("-", " ").title())}</a>'
    for p in sorted((repo / "security-reference").glob("*.html"))
)

index = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AEGIS Documentation Portal</title>
<meta name="description" content="AEGIS federal multi-cloud security governance, compliance, and infrastructure documentation.">
<link rel="stylesheet" href="assets/style.css">
</head>
<body>
<header class="hero">
  <div class="hero-inner">
    <p class="eyebrow">Advanced Enterprise Governance &amp; Infrastructure Security</p>
    <h1>AEGIS <span>Documentation Portal</span></h1>
    <p class="lede">FedRAMP High, NIST 800-53 Rev 5, DoD Cloud SRG, and NIST 800-207 Zero Trust guidance, templates, and Terraform modules — generated from repository source.</p>
    <div class="hero-actions">
      <a class="button primary" href="pages/README.html">Read the project README</a>
      <a class="button" href="#verification">Verification evidence</a>
      <a class="button" href="#all-docs">Browse all documents</a>
    </div>
    <div class="hero-stats">
      <div class="stat"><strong>{len(records)}</strong><span>documents</span></div>
      <div class="stat"><strong>3</strong><span>cloud providers</span></div>
      <div class="stat"><strong>{sum(1 for r in records if r['category'] == 'Templates')}</strong><span>authorization templates</span></div>
      <div class="stat"><strong class="status {html.escape(verification_status.lower())}">{html.escape(verification_status)}</strong><span>repository verification</span></div>
    </div>
  </div>
</header>

<main>
  <section class="panel" id="verification">
    <div class="section-head">
      <h2>Verification snapshot</h2>
      <p>Reproducible checks recorded in <code>docs/evidence/verification.json</code>. These validate repository artifacts, Terraform configuration, shell scripts, and the documentation portal. They do not prove live cloud control effectiveness.</p>
    </div>
    <div class="stats-row">{counts_html}</div>
    <ul class="checks">{verification_checks_html}</ul>
    <div class="hero-actions">
      {verification_report_button}
      <a class="button" href="#evidence">Screenshots</a>
      <span class="pills">{security_links}</span>
    </div>
  </section>

  <section class="panel" id="all-docs">
    <div class="section-head">
      <h2>All documentation</h2>
      <p>Filter by title, summary, or path. Content is rendered from the repository's Markdown at build time.</p>
    </div>
    <label class="search"><span>Filter</span><input id="doc-filter" type="search" placeholder="e.g. FedRAMP, Zero Trust, IAM, Terraform" autocomplete="off"></label>
    <p class="empty" id="empty" hidden>No documents match that filter.</p>
    {cards_by_category}
  </section>

  <section class="panel" id="evidence">
    <div class="section-head">
      <h2>Execution evidence</h2>
      <p>Genuine screenshots captured from this documentation portal and the repository's security reference pages using browser automation.</p>
    </div>
    <div class="gallery">{gallery if gallery else '<p class="empty">No screenshots captured yet. Run <code>make test-e2e</code>.</p>'}</div>
  </section>
</main>

<footer class="site-footer">
  <p><strong>AEGIS</strong> · BE EASY ENTERPRISES · Documentation generated {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}</p>
  <p>Source documents remain authoritative. Generated portal: <code>docs/site/</code>.</p>
</footer>
<script>
const input = document.getElementById('doc-filter');
const cards = Array.from(document.querySelectorAll('.card'));
const empty = document.getElementById('empty');
function applyFilter() {{
  const q = input.value.trim().toLowerCase();
  let visible = 0;
  for (const card of cards) {{
    const match = !q || card.dataset.search.includes(q);
    card.hidden = !match;
    if (match) visible++;
  }}
  empty.hidden = visible !== 0;
  for (const section of document.querySelectorAll('.category')) {{
    const any = Array.from(section.querySelectorAll('.card')).some(c => !c.hidden);
    section.hidden = !any;
  }}
}}
if (input) {{ input.addEventListener('input', applyFilter); }}
</script>
</body>
</html>
"""
(site / "index.html").write_text(index, encoding="utf-8")

assets = site / "assets"
assets.mkdir()
(assets / "style.css").write_text(
    """/* AEGIS documentation portal */
:root{--ink:#0d1b2a;--navy:#102a43;--blue:#1f6feb;--cyan:#39c6c0;--paper:#f5f7fa;--line:#d9e2ec;--muted:#52667a;--good:#1a7f4b;--bad:#b42318;--warn:#8a5a00}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--ink);background:var(--paper);line-height:1.6}
a{color:var(--blue);text-decoration:none}
a:hover{text-decoration:underline}
.hero{background:linear-gradient(135deg,#0b1f33 0%,#12395c 60%,#155e75 100%);color:#fff;padding:4rem 1.25rem 3rem}
.hero-inner{max-width:1100px;margin:0 auto}
.eyebrow{text-transform:uppercase;letter-spacing:.16em;font-size:.72rem;color:#9fd8f5;margin:0 0 1rem}
.hero h1{font-size:clamp(2.2rem,5vw,3.6rem);margin:0;line-height:1.1}
.hero h1 span{display:block;font-weight:400;color:#bfe3f5;font-size:.52em;letter-spacing:.02em;margin-top:.5rem}
.lede{max-width:760px;color:#dbeafe;font-size:1.05rem}
.hero-actions{display:flex;flex-wrap:wrap;gap:.75rem;align-items:center;margin-top:1.5rem}
.button{display:inline-block;border:1px solid rgba(255,255,255,.35);color:#fff;padding:.6rem 1rem;border-radius:999px;font-size:.9rem;background:rgba(255,255,255,.06)}
.button.primary{background:#fff;color:var(--navy);border-color:#fff;font-weight:600}
.button:hover{text-decoration:none;transform:translateY(-1px)}
.hero-stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:.75rem;margin-top:2.5rem;max-width:900px}
.hero-stats .stat{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.16);border-radius:12px;padding:.8rem 1rem;display:flex;flex-direction:column}
.hero-stats .stat strong{font-size:1.35rem;color:#fff}
.hero-stats .stat span{font-size:.75rem;color:#c7e3f4;text-transform:uppercase;letter-spacing:.08em}
main{max-width:1180px;margin:0 auto;padding:2rem 1.25rem 3rem}
.panel{background:#fff;border:1px solid var(--line);border-radius:16px;padding:1.75rem;margin:1.25rem 0;box-shadow:0 8px 24px rgba(16,42,67,.05)}
.section-head h2{margin:.1rem 0 .25rem;font-size:1.5rem}
.section-head p{margin:0 0 1.1rem;color:var(--muted)}
.stats-row{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:.75rem;margin-bottom:1rem}
.stats-row .stat{border:1px solid var(--line);border-radius:10px;padding:.7rem .9rem;display:flex;flex-direction:column;background:#fbfdff}
.stats-row .stat strong{font-size:1.25rem}
.stats-row .stat span{font-size:.72rem;color:var(--muted);text-transform:uppercase;letter-spacing:.06em}
.checks{list-style:none;padding:0;margin:0 0 1rem;display:grid;gap:.45rem}
.checks li{display:grid;grid-template-columns:78px 1fr;gap:.6rem;align-items:start;border-bottom:1px dashed var(--line);padding:.45rem 0;font-size:.9rem}
.checks li span:last-child{grid-column:2;color:var(--muted);font-size:.82rem}
.status{display:inline-block;font-size:.68rem;font-weight:700;letter-spacing:.05em;padding:.15rem .45rem;border-radius:5px;text-align:center}
.status.pass{background:#e6f6ec;color:var(--good)}
.status.fail{background:#fdecea;color:var(--bad)}
.status.partial,.status.not-run{background:#fff4dc;color:var(--warn)}
.status.unknown,.status.unreadable,.status.advisory{background:#eef1f5;color:var(--muted)}
.hero-stats .status.pass{color:#7ee2a8;background:rgba(26,127,75,.25)}
.hero-stats .status.fail{color:#ffb4ab;background:rgba(180,35,24,.25)}
.hero-stats .status.partial,.hero-stats .status.not-run{color:#ffd58a;background:rgba(138,90,0,.25)}
.pills{display:inline-flex;gap:.4rem;flex-wrap:wrap;margin-left:.5rem}
.pill{background:#eef5ff;color:var(--navy);border:1px solid #cfe1ff;border-radius:999px;padding:.3rem .65rem;font-size:.78rem}
.search{display:flex;align-items:center;gap:.75rem;margin:0 0 1.5rem;font-size:.8rem;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}
.search input{flex:1;padding:.7rem .9rem;border:1px solid var(--line);border-radius:10px;font:inherit;text-transform:none;letter-spacing:0;font-weight:400;color:var(--ink);background:#fbfdff}
.category{margin:1.75rem 0}
.category h2{font-size:1.15rem;margin:0 0 .15rem}
.category .section-head p{font-size:.86rem;margin-bottom:.8rem}
.card-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:.8rem}
.card{display:flex;flex-direction:column;border:1px solid var(--line);border-radius:12px;padding:1rem;background:#fff;color:var(--ink);transition:border-color .15s,transform .15s,box-shadow .15s}
.card:hover{text-decoration:none;border-color:#9cc3ff;transform:translateY(-2px);box-shadow:0 8px 18px rgba(31,111,235,.12)}
.card .tag{font-size:.65rem;text-transform:uppercase;letter-spacing:.08em;color:var(--blue);font-weight:700}
.card h3{font-size:1rem;margin:.35rem 0 .4rem;line-height:1.35}
.card p{font-size:.83rem;color:var(--muted);margin:0 0 .7rem;flex:1}
.card .meta{font-size:.7rem;color:#7b8ca0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;word-break:break-all}
.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:1rem}
.gallery figure{margin:0;border:1px solid var(--line);border-radius:12px;overflow:hidden;background:#f8fafc}
.gallery img{display:block;width:100%;height:auto}
.gallery figcaption{padding:.55rem .75rem;font-size:.78rem;color:var(--muted);text-transform:capitalize}
.empty{color:var(--muted);font-style:italic}
.site-footer{max-width:1180px;margin:0 auto;padding:1rem 1.25rem 3rem;color:var(--muted);font-size:.8rem}
.doc-page{background:#fff}
.topbar{display:flex;justify-content:space-between;align-items:center;gap:1rem;padding:.8rem 1.25rem;background:var(--navy);color:#fff}
.brand{color:#fff;font-weight:800;letter-spacing:.04em}
.brand span{font-weight:400;color:#9fd8f5;margin-left:.3rem}
.topbar nav{display:flex;gap:1rem;font-size:.82rem}
.topbar a{color:#dbeafe}
.prose{max-width:900px;margin:0 auto;padding:2rem 1.25rem 3rem}
.prose article h1{font-size:2rem;margin-top:0}
.prose article h2{margin-top:2rem;border-bottom:1px solid var(--line);padding-bottom:.25rem}
.prose table{border-collapse:collapse;width:100%;font-size:.88rem;display:block;overflow-x:auto}
.prose th,.prose td{border:1px solid var(--line);padding:.45rem .6rem;text-align:left;vertical-align:top}
.prose th{background:#f0f4f8}
.prose pre{background:#0d1b2a;color:#e6f1ff;padding:1rem;border-radius:10px;overflow-x:auto;font-size:.82rem}
.prose code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.88em}
.prose :not(pre)>code{background:#eef2f7;padding:.1rem .3rem;border-radius:4px}
.prose blockquote{border-left:4px solid var(--cyan);margin:1rem 0;padding:.25rem 1rem;color:var(--muted);background:#f7fbfd}
.prose img{max-width:100%}
.breadcrumb{font-size:.78rem;color:var(--muted);text-transform:uppercase;letter-spacing:.05em}
.doc-footer{margin-top:2.5rem;border-top:1px solid var(--line);padding-top:1rem;color:var(--muted);font-size:.8rem}
@media (max-width:640px){.hero{padding:2.5rem 1rem 2rem}.panel{padding:1.1rem}.topbar{flex-direction:column;align-items:flex-start}.checks li{grid-template-columns:68px 1fr}.hero-actions{gap:.5rem}.pill{margin-left:0}}
""",
    encoding="utf-8",
)

# A machine-readable index supports repository tests and CI link checking.
manifest = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "documents": [
        {
            "path": r["rel"],
            "title": r["title"],
            "category": r["category"],
            "slug": r["slug"],
            "words": r["words"],
        }
        for r in records
    ],
}
(site / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

print(f"Built {len(records)} documentation pages in {site}")
PY
