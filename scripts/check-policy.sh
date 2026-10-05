#!/usr/bin/env bash
set +x
set -Eeuo pipefail
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: xrayctl check-policy /absolute/path/to/server.json\n'
    printf 'Read-only: rejects REALITY fallback limit fields, including zero-valued ones. No config output.\n'
    exit 0
fi
[[ $# == 1 && $1 = /* && -f $1 ]] || { printf '[FAIL] POLICY: expected server JSON path\n' >&2; exit 2; }
if jq -e '
    [.inbounds[] | .streamSettings | select(.security=="reality")] as $r |
    ($r|length)>0 and all($r[];
        (.realitySettings|type)=="object" and
        (.realitySettings|has("limitFallbackUpload") or has("limitFallbackDownload")|not))
' "$1" >/dev/null 2>&1; then
    printf '[PASS] POLICY: REALITY fallback bandwidth limits absent\n'
else
    printf '[FAIL] POLICY: invalid server config or forbidden REALITY fallback limits; contents withheld\n' >&2
    exit 6
fi
