#!/usr/bin/env python3
"""Browser E2E checks and screenshot capture for the AEGIS documentation portal.

The repository has no operational web application. The generated static portal
is the only browser-rendered surface; these tests verify its navigation, search,
responsive layout, link integrity, console cleanliness, and evidence rendering.

Usage:
  python3 tests/e2e/test_docs_portal.py
  python3 tests/e2e/test_docs_portal.py --screenshots-only
"""

from __future__ import annotations

import functools
import http.server
import socket
import sys
import threading
import urllib.parse
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "docs" / "site"
SHOTS = ROOT / "docs" / "evidence" / "screenshots"
SCREENSHOTS_ONLY = "--screenshots-only" in sys.argv


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args) -> None:  # noqa: D401 - silence test server
        return


class QuietServer(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address) -> None:
        import sys as _sys

        error = _sys.exc_info()[1]
        if isinstance(error, (BrokenPipeError, ConnectionResetError)):
            return
        super().handle_error(request, client_address)


def start_server() -> tuple[http.server.ThreadingHTTPServer, str]:
    handler = functools.partial(QuietHandler, directory=str(ROOT))
    server = QuietServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    return server, f"http://127.0.0.1:{port}"


def assert_http_ok(url: str) -> None:
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            if response.status >= 400:
                raise AssertionError(f"{url} returned HTTP {response.status}")
    except Exception as exc:  # noqa: BLE001 - report exact failing URL
        raise AssertionError(f"broken internal link {url}: {exc}") from exc


def main() -> int:
    if not (SITE / "index.html").is_file():
        print("ERROR: docs/site/index.html is missing. Run 'make docs' first.")
        return 1
    SHOTS.mkdir(parents=True, exist_ok=True)
    server, base = start_server()
    console_errors: list[str] = []
    failed_requests: list[str] = []

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 1440, "height": 1000})
            page.on(
                "console",
                lambda message: console_errors.append(message.text)
                if message.type == "error" and "favicon" not in message.text.lower()
                else None,
            )
            page.on(
                "response",
                lambda response: failed_requests.append(f"{response.status} {response.url}")
                if response.status >= 400 and "favicon" not in response.url
                else None,
            )

            index_url = f"{base}/docs/site/index.html"
            page.goto(index_url, wait_until="networkidle")
            if "AEGIS Documentation Portal" not in page.title():
                raise AssertionError(f"unexpected portal title: {page.title()}")

            cards = page.locator(".card").count()
            if cards < 20:
                raise AssertionError(f"expected at least 20 documentation cards, found {cards}")

            verification_text = page.locator("#verification").inner_text()
            if "Verification snapshot" not in verification_text:
                raise AssertionError("verification section is missing")

            if not SCREENSHOTS_ONLY:
                # Internal link integrity across the portal index.
                hrefs = page.locator("a[href]").evaluate_all(
                    "els => els.map(el => el.getAttribute('href'))"
                )
                checked = 0
                for href in hrefs:
                    if not href or href.startswith(("http://", "https://", "#", "mailto:")):
                        continue
                    absolute = urllib.parse.urljoin(index_url, href)
                    assert_http_ok(absolute)
                    checked += 1
                if checked < 20:
                    raise AssertionError(f"expected to check at least 20 links, checked {checked}")

                # Search filters cards and exposes the empty state.
                page.locator("#all-docs").scroll_into_view_if_needed()
                page.locator("#doc-filter").fill("FedRAMP")
                page.wait_for_timeout(250)
                visible = page.locator(".card:visible").count()
                if visible == 0:
                    raise AssertionError("search for FedRAMP returned no cards")
                page.locator("#all-docs").screenshot(path=str(SHOTS / "feature-verification.png"))

                page.locator("#doc-filter").fill("zzzz-no-such-document")
                page.wait_for_timeout(150)
                if not page.locator("#empty").is_visible():
                    raise AssertionError("empty-state message did not appear")
                page.locator("#doc-filter").fill("")
                page.wait_for_timeout(100)

                # Navigate to a rendered document and a source security reference.
                page.goto(f"{base}/docs/site/pages/README.html", wait_until="networkidle")
                if page.locator("article h1").count() == 0:
                    raise AssertionError("README page has no rendered heading")
                page.screenshot(path=str(SHOTS / "readme-page.png"), full_page=False)

                page.goto(
                    f"{base}/security-reference/aws-security-reference.html",
                    wait_until="networkidle",
                )
                if "AWS Security" not in page.title():
                    raise AssertionError(f"unexpected AWS reference title: {page.title()}")
                page.screenshot(path=str(SHOTS / "security-reference-aws.png"), full_page=False)

                # Desktop homepage and verification evidence.
                page.goto(index_url, wait_until="networkidle")
                page.evaluate("window.scrollTo(0, 0)")
                page.screenshot(path=str(SHOTS / "homepage-desktop.png"), full_page=False)
                page.locator("#verification").screenshot(
                    path=str(SHOTS / "verification-snapshot.png")
                )

                for cloud in ("azure", "gcp"):
                    page.goto(
                        f"{base}/security-reference/{cloud}-security-reference.html",
                        wait_until="networkidle",
                    )
                    page.screenshot(
                        path=str(SHOTS / f"security-reference-{cloud}.png"),
                        full_page=False,
                    )

            else:
                page.evaluate("window.scrollTo(0, 0)")
                page.screenshot(path=str(SHOTS / "homepage-desktop.png"), full_page=False)
                page.locator("#verification").screenshot(
                    path=str(SHOTS / "verification-snapshot.png")
                )

            # Mobile viewport and overflow check.
            mobile = browser.new_page(viewport={"width": 390, "height": 844})
            mobile.goto(index_url, wait_until="networkidle")
            overflow = mobile.evaluate(
                "() => document.documentElement.scrollWidth - window.innerWidth"
            )
            if overflow > 2:
                raise AssertionError(f"mobile layout overflows horizontally by {overflow}px")
            mobile.evaluate("window.scrollTo(0, 0)")
            mobile.screenshot(path=str(SHOTS / "homepage-mobile.png"), full_page=False)
            mobile.close()

            browser.close()
    finally:
        server.shutdown()
        server.server_close()

    if failed_requests:
        raise AssertionError("failed network requests:\n" + "\n".join(failed_requests))
    if console_errors:
        raise AssertionError("browser console errors:\n" + "\n".join(console_errors))

    print("PASS: documentation portal E2E")
    print(f"Screenshots: {SHOTS.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
