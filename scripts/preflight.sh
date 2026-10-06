#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: preflight.sh [--json]\nRead-only host checks for the Skill. DNS/CF/target checks are guided separately.\n'
    exit 0
fi
json=false
if [[ ${1:-} == --json ]]; then json=true; shift; fi
[[ $# == 0 ]] || exit 2
command -v jq >/dev/null || { printf '[FAIL] P00 jq required; let the agent install prerequisites\n' >&2; exit 3; }
result=$(mktemp)
trap 'rm -f -- "$result"' EXIT
failed=false
row() {
    jq -cn --arg id "$1" --arg status "$2" --arg detail "$3" '{id:$id,status:$status,detail:$detail}' >> "$result"
    if [[ $2 == FAIL ]]; then failed=true; fi
}
# shellcheck disable=SC1091
source /etc/os-release
case "$ID:$VERSION_ID:$(uname -m)" in
    debian:12:x86_64|debian:13:x86_64|ubuntu:22.04:x86_64|ubuntu:24.04:x86_64|debian:12:aarch64|debian:13:aarch64|ubuntu:22.04:aarch64|ubuntu:24.04:aarch64)
        row P01 PASS 'supported OS/architecture; see tested coverage matrix' ;;
    *) row P01 FAIL 'host outside the documented Debian/Ubuntu support range' ;;
esac
if [[ $EUID == 0 && -d /run/systemd/system ]]; then row P02 PASS 'root and systemd available'; else row P02 FAIL 'run on a systemd VPS as root'; fi
if [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null || true) == yes ]]; then
    row P03 PASS 'system reports synchronized time; timestamp precision is not independently measured'
else row P03 FAIL 'time synchronization not confirmed'; fi
if command -v ss >/dev/null && [[ -z $(ss -Hltn 'sport = :443') ]]; then
    row P04 PASS '443 free'
elif systemctl is-active --quiet xray-skill.service; then
    row P04 WARN 'existing Xray service; follow repair/upgrade flow, never reinitialize credentials'
else row P04 FAIL '443 unavailable or listener inspection unavailable'; fi
missing=()
for dep in curl openssl unzip flock ss timeout getent tar zstd; do command -v "$dep" >/dev/null || missing+=("$dep"); done
if ((${#missing[@]}==0)); then row P06 PASS 'required inspection and backup tools available'; else row P06 FAIL "missing commands: ${missing[*]}"; fi
for host in github.com api.cloudflare.com; do
    if curl -sSIL --connect-timeout 5 --max-time 10 "https://$host/" >/dev/null 2>&1; then
        row P07 PASS "HTTPS reachable: $host"
    else row P07 FAIL "HTTPS unavailable: $host"; fi
done
row P11 WARN 'agent must inspect existing firewall rules; this helper makes no changes'
row P12 WARN 'cloud security group requires provider or external verification'
row P15 WARN 'agent must separately check target and CDN DNS/CF settings'
if [[ $json == true ]]; then jq -s . "$result"; else jq -r '.|"[\(.status)] \(.id) \(.detail)"' "$result"; fi
[[ $failed == false ]] || exit 3
