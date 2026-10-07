#!/usr/bin/env python3
"""Print a Cloudflare cache-bypass expression containing only the XHTTP hostname."""
import argparse
import json
from pathlib import Path
import re
import sys


def cache_expression(config):
    nodes = [node for node in config['inbounds'] if node.get('tag') == 'xhttp-in']
    if len(nodes) != 1:
        raise ValueError('one XHTTP inbound required')
    stream = nodes[0]['streamSettings']
    if stream['network'] != 'xhttp' or stream['security'] != 'tls':
        raise ValueError('XHTTP TLS required')
    host = stream['xhttpSettings']['host']
    # Reject expression/control-character injection instead of echoing arbitrary config text.
    if not isinstance(host, str) or not 1 <= len(host) <= 253:
        raise ValueError('invalid hostname')
    labels = host.split('.')
    if len(labels) < 2 or not re.search('[a-zA-Z]', labels[-1]) or any(
        not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?', label)
        for label in labels
    ):
        raise ValueError('invalid hostname')
    return f'(http.host eq "{host.lower()}")'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server-config', default='/etc/xray-skill/config.json',
                        help='private server JSON; only the validated hostname is printed')
    args = parser.parse_args()
    try:
        expression = cache_expression(json.loads(Path(args.server_config).read_text()))
    except (OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError):
        print('[FAIL] CF_CACHE: cannot validate XHTTP hostname; private details withheld', file=sys.stderr)
        return 1
    print(expression)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
