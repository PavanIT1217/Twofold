"""Checks the website's SEO basics: titles, descriptions, canonical URLs,
social cards, structured data, links and the sitemap.

Usage: python3 .github/scripts/check_website.py website
"""
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree

SITE = "https://twofold.webappslab.com"
NOT_INDEXED = {"404.html"}


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.meta, self.links, self.ids, self.hrefs, self.imgs = {}, {}, set(), [], []
        self.title, self.h1, self.ld = "", 0, []
        self._in = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag == "meta":
            key = a.get("name") or a.get("property")
            if key:
                self.meta[key] = a.get("content", "")
        elif tag == "link" and "rel" in a:
            self.links.setdefault(a["rel"], a.get("href", ""))
        elif tag == "a" and "href" in a:
            self.hrefs.append(a["href"])
        elif tag == "img":
            self.imgs.append(a)
        elif tag == "h1":
            self.h1 += 1
        elif tag == "title":
            self._in = "title"
        elif tag == "script" and a.get("type") == "application/ld+json":
            self._in = "ld"
            self.ld.append("")

    def handle_endtag(self, tag):
        if tag in ("title", "script"):
            self._in = None

    def handle_data(self, data):
        if self._in == "title":
            self.title += data
        elif self._in == "ld":
            self.ld[-1] += data


def main(root):
    root = Path(root)
    errors = []
    pages = {p.name: p for p in root.glob("*.html")}
    parsed = {}

    for name, path in sorted(pages.items()):
        p = Page()
        p.feed(path.read_text())
        parsed[name] = p
        err = lambda msg: errors.append(f"{name}: {msg}")

        if not 10 <= len(p.title.strip()) <= 65:
            err(f"title should be 10-65 characters, is {len(p.title.strip())}")
        if p.h1 != 1:
            err(f"expected exactly one <h1>, found {p.h1}")
        for img in p.imgs:
            if "alt" not in img:
                err(f"<img src={img.get('src')}> has no alt attribute")

        if name in NOT_INDEXED:
            if "noindex" not in p.meta.get("robots", ""):
                err("should be noindex")
            continue

        desc = p.meta.get("description", "")
        if not 50 <= len(desc) <= 165:
            err(f"meta description should be 50-165 characters, is {len(desc)}")
        expected = f"{SITE}/" + ("" if name == "index.html" else name)
        if p.links.get("canonical") != expected:
            err(f"canonical should be {expected}, is {p.links.get('canonical')}")
        if p.meta.get("og:url") != expected:
            err("og:url should match the canonical URL")
        for key in ("og:title", "og:description", "og:image", "og:image:alt", "twitter:card"):
            if not p.meta.get(key):
                err(f"missing {key}")
        image = p.meta.get("og:image", "")
        if image.startswith(SITE) and not (root / image[len(SITE) + 1:]).is_file():
            err(f"og:image {image} doesn't exist")
        if not p.ld:
            err("no JSON-LD structured data")
        for block in p.ld:
            try:
                data = json.loads(block)
                if data.get("@context") != "https://schema.org":
                    err("JSON-LD @context should be https://schema.org")
            except json.JSONDecodeError as e:
                err(f"JSON-LD doesn't parse: {e}")

    # Internal links and fragment targets.
    for name, p in parsed.items():
        for href in p.hrefs:
            if re.match(r"^(https?:|mailto:|tel:)", href) or href == "#":
                continue
            target, _, frag = href.partition("#")
            if href.startswith("#"):
                target = name
            elif target in ("./", "/"):
                target = "index.html"
            target = target.lstrip("/")
            if target not in parsed:
                errors.append(f"{name}: link to missing page {href}")
            elif frag and frag not in parsed[target].ids:
                errors.append(f"{name}: link to missing anchor {href}")

    # Sitemap lists exactly the indexable pages.
    ns = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    locs = {e.text for e in ElementTree.parse(root / "sitemap.xml").findall("s:url/s:loc", ns)}
    wanted = {f"{SITE}/" + ("" if n == "index.html" else n) for n in pages if n not in NOT_INDEXED}
    for missing in sorted(wanted - locs):
        errors.append(f"sitemap.xml: missing {missing}")
    for extra in sorted(locs - wanted):
        errors.append(f"sitemap.xml: lists {extra}, which isn't an indexable page")

    if f"Sitemap: {SITE}/sitemap.xml" not in (root / "robots.txt").read_text():
        errors.append("robots.txt: should point to the sitemap")
    json.loads((root / "site.webmanifest").read_text())

    for e in errors:
        print(f"::error::{e}")
    print(f"Checked {len(pages)} pages: {len(errors)} problem(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "website"))
