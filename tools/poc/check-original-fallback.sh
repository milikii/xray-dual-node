#!/usr/bin/env bash
set +x
# Temporarily exercise the rejected topology on the explicitly prepared PoC service.
set -Eeuo pipefail
umask 077
usage() {
    printf 'Usage: check-original-fallback.sh --xray PATH --work-dir PREPARED_DIR\n'
    printf 'Temporarily restarts xray-poc with original-A fallbacks, then restores A-prime. Requires root and tshark.\n'
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
exec 3>&2 2>"$work/original-errors.log"
trap 'printf "[FAIL] original-A harness line %s; private logs withheld\n" "$LINENO" >&3' ERR
jq -e '.inbounds[0].streamSettings.realitySettings.target=="127.0.0.1:8001"' "$work/server.json" >/dev/null
backup=$(mktemp "$work/server-backup.XXXXXXXX")
cp "$work/server.json" "$backup"
capture_pid=''
restore() {
    local result=$?
    trap - EXIT
    if [[ -n $capture_pid ]]; then
        kill "$capture_pid" 2>/dev/null || true
        wait "$capture_pid" 2>/dev/null || true
    fi
    if "$xray_bin" run -test -format json -c "$backup" > "$work/restore-test.log" 2>&1; then
        mv -f "$backup" "$work/server.json"
        if systemctl restart xray-poc; then
            printf '[PASS] A-prime config restored\n'
        else
            printf '[FAIL] A-prime restart failed\n' >&3
            result=1
        fi
    else
        printf '[FAIL] saved config validation failed; retained private backup\n' >&3
        result=1
    fi
    exit "$result"
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cdn=$(jq -r '.inbounds[2].streamSettings.xhttpSettings.host' "$backup")
dest=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$backup")
jq --arg cdn "$cdn" --arg dest "$dest" '
    .inbounds[0].streamSettings.realitySettings.target=($dest+":443") |
    .inbounds[0].streamSettings.realitySettings.xver=0 |
    .inbounds[0].settings.fallbacks=[{name:$cdn,dest:8002,xver:2}]
    ' "$backup" > "$work/original-a.json"
"$xray_bin" run -test -c "$work/original-a.json" > "$work/original-a-test.log" 2>&1
cp "$work/original-a.json" "$work/server.json"
systemctl restart xray-poc
sleep 1
systemctl is-active --quiet xray-poc
tshark -i lo -f 'tcp dst port 8002' -a duration:8 -Y 'tcp.flags.syn == 1 && tcp.flags.ack == 0' \
    -T fields -e tcp.srcport > "$work/original-a-b-syns.txt" 2> "$work/original-a-capture.log" &
capture_pid=$!
sleep 1
status=$(curl --noproxy '*' -sSI --max-time 6 "https://$cdn/" -o "$work/original-a-cf-response.txt" -w '%{http_code}')
wait "$capture_pid"
capture_pid=''
printf 'ORIGINAL_A_CF_STATUS=%s\n' "$status"
printf 'ORIGINAL_A_B_CONNECTIONS=%s\n' "$(wc -l < "$work/original-a-b-syns.txt")"
[[ ! -s $work/original-a-b-syns.txt ]]

timeout 8 openssl s_client -connect "$dest:443" -servername "$cdn" -showcerts </dev/null \
    > "$work/original-a-direct-peer.txt" 2> "$work/original-a-direct-peer.log"
timeout 8 openssl s_client -connect 127.0.0.1:443 -servername "$cdn" -showcerts </dev/null \
    > "$work/original-a-peer.txt" 2> "$work/original-a-peer.log"
openssl x509 -in "$work/original-a-direct-peer.txt" -outform DER > "$work/original-a-direct-cert.der"
openssl x509 -in "$work/original-a-peer.txt" -outform DER > "$work/original-a-peer-cert.der"
cmp -s "$work/original-a-direct-cert.der" "$work/original-a-peer-cert.der"
printf '[PASS] original-A CDN SNI receives camouflage certificate; actual CF probe opens zero connections to B\n'
