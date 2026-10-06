#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
if [[ ${1:-} == --help ]]; then
    printf 'Usage: tests/unit/helper-contracts.sh\nOffline installer and archive-integrity tests using synthetic fixtures.\n'
    exit 0
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
trap 'printf "[FAIL] helper contract at line %s\n" "$LINENO" >&2' ERR
mkdir "$work/project" "$work/conflict"
"$root/scripts/install-skill.sh" --project "$work/project" >/dev/null
for platform in .agents .claude; do
    [[ $(readlink -f "$work/project/$platform/skills/xray-dual-node") == "$root" ]]
done
"$root/scripts/install-skill.sh" --project "$work/project" >/dev/null
mkdir -p "$work/conflict/.claude/skills/xray-dual-node"
printf 'previous skill\n' > "$work/conflict/.claude/skills/xray-dual-node/retained.txt"
if "$root/scripts/install-skill.sh" --project "$work/conflict" > "$work/conflict.log" 2>&1; then exit 1; fi
[[ ! -e $work/conflict/.agents/skills/xray-dual-node ]]
"$root/scripts/install-skill.sh" --project "$work/conflict" --force >/dev/null
[[ $(rg --files --hidden "$work/conflict/.claude/skills" -g retained.txt | wc -l) == 1 ]]
printf '[PASS] both platform paths, idempotent links, conflict refusal and preserved force backup\n'

# A disposable skill copy lets us test a checksum fixture without altering the real pin.
mkdir -p "$work/fixture/scripts" "$work/archive-input"
cp "$root/scripts/fetch-xray.sh" "$work/fixture/scripts/"
printf 'synthetic executable fixture\n' > "$work/archive-input/xray"
printf 'synthetic data\n' > "$work/archive-input/geoip.dat"
printf 'synthetic data\n' > "$work/archive-input/geosite.dat"
python3 - "$work" <<'PY'
from pathlib import Path
from zipfile import ZipFile
import sys
work=Path(sys.argv[1])
with ZipFile(work/'fixture.zip','w') as archive:
    for name in ('xray','geoip.dat','geosite.dat'):
        archive.write(work/'archive-input'/name,name)
PY
digest=$(sha256sum "$work/fixture.zip" | cut -d ' ' -f 1)
printf 'XRAY_PINNED_TAG="v0.0.0"\nXRAY_PINNED_SHA256_LINUX_64="%s"\nXRAY_PINNED_SHA256_LINUX_ARM64_V8A="%s"\n' \
    "$digest" "$digest" > "$work/fixture/versions.env"
"$work/fixture/scripts/fetch-xray.sh" --arch amd64 --archive "$work/fixture.zip" --output-dir "$work/good" >/dev/null
cmp -s "$work/good/xray" "$work/archive-input/xray"
jq -e --arg hash "$digest" '.sha256==$hash and .tag=="v0.0.0"' "$work/good/artifact.json" >/dev/null
cp "$work/fixture.zip" "$work/corrupt.zip"
printf 'tampered\n' >> "$work/corrupt.zip"
if "$work/fixture/scripts/fetch-xray.sh" --arch amd64 --archive "$work/corrupt.zip" --output-dir "$work/bad" > "$work/download.log" 2>&1; then exit 1; fi
[[ ! -e $work/bad ]]
if "$work/fixture/scripts/fetch-xray.sh" --arch amd64 --archive "$work/fixture.zip" --output-dir "$work/good" > "$work/download.log" 2>&1; then exit 1; fi
cmp -s "$work/good/xray" "$work/archive-input/xray"
printf '[PASS] verified extraction, tampered archive rejection and existing directory protection\n'
