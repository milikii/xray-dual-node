#!/usr/bin/env bash
set +x
set -Eeuo pipefail
umask 077
usage() {
    printf 'Usage: check-live-auth.sh --xray PATH --work-dir PREPARED_DIR\n'
    printf 'Requires the prepared Phase 0 server to be running. Tests disposable clients on loopback 20810.\n'
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
[[ $xray_bin = /* && -x $xray_bin && $work = /* && -f $work/server.json ]] || exit 2
[[ -z $(ss -Hltn 'sport = :20810') ]] || exit 3
test_dir=$(mktemp -d "$work/auth.XXXXXXXX")
exec 3>&2 2>"$test_dir/harness-errors.log"
client_pid=''
cleanup() {
    if [[ -n $client_pid ]]; then
        kill "$client_pid" 2>/dev/null || true
        wait "$client_pid" 2>/dev/null || true
    fi
    rm -rf -- "$test_dir"
}
trap cleanup EXIT
trap 'printf "[FAIL] auth harness line %s; private logs withheld\n" "$LINENO" >&3' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

stop_client() {
    if [[ -n $client_pid ]]; then
        kill "$client_pid" 2>/dev/null || true
        wait "$client_pid" 2>/dev/null || true
        client_pid=''
    fi
}

run_case() {
    local name=$1 expected=$2 source=$3 status=0 ready=false matched=false cf526=false
    # Every failure is explicit: callers may run this function in an if/|| context,
    # where Bash disables errexit throughout the function.
    if ! jq --arg dir "$test_dir" '.inbounds[0].port=20810 | .log.error=($dir+"/client.log")' \
        "$source" > "$test_dir/active.json"; then
        printf '[FAIL] %s reason=client-render\n' "$name"
        return 1
    fi
    if ! "$xray_bin" run -test -c "$test_dir/active.json" > "$test_dir/test.log" 2>&1; then
        printf '[FAIL] %s reason=client-config-test\n' "$name"
        return 1
    fi
    : > "$test_dir/client.log"
    "$xray_bin" run -c "$test_dir/active.json" > "$test_dir/process.log" 2>&1 &
    client_pid=$!
    for ((i=0; i<100; i++)); do
        if ! kill -0 "$client_pid" 2>/dev/null; then break; fi
        if [[ -n $(ss -Hltn 'sport = :20810') ]]; then ready=true; break; fi
        sleep 0.05
    done
    if [[ $ready != true ]]; then
        stop_client
        printf '[FAIL] %s reason=client-not-ready\n' "$name"
        return 1
    fi
    curl --noproxy '' --proxy socks5h://127.0.0.1:20810 -fsS --max-time 12 \
        https://www.cloudflare.com/cdn-cgi/trace > "$test_dir/trace" 2> "$test_dir/curl.log" || status=$?
    stop_client
    if grep -Eqi '(status|HTTP)[^[:cntrl:]]{0,50}526([^0-9]|$)' "$test_dir/client.log" "$test_dir/curl.log"; then cf526=true; fi
    if [[ $expected == success ]]; then
        if [[ $status == 0 ]] && grep -q '^ip=' "$test_dir/trace"; then matched=true; fi
    elif [[ $status != 0 && $cf526 == false ]]; then
        matched=true
    fi
    if [[ $matched != true ]]; then
        printf '[FAIL] %s expected=%s curl_exit=%s cf_origin_526=%s\n' "$name" "$expected" "$status" "$cf526"
        return 1
    fi
    printf '[PASS] %s expected=%s curl_exit=%s\n' "$name" "$expected" "$status"
    return 0
}

baseline_failed=false
run_case node-a-baseline success "$work/client-a.json" || baseline_failed=true
run_case node-b-baseline success "$work/client-b.json" || baseline_failed=true
if [[ $baseline_failed == true ]]; then
    printf '[FAIL] AUTH: baseline failed; wrong-credential controls not run\n'
    exit 1
fi
jq 'del(.outbounds[0].streamSettings.realitySettings.mldsa65Verify)' "$work/client-a.json" > "$test_dir/no-verify.json"
run_case node-a-without-mldsa-verification success "$test_dir/no-verify.json" || exit 1

"$xray_bin" mldsa65 > "$test_dir/new-mldsa"
awk -F ': ' '$1=="Verify" {print $2}' "$test_dir/new-mldsa" > "$test_dir/new-verify"
jq --rawfile key "$test_dir/new-verify" '.outbounds[0].streamSettings.realitySettings.mldsa65Verify=($key|rtrimstr("\n"))' \
    "$work/client-a.json" > "$test_dir/wrong-verify.json"
run_case node-a-wrong-mldsa-verification failure "$test_dir/wrong-verify.json" || exit 1

openssl rand -hex 8 > "$test_dir/new-sid"
jq -e --rawfile sid "$test_dir/new-sid" '.inbounds[0].streamSettings.realitySettings.shortIds | index($sid|rtrimstr("\n")) == null' \
    "$work/server.json" >/dev/null
jq --rawfile sid "$test_dir/new-sid" '.outbounds[0].streamSettings.realitySettings.shortId=($sid|rtrimstr("\n"))' \
    "$work/client-a.json" > "$test_dir/wrong-sid.json"
run_case node-a-wrong-shortid failure "$test_dir/wrong-sid.json" || exit 1

# This fixed fingerprint is registered by v26.9.30; wire groups need separate capture.
jq '.outbounds[0].streamSettings.realitySettings.fingerprint="hellochrome_120"' \
    "$work/client-a.json" > "$test_dir/old-fingerprint.json"
run_case node-a-chrome120-fingerprint failure "$test_dir/old-fingerprint.json" || exit 1

"$xray_bin" vlessenc > "$test_dir/new-enc-pair"
awk '/^Authentication: ML-KEM-768, Post-Quantum/ {pq=1; next} pq && /^"encryption":/ {sub(/^"encryption": /, ""); print}' \
    "$test_dir/new-enc-pair" | jq -er 'select(startswith("mlkem768x25519plus."))' > "$test_dir/new-encryption"
jq --rawfile enc "$test_dir/new-encryption" '.outbounds[0].settings.vnext[0].users[0].encryption=($enc|rtrimstr("\n"))' \
    "$work/client-b.json" > "$test_dir/wrong-enc.json"
run_case node-b-wrong-vless-encryption failure "$test_dir/wrong-enc.json" || exit 1
run_case node-a-final-baseline success "$work/client-a.json" || exit 1
run_case node-b-final-baseline success "$work/client-b.json" || exit 1
printf 'AUTH_POC: PASS (same-core clients; GUI compatibility untested)\n'
