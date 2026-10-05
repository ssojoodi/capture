#!/usr/bin/env python3
"""Validate public page metadata, structured data, fragments and local assets."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[1] / 'web-page'
BASE = 'https://sojoodi.com/apps/Capture/'
class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.tags = []
        self.source = path.read_text()
        self.feed(self.source)
    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))
    def meta(self, key):
        values = [a['content'] for t, a in self.tags if t == 'meta' and (a.get('name') == key or a.get('property') == key)]
        assert len(values) == 1, key
        return values[0]

titles, descriptions = set(), set()
for path in ROOT.glob('*.html'):
    page = Page(path)
    title = re.search(r'<title>(.*?)</title>', page.source)[1]
    assert title not in titles
    titles.add(title)
    description = page.meta('description')
    assert description not in descriptions
    descriptions.add(description)
    canonical = BASE + ('' if path.name == 'index.html' else path.name)
    assert [a['href'] for t,a in page.tags if t == 'link' and a.get('rel') == 'canonical'] == [canonical]
    assert page.meta('og:url') == canonical
    assert page.meta('og:title') == page.meta('twitter:title') == title
    assert page.meta('og:description') == page.meta('twitter:description') == description
    assert page.meta('twitter:card') == 'summary_large_image'
    image = page.meta('og:image')
    assert image == page.meta('twitter:image') and image.startswith(BASE)
    raw = (ROOT / image.removeprefix(BASE)).read_bytes()
    assert struct.unpack('>II', raw[16:24]) == (1200,630)
    assert (page.meta('og:image:width'),page.meta('og:image:height')) == ('1200','630')
    assert page.meta('og:image:alt') == page.meta('twitter:image:alt')
    assert not re.search(r'noindex|nofollow', page.source, re.I)
    assert sum(t == 'h1' for t,a in page.tags) == 1
    ids = [a['id'] for t,a in page.tags if 'id' in a]
    assert len(ids) == len(set(ids))
    links = [a['href'] for t,a in page.tags if t == 'a']
    assert 'https://sojoodi.com/' in links and 'https://sojoodi.com/apps/' in links
    for t,a in page.tags:
        if t == 'img':
            assert all(key in a for key in ('alt','width','height'))
        urls = [a[key] for key in ('href','src') if key in a]
        urls += [entry.strip().split()[0] for entry in a.get('srcset','').split(',') if entry]
        for url in urls:
            parsed = urlsplit(url)
            if parsed.scheme or parsed.netloc: continue
            target = ROOT / unquote(parsed.path) if parsed.path else path
            assert target.exists(), url
            if parsed.fragment:
                target_page = Page(target) if target.is_file() else page
                assert parsed.fragment in [attrs.get('id') for _,attrs in target_page.tags], url
    data = json.loads(re.search(r'<script type="application/ld\+json">(.*?)</script>',page.source,re.S)[1])
    assert data['url'] == canonical and data['@context'] == 'https://schema.org'
    print('PASS', canonical)
