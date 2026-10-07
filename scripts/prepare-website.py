#!/usr/bin/env python3
"""Prepare an AI feed website and private Nginx configuration. No service changes."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

_spec = importlib.util.spec_from_file_location('news_site', Path(__file__).with_name('news_site.py'))
news = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(news)
THEMES = news.THEMES


def create_site(directory, theme='random', seed=None):
    config = news.make_config(theme, seed)
    news.render_site(directory, config)
    return config


def nginx_config(server, site_root, cert, key, runtime, port=8003, trusted_ca=None):
    inbound = next(item for item in server['inbounds'] if item['tag'] == 'xhttp-in')
    host = inbound['streamSettings']['xhttpSettings']['host']
    path = inbound['streamSettings']['xhttpSettings']['path']
    backend = inbound['port']
    if not re.fullmatch(r'[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*', host):
        raise ValueError('invalid host')
    if not re.fullmatch(r'/[A-Za-z0-9_-]+', path):
        raise ValueError('unsupported path')
    if inbound['listen'] != '127.0.0.1' or not 1024 <= backend <= 65535 or not 1024 <= port <= 65535:
        raise ValueError('invalid listener')
    trusted_ca = trusted_ca or cert
    for value in [site_root, cert, key, runtime, trusted_ca]:
        if not re.fullmatch(r'/[A-Za-z0-9_./-]+', value) or '..' in Path(value).parts:
            raise ValueError('invalid local path')
    return f'''worker_processes 1;
pid {runtime}/nginx.pid;
error_log /dev/null crit;
events {{ worker_connections 1024; }}
http {{
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;
    server_tokens off;
    client_body_temp_path {runtime}/body;
    proxy_temp_path {runtime}/proxy;
    server {{
        listen 127.0.0.1:{port} ssl http2 proxy_protocol;
        server_name {host};
        ssl_certificate {cert};
        ssl_certificate_key {key};
        ssl_protocols TLSv1.2 TLSv1.3;
        root {site_root};
        index index.html;
        add_header X-Content-Type-Options nosniff always;
        location ~ ^{path}(?:/|$) {{
            proxy_pass https://127.0.0.1:{backend};
            proxy_http_version 1.1;
            proxy_set_header Host {host};
            proxy_set_header Connection "";
            proxy_ssl_server_name on;
            proxy_ssl_name {host};
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate {trusted_ca};
            proxy_ssl_verify_depth 5;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_cache off;
            proxy_intercept_errors off;
            client_max_body_size 0;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }}
        location ~ /\\. {{ return 404; }}
        location / {{ error_page 404 /404.html; try_files $uri $uri/ =404; }}
    }}
}}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server-config', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--theme', choices=['random', *THEMES], default='random')
    parser.add_argument('--fetch', choices=['on', 'off'], default='on')
    parser.add_argument('--certificate-mode', choices=['provided'], default='provided')
    args = parser.parse_args()
    output = Path(args.output_dir)
    if output.exists():
        raise ValueError('output must be new')
    with open(args.server_config, encoding='utf-8') as stream:
        server = json.load(stream)
    config = nginx_config(server, '/var/www/xray-skill/current',
                          '/etc/xray-skill/certs/origin/fullchain.pem',
                          '/etc/xray-skill/certs/origin/privkey.pem', '/run/xray-skill-web',
                          trusted_ca='/etc/ssl/certs/ca-certificates.crt')
    output.mkdir(mode=0o700)
    metadata = news.make_config(args.theme)
    cache, items, count = news.collect(metadata) if args.fetch == 'on' else ({}, [], 0)
    news.render_site(output / 'site', metadata, items, cache.get('updated', ''), cache.get('failed'))
    (output / 'news-cache.json').write_text(json.dumps(cache), encoding='utf-8')
    (output / 'news-cache.json').chmod(0o600)
    (output / 'news-attempt.json').write_text(json.dumps({'attempted': news.now()}), encoding='utf-8')
    (output / 'news-attempt.json').chmod(0o600)
    (output / 'nginx.conf').write_text(config, encoding='utf-8')
    (output / 'nginx.conf').chmod(0o600)
    (output / 'website.json').write_text(json.dumps(metadata), encoding='utf-8')
    (output / 'website.json').chmod(0o600)
    print('[PASS] WEB: AI reading site and private proxy configuration prepared')
    if not count:
        print('[WARN] NEWS: no initial feed refresh; empty reading desk awaits scheduled update')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('[FAIL] WEB: preparation failed; details withheld', file=sys.stderr)
        sys.exit(1)
