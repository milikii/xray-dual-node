#!/usr/bin/env python3
"""Fetch public AI feeds and atomically publish a static reading site. No model calls."""
import argparse
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
import fcntl
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import random
import re
import secrets
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

THEMES = {
    'ai-news': ('AI Dispatch', 'Updates from the AI ecosystem', ['huggingface', 'mit']),
    'ai-hardware': ('Compute Brief', 'AI hardware and computing infrastructure', ['nvidia', 'sth']),
    'ai-research': ('Paper Signals', 'Recent papers in artificial intelligence', ['arxiv-ai', 'arxiv-lg']),
    'ai-digest': ('Intelligence Ledger', 'AI news, computing and research', ['huggingface', 'mit', 'nvidia', 'sth', 'arxiv-ai', 'arxiv-lg']),
}
SOURCES = {
    'huggingface': {'name': 'Hugging Face', 'url': 'https://huggingface.co/blog/feed.xml', 'hosts': ['huggingface.co'], 'category': 'AI news'},
    'mit': {'name': 'MIT News · AI', 'url': 'https://news.mit.edu/rss/topic/artificial-intelligence2', 'hosts': ['news.mit.edu'], 'category': 'AI news'},
    'nvidia': {'name': 'NVIDIA Blog', 'url': 'https://blogs.nvidia.com/feed/', 'hosts': ['nvidia.com'], 'category': 'AI hardware'},
    'sth': {'name': 'ServeTheHome', 'url': 'https://www.servethehome.com/feed/', 'hosts': ['servethehome.com'], 'category': 'AI hardware'},
    'arxiv-ai': {'name': 'arXiv · cs.AI', 'url': 'https://rss.arxiv.org/rss/cs.AI', 'hosts': ['arxiv.org'], 'category': 'AI research'},
    'arxiv-lg': {'name': 'arXiv · cs.LG', 'url': 'https://rss.arxiv.org/rss/cs.LG', 'hosts': ['arxiv.org'], 'category': 'AI research'},
}
PALETTES = [('#f4f1e9', '#202d2a', '#286450'), ('#f4eee8', '#382c27', '#a04430'),
            ('#edf1f5', '#263647', '#345f92'), ('#f4eff5', '#3c2b40', '#84548c'),
            ('#faf3df', '#3b3321', '#8b641a'), ('#edf3ed', '#293c31', '#4b7049')]
MAX_BYTES = 4 * 1024 * 1024
HARDWARE = re.compile(r'\b(gpu|gpus|accelerator|accelerators|chip|chips|semiconductor|cuda|hbm|blackwell|rubin|instinct|tpu|tpus|npu|npus)\b', re.I)


def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0
    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden += 1
    def handle_endtag(self, tag):
        if tag in ('script', 'style') and self.hidden:
            self.hidden -= 1
    def handle_data(self, value):
        if not self.hidden:
            self.parts.append(value)


def plain(value, limit):
    parser = PlainText()
    parser.feed(value[:20000])
    value = re.sub(r'\s+', ' ', ' '.join(parser.parts)).strip()
    return value if len(value) <= limit else value[:limit].rsplit(' ', 1)[0] + '…'


def approved_url(value, source):
    try:
        parsed = urllib.parse.urlsplit(value)
        host = (parsed.hostname or '').lower()
        if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.port not in (None, 443):
            return None
        if not any(host == allowed or host.endswith('.' + allowed) for allowed in source['hosts']):
            return None
        query = urllib.parse.urlencode([(k, v) for k, v in urllib.parse.parse_qsl(parsed.query)
                                       if not k.lower().startswith('utm_') and k.lower() not in ('fbclid', 'gclid')])
        return urllib.parse.urlunsplit(('https', parsed.netloc.lower(), parsed.path or '/', query, ''))
    except ValueError:
        return None


def date_value(value):
    try:
        date = parsedate_to_datetime(value)
    except (ValueError, TypeError, OverflowError):
        try:
            date = datetime.fromisoformat(value.strip().replace('Z', '+00:00'))
        except (ValueError, TypeError):
            return ''
    if date.tzinfo is None:
        date = date.replace(tzinfo=timezone.utc)
    if date > datetime.now(timezone.utc) + timedelta(days=1):
        return ''
    return date.astimezone(timezone.utc).replace(microsecond=0).isoformat()


