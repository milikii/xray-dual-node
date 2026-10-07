#!/usr/bin/env bash
# Bootstrap a selected deployment host without requiring Python or jq.
set -Eeuo pipefail
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: prepare-host.sh\nInstall missing Debian/Ubuntu deployment dependencies as root. Does not deploy nodes.\n'
    exit 0
fi
[[ $# == 0 ]] || exit 2
fail() { printf '[FAIL] HOST: %s\n' "$1" >&2; exit 3; }
[[ $EUID == 0 ]] || fail 'run on the selected VPS as root or with sudo'
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}:${VERSION_ID:-}:$(uname -m)" in
    debian:12:x86_64|debian:13:x86_64|debian:12:aarch64|debian:13:aarch64|ubuntu:22.04:x86_64|ubuntu:24.04:x86_64|ubuntu:22.04:aarch64|ubuntu:24.04:aarch64) ;;
    *) fail 'supported targets: Debian 12/13, Ubuntu 22.04/24.04; amd64/arm64' ;;
esac
[[ -d /run/systemd/system ]] || fail 'a systemd host is required'
command -v apt-get >/dev/null || fail 'apt-get unavailable'
packages=(curl jq unzip openssl iproute2 ca-certificates zstd util-linux python3 certbot nginx)
missing=()
for package in "${packages[@]}"; do
    if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != 'install ok installed' ]]; then
        missing+=("$package")
    fi
done
if ((${#missing[@]} == 0)); then
    printf '[PASS] HOST: deployment packages already installed\n'
    exit 0
fi

# Preserve an existing service; a newly packaged default nginx must not claim
# ports 80/443 on the next boot either. The Skill installs its own units later.
new_nginx=false
if [[ " ${missing[*]} " == *' nginx '* ]] && ! systemctl cat nginx.service >/dev/null 2>&1; then
    new_nginx=true
fi

# Prevent package maintainer scripts from starting a default web server.
# Never replace a host administrator's policy, even temporarily.
policy=/usr/sbin/policy-rc.d
created_policy=false
cleanup() {
    if [[ $created_policy == true ]]; then rm -f -- "$policy"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -e $policy || -L $policy ]]; then
    for action in start restart; do
        status=0
        "$policy" nginx "$action" >/dev/null 2>&1 || status=$?
        [[ $status == 101 ]] || fail 'existing policy-rc.d does not deny nginx startup; preserve it and arrange package startup suppression before retrying'
    done
else
    (set -o noclobber; printf '#!/bin/sh\nexit 101\n' > "$policy") || fail 'cannot create temporary package startup policy'
    created_policy=true
    chmod 755 "$policy"
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${missing[@]}"
if [[ $new_nginx == true ]]; then systemctl disable nginx.service; fi
for command in python3 jq curl unzip openssl ss zstd flock certbot nginx; do
    command -v "$command" >/dev/null || fail "missing command after installation: $command"
done
printf '[PASS] HOST: deployment dependencies installed; node setup and preflight still required\n'
