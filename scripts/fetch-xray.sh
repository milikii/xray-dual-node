#!/usr/bin/env bash
# Deterministic download/verification helper; never switches or restarts a service.
set -Eeuo pipefail
umask 077
usage() {
    cat <<'EOF'
Usage: fetch-xray.sh --output-dir NEW_DIRECTORY [--archive LOCAL_ZIP] [--arch amd64|arm64]
Download the tag/hash fixed in versions.env, verify, and extract the core and geo assets.
--archive uses a cached official ZIP and performs the same checksum verification.
The output directory must not exist. No install, service mutation, or latest resolution.
EOF
}
output='' archive='' arch=$(uname -m)
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --output-dir|--archive|--arch)
            (($# >= 2)) || exit 2
            case "$1" in --output-dir) output=$2;; --archive) archive=$2;; --arch) arch=$2;; esac
            shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ $output = /* && ! -e $output && ! -L $output ]] || { usage >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=versions.env
source "$root/versions.env"
case "$arch" in
    x86_64|amd64) asset=Xray-linux-64.zip; expected=$XRAY_PINNED_SHA256_LINUX_64 ;;
    aarch64|arm64) asset=Xray-linux-arm64-v8a.zip; expected=$XRAY_PINNED_SHA256_LINUX_ARM64_V8A ;;
    *) printf '[FAIL] unsupported architecture\n' >&2; exit 3 ;;
esac
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
trap 'printf "[FAIL] core fetch/verification failed at line %s\n" "$LINENO" >&2' ERR
if [[ -n $archive ]]; then cp -- "$archive" "$work/core.zip"; else
    curl -fsSL --connect-timeout 10 --max-time 180 --retry 2 \
        "https://github.com/XTLS/Xray-core/releases/download/$XRAY_PINNED_TAG/$asset" -o "$work/core.zip"
fi
printf '%s  %s\n' "$expected" "$work/core.zip" | sha256sum -c - >/dev/null
# Extract only fixed file names, not arbitrary archive paths.
mkdir "$work/bin"
for file in xray geoip.dat geosite.dat; do
    unzip -p "$work/core.zip" "$file" > "$work/bin/$file"
    [[ -s $work/bin/$file ]]
done
chmod 755 "$work/bin/xray"
chmod 644 "$work/bin/geoip.dat" "$work/bin/geosite.dat"
jq -n --arg tag "$XRAY_PINNED_TAG" --arg asset "$asset" --arg sha256 "$expected" \
    '{tag:$tag,asset:$asset,sha256:$sha256}' > "$work/bin/artifact.json"
mkdir -p -- "$(dirname -- "$output")"
mv -T -- "$work/bin" "$output"
printf '[PASS] fixed core archive verified and extracted: %s\n' "$output"
