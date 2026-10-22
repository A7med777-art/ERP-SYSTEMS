#!/usr/bin/env python3
"""Rewrites the Content-Security-Policy <meta> in an HTML file so it allows
exactly the page's own inline <script> blocks (by SHA-256 hash) and nothing else.

Run after editing any <script> in index.html:  python3 scripts/csp.py index.html
The publish workflow also runs it on the published copy, so an edit can never
ship with a stale hash (which would silently stop the page's JavaScript).
"""
import base64, hashlib, re, sys

SUPABASE = "https://vtzzqhbtnqudhtxnbykm.supabase.co"
VIDEO = "https://d8j0ntlcm91z4.cloudfront.net"

def policy(html: str) -> str:
    hashes = []
    for body in re.findall(r"<script>(.*?)</script>", html, flags=re.S):
        digest = base64.b64encode(hashlib.sha256(body.encode()).digest()).decode()
        hashes.append(f"'sha256-{digest}'")
    return "; ".join([
        "default-src 'none'",
        "script-src " + " ".join(hashes),
        "style-src 'unsafe-inline'",
        "img-src data:",
        "font-src data:",
        f"media-src {VIDEO}",
        f"connect-src {SUPABASE}",
        "base-uri 'none'",
        "form-action 'none'",
        "object-src 'none'",
        "upgrade-insecure-requests",
    ])

def main(path: str) -> None:
    html = open(path, encoding="utf-8").read()
    tag = f'<meta http-equiv="Content-Security-Policy" content="{policy(html)}">'
    new, n = re.subn(r'<meta http-equiv="Content-Security-Policy" content="[^"]*">', tag, html)
    if n != 1:
        sys.exit(f"{path}: expected exactly one Content-Security-Policy meta tag, found {n}")
    if new != html:
        open(path, "w", encoding="utf-8").write(new)
        print(f"{path}: CSP updated")
    else:
        print(f"{path}: CSP already current")

if __name__ == "__main__":
    for p in sys.argv[1:] or ["index.html"]:
        main(p)
