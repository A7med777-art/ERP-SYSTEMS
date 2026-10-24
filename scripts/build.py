#!/usr/bin/env python3
"""Builds the single-file site: src/index.html → index.html (or the path given).

Embeds the fonts in src/fonts/ as base64, inlines the Motion library from src/vendor/,
then writes the Content-Security-Policy with the hashes of the page's inline scripts.
Edit src/index.html, then run:  python3 scripts/build.py
"""
import base64, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import csp  # noqa: E402

MOTION = "motion-14.1.0.min.js"

def build(out: pathlib.Path) -> None:
    html = (ROOT / "src/index.html").read_text(encoding="utf-8")

    def font(m):
        return base64.b64encode((ROOT / f"src/fonts/{m.group(1)}.woff2").read_bytes()).decode()
    html = re.sub(r"__FONT_([a-z0-9-]+)__", font, html)

    lib = (ROOT / f"src/vendor/{MOTION}").read_text(encoding="utf-8")
    if "</script" in lib.lower():
        sys.exit("vendor script contains </script>; cannot inline it safely")
    html = html.replace("<!--MOTION-->", f"<script>/*! Motion 14.1.0 | MIT | https://motion.dev */\n{lib}</script>", 1)

    if "__FONT_" in html or "<!--MOTION-->" in html:
        sys.exit("unreplaced placeholder left in the page")
    out.write_text(html, encoding="utf-8")
    csp.main(str(out))
    print(f"built {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out} ({out.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    build(pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "index.html")