def parse_feed(data, source_id):
    if len(data) > MAX_BYTES or re.search(br'<!\s*(?:DOCTYPE|ENTITY)', data, re.I):
        raise ValueError('unsupported XML')
    source = SOURCES[source_id]
    root = ET.fromstring(data)
    if root.tag.rsplit('}', 1)[-1].lower() not in ('rss', 'feed', 'rdf'):
        raise ValueError('not a feed')
    items = []
    for entry in (node for node in root.iter() if node.tag.rsplit('}', 1)[-1] in ('item', 'entry')):
        fields = {}
        for child in entry:
            name = child.tag.rsplit('}', 1)[-1]
            fields.setdefault(name, ''.join(child.itertext()))
            if name == 'link' and child.get('href') and child.get('rel', 'alternate') == 'alternate':
                fields['link'] = child.get('href')
        title = plain(fields.get('title', ''), 220)
        link = approved_url(fields.get('link', '').strip(), source)
        summary = plain(fields.get('description') or fields.get('summary') or '', 280)
        if not title or not link:
            continue
        if source['category'] == 'AI hardware' and not HARDWARE.search(title + ' ' + summary):
            continue
        published = date_value(fields.get('pubDate') or fields.get('published') or fields.get('date') or fields.get('updated') or '')
        items.append({'title': title, 'url': link, 'summary': summary, 'date': published,
                      'source': source_id, 'category': source['category']})
        if len(items) >= 1500:
            break
    return merge_items(items, limit=60)


def merge_items(items, limit=120):
    unique = {}
    for item in items:
        if item['url'] not in unique or item['date'] > unique[item['url']]['date']:
            unique[item['url']] = item
    return sorted(unique.values(), key=lambda item: (item['date'], item['url']), reverse=True)[:limit]


class FeedRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, source):
        self.source = source
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not approved_url(newurl, self.source):
            raise ValueError('redirect outside source')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(source_id, previous):
    source = SOURCES[source_id]
    headers = {'User-Agent': 'AIReadingDesk/1.0 (public RSS reader)', 'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml', 'Accept-Encoding': 'identity'}
    for field, header in [('etag', 'If-None-Match'), ('modified', 'If-Modified-Since')]:
        if previous.get(field):
            headers[header] = previous[field]
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), FeedRedirect(source))
    request = urllib.request.Request(source['url'], headers=headers)
    try:
        with opener.open(request, timeout=10) as response:
            data = response.read(MAX_BYTES + 1)
            items = parse_feed(data, source_id)
            if not items:
                raise ValueError('no usable entries')
            return {'items': items, 'etag': response.headers.get('ETag', ''),
                    'modified': response.headers.get('Last-Modified', ''), 'checked': now()}
    except urllib.error.HTTPError as error:
        if error.code == 304 and previous.get('items'):
            return dict(previous, checked=now())
        raise


def make_config(theme='random', seed=None):
    rng = random.Random(seed if seed is not None else secrets.randbits(128))
    theme = rng.choice(list(THEMES)) if theme == 'random' else theme
    if theme not in THEMES:
        raise ValueError('invalid theme')
    return {'version': 1, 'theme': theme, 'seed': rng.getrandbits(128)}


def collect(config, previous=None, fetcher=fetch):
    previous = previous or {}
    feeds = dict(previous.get('feeds', {}))
    success = 0
    failed = []
    for source_id in THEMES[config['theme']][2]:
        try:
            fresh = fetcher(source_id, feeds.get(source_id, {}))
            fresh['items'] = merge_items(fresh['items'] + feeds.get(source_id, {}).get('items', []), limit=60)
            feeds[source_id] = fresh
            success += 1
        except Exception:
            failed.append(source_id)
    items = [item for source_id in THEMES[config['theme']][2]
             for item in feeds.get(source_id, {}).get('items', [])]
    if config['theme'] == 'ai-digest':
        items = [item for category in ('AI news', 'AI hardware', 'AI research')
                 for item in merge_items([entry for entry in items if entry['category'] == category], limit=40)]
    items = merge_items(items)
    cache = {'feeds': feeds, 'updated': now() if success else previous.get('updated', ''), 'failed': failed}
    return cache, items, success


