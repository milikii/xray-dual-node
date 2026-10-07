#!/usr/bin/env python3
"""Feed ingestion and atomic publication tests using public synthetic content."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
from datetime import datetime, timezone, timedelta

spec = importlib.util.spec_from_file_location('news', Path(__file__).resolve().parents[2] / 'scripts/news_site.py')
news = importlib.util.module_from_spec(spec)
spec.loader.exec_module(news)

RSS = b'''<rss><channel><item><title>New model &amp; tools</title>
<link>https://huggingface.co/blog/test?utm_source=rss</link>
<pubDate>Mon, 05 Oct 2026 10:00:00 +0000</pubDate>
<description><![CDATA[<p>Useful public summary.</p><script>BAD_SCRIPT</script><img src=x onerror="BAD_EVENT">]]></description>
</item><item><title>duplicate</title><link>https://huggingface.co/blog/test#fragment</link></item>
<item><title>untrusted</title><link>https://evil.invalid/article</link></item>
<item><title>javascript</title><link>javascript:alert(1)</link></item></channel></rss>'''
ATOM = b'''<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>A paper</title>
<link href="https://arxiv.org/abs/2610.00001"/><published>2026-10-05T12:00:00Z</published><summary>Public abstract excerpt.</summary></entry></feed>'''


def fixture(source_id, previous):
    source = news.SOURCES[source_id]
    return {'items': [{'title': 'Public update', 'summary': 'A short attributed excerpt.',
        'url': 'https://' + source['hosts'][0] + '/sample', 'date': '2026-10-05T10:00:00+00:00',
        'source': source_id, 'category': source['category']}], 'etag': 'test-tag', 'checked': news.now()}


class NewsTests(unittest.TestCase):
    def test_rss_plain_text_dedup_dates_and_url_allowlist(self):
        items = news.parse_feed(RSS, 'huggingface')
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]['url'], 'https://huggingface.co/blog/test')
        self.assertEqual(items[0]['date'], '2026-10-05T10:00:00+00:00')
        self.assertEqual(items[0]['summary'], 'Useful public summary.')
        self.assertEqual(items[0]['title'], 'New model & tools')

    def test_atom_and_missing_dates(self):
        self.assertEqual(news.parse_feed(ATOM, 'arxiv-ai')[0]['date'], '2026-10-05T12:00:00+00:00')
        self.assertEqual(news.date_value('not a date'), '')
        self.assertEqual(news.date_value('2999-01-01T00:00:00Z'), '')

    def test_malicious_or_oversized_xml(self):
        for data in [b'<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]><rss/>',
                     b'<!ENTITY x "x"><rss/>', b'x' * (news.MAX_BYTES + 1), b'<html/>']:
            with self.assertRaises((ValueError, news.ET.ParseError)):
                news.parse_feed(data, 'mit')

    def test_hardware_filter(self):
        data = b'<rss><channel><item><title>GPU inference hardware</title><link>https://www.servethehome.com/gpu/</link></item><item><title>Home router review</title><link>https://www.servethehome.com/router/</link></item></channel></rss>'
        items = news.parse_feed(data, 'sth')
        self.assertEqual(len(items), 1)
        self.assertIn('GPU', items[0]['title'])

    def test_redirect_cannot_leave_publisher(self):
        handler = news.FeedRedirect(news.SOURCES['mit'])
        with self.assertRaises(ValueError):
            handler.redirect_request(None, None, 302, '', {}, 'http://127.0.0.1/secrets')
        self.assertIsNone(news.approved_url('https://news.mit.edu.evil.invalid/path', news.SOURCES['mit']))
        self.assertIsNone(news.approved_url('https://user:pass@news.mit.edu/path', news.SOURCES['mit']))

    def test_conditional_fetch_304_preserves_items(self):
        old = fixture('huggingface', {})
        class Opener:
            def open(self, request, timeout):
                assert request.get_header('If-none-match') == 'test-tag'
                raise urllib.error.HTTPError(request.full_url, 304, 'unchanged', {}, None)
        with patch.object(news.urllib.request, 'build_opener', return_value=Opener()):
            refreshed = news.fetch('huggingface', old)
        self.assertEqual(refreshed['items'], old['items'])

    def test_partial_failures_keep_original_dates(self):
        config = news.make_config('ai-news', 1)
        initial, items, count = news.collect(config, fetcher=fixture)
        def partial(source, previous):
            if source == 'mit':
                raise RuntimeError('PRIVATE_ERROR')
            return fixture(source, previous)
        cache, retained, count = news.collect(config, initial, partial)
        self.assertEqual(count, 1)
        self.assertEqual(cache['failed'], ['mit'])
        self.assertEqual(retained, items)
        self.assertNotIn('PRIVATE_ERROR', json.dumps(cache))

    def test_atomic_refresh_empty_failure_and_stable_style(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, state = Path(tmp) / 'public', Path(tmp) / 'state'
            root.mkdir()
            state.mkdir(mode=0o700)
            config = news.make_config('ai-news', 3)
            (state / 'config.json').write_text(json.dumps(config))
            def fail(source, previous):
                raise RuntimeError('offline')
            self.assertFalse(news.refresh(root, state, fail)['published'])
            self.assertFalse((root / 'current').exists())
            old_umask = os.umask(0o077)
            try:
                first = news.refresh(root, state, fixture)
            finally:
                os.umask(old_umask)
            self.assertTrue(first['published'])
            target = (root / 'current').readlink()
            content = (root / 'current/index.html').read_bytes()
            css = (root / 'current/style.css').read_bytes()
            self.assertEqual((root / 'current').stat().st_mode & 0o777, 0o755)
            self.assertEqual((root / 'current/index.html').stat().st_mode & 0o777, 0o644)
            self.assertFalse(news.refresh(root, state, fail)['published'])
            self.assertEqual((root / 'current').readlink(), target)
            self.assertEqual((root / 'current/index.html').read_bytes(), content)
            def broken(*args):
                raise OSError('render failure')
            with self.assertRaises(OSError):
                news.refresh(root, state, fixture, broken)
            self.assertEqual((root / 'current').readlink(), target)
            self.assertFalse(list((root / 'releases').glob('.building-*')))
            for _ in range(4):
                news.refresh(root, state, fixture)
            self.assertEqual((root / 'current/style.css').read_bytes(), css)
            self.assertLessEqual(len(list((root / 'releases').glob('build-*'))), 3)
            self.assertEqual((state / 'cache.json').stat().st_mode & 0o777, 0o600)

    def test_render_escapes_feed_content(self):
        with tempfile.TemporaryDirectory() as tmp:
            item = fixture('huggingface', {})['items'][0]
            item['title'] = '<script>alert(1)</script>'
            item['summary'] = '<img src=x onerror=alert(1)>'
            output = Path(tmp) / 'site'
            news.render_site(output, news.make_config('ai-news', 2), [item])
            text = (output / 'index.html').read_text()
            self.assertNotIn('<script', text)
            self.assertNotIn('<img', text)
            self.assertIn('&lt;script&gt;', text)
            self.assertIn('Hugging Face', text)
            self.assertIn('2026-10-05', text)

    def test_three_day_gate_survives_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, state = Path(tmp) / 'public', Path(tmp) / 'state'
            root.mkdir()
            state.mkdir()
            (state / 'config.json').write_text(json.dumps(news.make_config('ai-news', 1)))
            news.atomic_json(state / 'last-attempt.json', {'attempted': news.now()})
            def unexpected(*args):
                self.fail('must not fetch before three days')
            result = news.refresh(root, state, unexpected, min_interval=3 * 86400)
            self.assertFalse(result['published'])
            old = (datetime.now(timezone.utc) - timedelta(days=3, minutes=1)).isoformat()
            news.atomic_json(state / 'last-attempt.json', {'attempted': old})
            result = news.refresh(root, state, fixture, min_interval=3 * 86400)
            self.assertTrue(result['published'])


if __name__ == '__main__':
    unittest.main()
