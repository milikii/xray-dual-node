#!/usr/bin/env bash
set +x
set -Eeuo pipefail
umask 077
usage() {
    printf 'Usage: check-live-modes.sh --xray PATH --work-dir PREPARED_DIR\n'
    printf 'Tests 1 MiB downloads with packet-up and auto. Restarts client B and restores it. Never enables REALITY throttling.\n'
}
xray_bin='' work=''
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --xray|--work-dir)
            (($# >= 2)) || exit 2
            case "$1" in --xray) xray_bin=$2;; --work-dir) work=$2;; esac
            shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ $EUID == 0 && $xray_bin = /* && -x $xray_bin && $work = /* && -f $work/server.json ]] || exit 2
[[ $(systemctl show xray-poc.service -p ExecStart --value) == *"$work/server.json"* ]] || exit 3
[[ $(systemctl show xray-poc-client-b.service -p ExecStart --value) == *"$work/client-b.json"* ]] || exit 3
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/check-policy.sh" "$work/server.json"
exec 3>&2 2>"$work/mode-errors.log"
saved=$(mktemp -d "$work/mode-backup.XXXXXXXX")
cp "$work/client-b.json" "$saved/client-b.json"
test_config() { "$xray_bin" run -test -format json -c "$1" > "$work/mode-test.log" 2>&1; }
restore() {
    local result=$?
    trap - EXIT
    if test_config "$saved/client-b.json"; then
        cp "$saved/client-b.json" "$work/client-b.json"
        if systemctl restart xray-poc-client-b; then
            rm -rf -- "$saved"
            printf '[PASS] baseline client B restored; server unchanged\n'
        else
            result=1
            printf '[FAIL] baseline restart failed; private backups retained\n' >&3
        fi
    else
        result=1
        printf '[FAIL] backup config test failed; private backups retained\n' >&3
    fi
    exit "$result"
}
trap restore EXIT
trap 'printf "[FAIL] modes harness line %s; private logs withheld\n" "$LINENO" >&3' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

restart_client() {
    test_config "$work/client-b.json"
    systemctl restart xray-poc-client-b
    for ((i=0; i<100; i++)); do
        if [[ -n $(ss -Hltn 'sport = :20809') ]]; then return 0; fi
        sleep 0.05
    done
    return 1
}
benchmark() {
    local label=$1
    curl --noproxy '' --proxy socks5h://127.0.0.1:20809 -fsS --max-time 25 \
        'https://speed.cloudflare.com/__down?bytes=1048576' -o /dev/null \
        -w '{"bytes":%{size_download},"seconds":%{time_total},"bytes_per_second":%{speed_download}}\n' \
        > "$work/bench-$label.json" 2> "$work/bench-$label.log"
    jq -e '.bytes==1048576 and .seconds>0' "$work/bench-$label.json" >/dev/null
    printf '[PASS] %s ' "$label"
    jq -c . "$work/bench-$label.json"
}
restart_client
benchmark packet-up

jq '.outbounds[0].streamSettings.xhttpSettings.mode="auto"' "$saved/client-b.json" > "$saved/auto.json"
test_config "$saved/auto.json"
cp "$saved/auto.json" "$work/client-b.json"
restart_client
benchmark auto

printf 'MODE_POC: PASS (short samples, not a capacity benchmark or tuning recommendation)\n'