def render_site(directory, config, items=None, updated='', failed=None):
    items = items or []
    rng = random.Random(config['seed'])
    title, subtitle, source_ids = THEMES[config['theme']]
    bg, ink, accent = rng.choice(PALETTES)
    layout = rng.choice(['grid', 'journal', 'feature'])
    serif = rng.choice(['Georgia,serif', 'system-ui,sans-serif'])
    edition = rng.choice(['The reading desk', 'A public-source digest', 'Notes from the frontier'])
    directory.mkdir(mode=0o755)
    directory.chmod(0o755)
    esc = html.escape
    stamp = 'Last successful refresh: ' + updated[:16].replace('T', ' ') + ' UTC' if updated else 'Awaiting the first successful source update'
    def page(heading, body):
        return f'''<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="{subtitle}">
<title>{esc(heading)} · {esc(title)}</title><link rel="stylesheet" href="/style.css"></head>
<body class="{layout}"><header><a class="brand" href="/">{esc(title)}</a>
<nav aria-label="Main navigation"><a href="/">Latest</a><a href="/archive.html">Archive</a><a href="/sources.html">Sources</a><a href="/about.html">About</a></nav></header>
<main>{body}</main><footer><div>{esc(title)}<br><span>{esc(stamp)}</span></div><span>Titles and brief excerpts link to their original publishers.</span></footer></body></html>'''
    def card(item):
        source = SOURCES[item['source']]
        label = item['date'][:10] or 'Source date unavailable'
        return f'<article><span class="number">{esc(item["category"])} / {esc(label)}</span><h2><a href="{esc(item["url"], quote=True)}" rel="noopener noreferrer">{esc(item["title"])}</a></h2><p>{esc(item["summary"])}</p><a class="source" href="{esc(item["url"], quote=True)}" rel="noopener noreferrer">{esc(source["name"])} ↗</a></article>'
    empty = '<p class="empty">No entries have been collected yet. The source links below are available while this reading desk prepares its first update.</p>'
    latest = items[:24]
    if config['theme'] == 'ai-digest':
        latest = merge_items([item for category in ('AI news', 'AI hardware', 'AI research')
                              for item in [entry for entry in items if entry['category'] == category][:8]], limit=24)
    cards = ''.join(card(item) for item in latest) or empty
    note = '<p class="update-note">Some sources are temporarily unavailable; earlier entries remain available with their original dates.</p>' if failed and items else ''
    body = f'<section class="hero"><p class="eyebrow">{edition}</p><h1>{subtitle}.</h1><p>A reading desk for public announcements, useful developments and papers worth exploring.</p><div class="art" aria-hidden="true"><i></i><i></i><i></i></div></section>{note}<section class="entries" aria-label="Recent entries">{cards}</section><p><a href="/archive.html">Browse the archive →</a></p>'
    pages = {'index.html': page('Latest', body),
             'archive.html': page('Archive', '<section class="reading"><p class="eyebrow">READING ARCHIVE</p><h1>Recent entries</h1></section><section class="entries">' + (''.join(card(item) for item in items) or empty) + '</section>'),
             'about.html': page('About', f'<section class="reading"><p class="eyebrow">ABOUT THIS READING DESK</p><h1>{title}</h1><p>{subtitle}. This independent reading desk collects titles and short excerpts from public feeds, with dates and links to the original sources.</p><p>Entries are refreshed every three days. Source dates are preserved, and older entries remain available when a publisher cannot be reached. Research feeds may include preprints that have not been peer reviewed.</p><p>Visit the original publisher for the complete article, paper and context. Inclusion does not imply endorsement or affiliation.</p><a href="/sources.html">Explore the sources →</a></section>'),
             'sources.html': page('Sources', '<section class="reading"><p class="eyebrow">PUBLIC SOURCES</p><h1>Follow the originals</h1><ul>' + ''.join(f'<li><a href="{esc(SOURCES[source]["url"], quote=True)}">{esc(SOURCES[source]["name"])}</a> — {esc(SOURCES[source]["category"])}</li>' for source in source_ids) + '</ul><p>The links lead to public publisher feeds. Article titles and short excerpts remain attributed to their sources.</p></section>'),
             '404.html': page('Page not found', '<section class="reading"><h1>This page is not here.</h1><p>There is more to read at the reading desk.</p><a href="/">Return home →</a></section>')}
    css = f''':root{{--paper:{bg};--ink:{ink};--accent:{accent}}}*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font:17px/1.7 system-ui,sans-serif}}a{{color:inherit;text-underline-offset:5px}}header,main,footer{{width:min(1120px,88%);margin:auto}}header{{display:flex;justify-content:space-between;align-items:center;padding:30px 0;border-bottom:1px solid currentColor;gap:28px}}.brand{{font:700 23px {serif};text-decoration:none}}nav{{display:flex;gap:20px;font-size:14px;flex-wrap:wrap}}h1,h2{{font-family:{serif};font-weight:500;line-height:1.15}}h1{{font-size:clamp(40px,6vw,78px);max-width:870px;margin:20px 0 28px}}h2{{font-size:26px;overflow-wrap:anywhere}}h2 a{{text-decoration:none}}.hero{{position:relative;padding:65px 0;overflow:hidden}}.hero>p{{max-width:620px}}.eyebrow,.number{{font-size:11px;letter-spacing:.12em;text-transform:uppercase}}.art{{display:flex;height:85px;gap:12px;margin-top:36px}}.art i{{display:block;background:var(--accent);width:180px;border-radius:100px 100px 0 0;opacity:.85}}.art i:nth-child(2){{border-radius:0 100px 100px 0;opacity:.55}}.art i:nth-child(3){{border-radius:50%;width:85px;opacity:.3}}.entries{{display:grid;grid-template-columns:repeat(3,1fr);gap:32px}}article{{padding:30px 0;border-top:1px solid currentColor}}article p{{font-size:16px;overflow-wrap:anywhere}}article>a{{font-size:13px}}.journal .entries{{grid-template-columns:1fr}}.journal article{{max-width:850px}}.feature article:first-child{{grid-column:span 2}}.reading{{max-width:850px;padding:55px 0 30px}}.reading p{{font-size:19px}}footer{{border-top:1px solid currentColor;margin-top:70px;padding:24px 0 40px;font-size:12px;display:flex;justify-content:space-between;gap:25px}}footer span{{opacity:.65}}.empty,.update-note{{max-width:750px}}a:focus-visible{{outline:2px solid var(--accent);outline-offset:5px}}@media(max-width:680px){{header{{display:block}}nav{{margin-top:18px;gap:18px}}.brand{{font-size:22px}}.entries{{grid-template-columns:1fr}}.feature article:first-child{{grid-column:auto}}.hero,.reading{{padding:40px 0}}footer{{display:block}}footer span{{display:block;margin-top:12px}}}}
'''
    pages['style.css'] = css
    for name, text in pages.items():
        path = directory / name
        path.write_text(text, encoding='utf-8')
        path.chmod(0o644)


