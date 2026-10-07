#!/usr/bin/env bash
# Compatibility entrypoint: public CA certificates are required for all new work.
set +x
set -Eeuo pipefail
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: renew-selfsigned.sh\nDeprecated: refuses self-signed renewal. Migrate to Certbot public CA renewal.\n'
    exit 0
fi
printf '[FAIL] CERT: self-signed renewal is disabled; migrate to public CA and Certbot\n' >&2
exit 2