def atomic_json(path, value):
    temp = path.with_name('.' + path.name + '-' + secrets.token_hex(8))
    try:
        with temp.open('x', encoding='utf-8') as stream:
            json.dump(value, stream)
        temp.chmod(0o600)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def refresh(site_root, state_dir, fetcher=fetch, renderer=render_site, min_interval=0):
    if site_root.is_symlink() or state_dir.is_symlink():
        raise ValueError('invalid root')
    with (state_dir / '.update.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        attempt_path = state_dir / 'last-attempt.json'
        if min_interval and attempt_path.exists():
            attempted = datetime.fromisoformat(json.loads(attempt_path.read_text())['attempted'])
            if (datetime.now(timezone.utc) - attempted).total_seconds() < min_interval:
                return {'status': 'PASS', 'published': False, 'reason': 'three-day interval not reached'}
        config = json.loads((state_dir / 'config.json').read_text())
        if config.get('version') != 1 or config.get('theme') not in THEMES or not isinstance(config.get('seed'), int):
            raise ValueError('invalid config')
        cache_path = state_dir / 'cache.json'
        previous = json.loads(cache_path.read_text()) if cache_path.exists() else {}
        atomic_json(attempt_path, {'attempted': now()})
        cache, items, success = collect(config, previous, fetcher)
        if not success:
            return {'status': 'WARN', 'published': False, 'reason': 'all sources unavailable; previous site retained'}
        releases = site_root / 'releases'
        if releases.is_symlink():
            raise ValueError('invalid releases directory')
        releases.mkdir(mode=0o755, exist_ok=True)
        stage = Path(tempfile.mkdtemp(prefix='.building-', dir=releases))
        new_link = site_root / ('.current-' + secrets.token_hex(8))
        release = releases / ('build-' + secrets.token_hex(8))
        try:
            renderer(stage / 'site', config, items, cache['updated'], cache['failed'])
            os.replace(stage / 'site', release)
            atomic_json(cache_path, cache)
            new_link.symlink_to(Path('releases') / release.name)
            os.replace(new_link, site_root / 'current')
        finally:
            shutil.rmtree(stage, ignore_errors=True)
            new_link.unlink(missing_ok=True)
        old = sorted((path for path in releases.iterdir() if re.fullmatch(r'build-[0-9a-f]{16}', path.name)
                      and path.is_dir() and not path.is_symlink()), key=lambda path: path.stat().st_mtime, reverse=True)
        for path in old[3:]:
            if path != release:
                shutil.rmtree(path, ignore_errors=True)
        return {'status': 'WARN' if cache['failed'] else 'PASS', 'published': True,
                'entries': len(items), 'sources_ok': success, 'sources_unavailable': len(cache['failed'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site-root', type=Path, default=Path('/var/www/xray-skill'))
    parser.add_argument('--state-dir', type=Path, default=Path('/var/lib/xray-skill-news'))
    parser.add_argument('--force', action='store_true', help='explicit manual refresh before the three-day interval')
    args = parser.parse_args()
    print(json.dumps(refresh(args.site_root, args.state_dir, min_interval=0 if args.force else 3 * 86400)))


if __name__ == '__main__':
    os.umask(0o077)
    try:
        main()
    except Exception:
        print('[FAIL] NEWS: update failed; details withheld', file=sys.stderr)
        sys.exit(1)
