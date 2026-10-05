#!/usr/bin/env bash
set +x
# Local evidence for T0; never a substitute for the real Cloudflare PoC.
set -Eeuo pipefail
umask 077

usage() {
    cat <<'EOF'
Usage: local-routing.sh --xray /absolute/path/to/xray [--base-port 25440]
Runs loopback-only REALITY/SNI/PROXY tests with disposable generated keys.
Requires Bash, jq, curl, OpenSSL, ss, timeout. Does not install or restart services.
The supplied binary must be the downloaded and checksum-verified v26.9.30 candidate.
EOF
}

xray_bin=
base_port=25440
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --xray|--base-port)
            (($# >= 2)) || { usage >&2; exit 2; }
            case "$1" in
                --xray) xray_bin=$2 ;;
                --base-port) base_port=$2 ;;
            esac
            shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ $xray_bin = /* && -x $xray_bin ]] || { usage >&2; exit 2; }
[[ $base_port =~ ^[1-9][0-9]{3,4}$ ]] && ((base_port < 65531)) || exit 2
for dep in jq curl openssl ss timeout; do
    command -v "$dep" >/dev/null || { printf '[FAIL] dependency %s\n' "$dep" >&2; exit 3; }
done
version=$($xray_bin version)
[[ $version = 'Xray 26.9.30 '* ]] || { printf '[FAIL] candidate version mismatch\n' >&2; exit 3; }

work=$(mktemp -d /tmp/xray-local-poc.XXXXXXXX)
exec 3>&2 2>"$work/harness-errors.log"
pids=()
cleanup() {
    local pid
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'printf "[FAIL] harness line %s (private logs withheld)\n" "$LINENO" >&3' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

front=$base_port
router=$((base_port + 1))
backend=$((base_port + 2))
camouflage=$((base_port + 3))
for port in "$front" "$router" "$backend" "$camouflage"; do
    [[ -z $(ss -Hltn "sport = :$port") ]] || { printf '[FAIL] port occupied: %s\n' "$port"; exit 3; }
done

"$xray_bin" x25519 > "$work/x25519"
awk -F ': ' '$1 == "PrivateKey" {print $2}' "$work/x25519" > "$work/private"
[[ $(wc -c < "$work/private") == 44 ]]
"$xray_bin" uuid > "$work/uuid"
openssl rand -hex 8 > "$work/shortid"
"$xray_bin" vlessenc > "$work/enc"
awk '/^Authentication: ML-KEM-768, Post-Quantum/ {pq=1; next} pq && /^"decryption":/ {sub(/^"decryption": /, ""); print}' \
    "$work/enc" | jq -er 'select(startswith("mlkem768x25519plus."))' > "$work/decryption"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$work/tls.key" -out "$work/tls.pem" -days 1 -subj /CN=cdn.example.com \
    -addext subjectAltName=DNS:cdn.example.com > "$work/openssl.log" 2>&1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$work/cam.key" -out "$work/cam.pem" -days 1 -subj /CN=example.com \
    -addext subjectAltName=DNS:example.com >> "$work/openssl.log" 2>&1

jq -n --rawfile key "$work/private" --rawfile uuid "$work/uuid" \
    --rawfile sid "$work/shortid" --rawfile dec "$work/decryption" \
    --arg dir "$work" --argjson front "$front" --argjson router "$router" \
    --argjson backend "$backend" --argjson cam "$camouflage" '
    def trim: rtrimstr("\n");
    {
      log: {loglevel:"warning"},
      inbounds: [
        {tag:"reality-in",listen:"127.0.0.1",port:$front,protocol:"vless",
         settings:{clients:[{id:($uuid|trim),flow:"xtls-rprx-vision"}],decryption:"none"},
         streamSettings:{network:"raw",security:"reality",realitySettings:{
           target:("127.0.0.1:"+($router|tostring)),xver:2,serverNames:["example.com"],
           privateKey:($key|trim),shortIds:[($sid|trim)],maxTimeDiff:60000}}},
        {tag:"sni-router",listen:"127.0.0.1",port:$router,protocol:"dokodemo-door",
         settings:{address:"127.0.0.1",port:9,network:"tcp"},
         streamSettings:{sockopt:{acceptProxyProtocol:true}},
         sniffing:{enabled:true,destOverride:["tls"],routeOnly:true}},
        {tag:"xhttp-in",listen:"127.0.0.1",port:$backend,protocol:"vless",
         settings:{clients:[{id:($uuid|trim)}],decryption:($dec|trim)},
         streamSettings:{network:"xhttp",security:"tls",
           xhttpSettings:{host:"cdn.example.com",path:"/poc-only",mode:"packet-up"},
           tlsSettings:{alpn:["h2","http/1.1"],certificates:[{
             certificateFile:($dir+"/tls.pem"),keyFile:($dir+"/tls.key")}]},
           sockopt:{acceptProxyProtocol:true}}},
        {tag:"camouflage-fixture",listen:"127.0.0.1",port:$cam,protocol:"vless",
         settings:{clients:[{id:($uuid|trim)}],decryption:"none"},
         streamSettings:{network:"xhttp",security:"tls",
           xhttpSettings:{host:"example.com",path:"/cam-only",mode:"packet-up"},
           tlsSettings:{alpn:["h2","http/1.1"],certificates:[{
             certificateFile:($dir+"/cam.pem"),keyFile:($dir+"/cam.key")}]}}}
      ],
      outbounds:[
        {tag:"blackhole",protocol:"blackhole"},
        {tag:"to-node-b",protocol:"freedom",settings:{redirect:("127.0.0.1:"+($backend|tostring)),proxyProtocol:2}},
        {tag:"to-camouflage",protocol:"freedom",settings:{redirect:("127.0.0.1:"+($cam|tostring))}}
      ],
      routing:{domainStrategy:"AsIs",rules:[
        {inboundTag:["sni-router"],domain:["full:cdn.example.com"],source:["127.0.0.2/32"],outboundTag:"to-node-b"},
        {inboundTag:["sni-router"],domain:["full:example.com"],outboundTag:"to-camouflage"},
        {inboundTag:["sni-router"],outboundTag:"blackhole"}
      ]}
    }' > "$work/server.json"

check_config() { "$xray_bin" run -test -c "$1" > "$work/config-test.log" 2>&1; }
check_config "$work/server.json"
printf '[PASS] E2-config redirect, PROXY v2 and XHTTP encryption accepted\n'
jq '.inbounds[1].protocol="tunnel"' "$work/server.json" > "$work/tunnel.json"
check_config "$work/tunnel.json"
printf '[PASS] E11-config dokodemo-door and tunnel accepted\n'
jq '.inbounds[1].streamSettings.sockopt.pocUnknownField=true' "$work/server.json" > "$work/unknown.json"
check_config "$work/unknown.json"
printf '[PASS] decoder-negative-control unknown field silently accepted; -test alone is insufficient\n'
jq '.outbounds[1].settings.proxyProtocol="invalid"' "$work/server.json" > "$work/invalid.json"
if check_config "$work/invalid.json"; then
    printf '[FAIL] known invalid field was accepted\n'; exit 1
fi
printf '[PASS] decoder-positive-control known field with wrong type rejected\n'

start_xray() {
    "$xray_bin" run -c "$1" > "$work/xray.log" 2>&1 &
    xray_pid=$!
    pids+=("$xray_pid")
    for ((i=0; i<100; i++)); do
        kill -0 "$xray_pid"
        ready=true
        for port in "$front" "$router" "$backend" "$camouflage"; do
            if [[ -z $(ss -Hltn "sport = :$port") ]]; then ready=false; break; fi
        done
        if "$ready"; then return 0; fi
        sleep 0.05
    done
    printf '[FAIL] process did not listen\n'; return 1
}

request() {
    local source=$1 domain=$2 port=$3 ca=$4
    curl --noproxy '*' --silent --show-error --max-time 4 --interface "$source" \
        --cacert "$ca" --resolve "$domain:$port:127.0.0.1" \
        "https://$domain:$port/" -o /dev/null -w '%{http_code}' 2> "$work/curl.log"
}

for alias in dokodemo-door tunnel; do
    if [[ $alias == tunnel ]]; then config="$work/tunnel.json"; else config="$work/server.json"; fi
    start_xray "$config"
    if status=$(request 127.0.0.2 example.com "$camouflage" "$work/cam.pem"); then
        [[ $status == 404 ]]
    else
        printf '[FAIL] TLS probe; private log withheld\n' >&3
        exit 1
    fi
    [[ $(request 127.0.0.2 cdn.example.com "$front" "$work/tls.pem") == 404 ]]
    printf '[PASS] E2-E3-local %s allowed source traverses REALITY xver=2, routing.source, freedom PROXY v2, XHTTP TLS (404)\n' "$alias"
    if request 127.0.0.3 cdn.example.com "$front" "$work/tls.pem" > "$work/denied"; then
        printf '[FAIL] untrusted source accepted\n'; exit 1
    fi
    [[ $(cat "$work/denied") == 000 ]]
    printf '[PASS] E3-negative %s same CDN SNI with other source blocked\n' "$alias"
    if request 127.0.0.2 wrong.example.com "$front" "$work/tls.pem" > "$work/denied"; then
        printf '[FAIL] unknown SNI accepted\n'; exit 1
    fi
    [[ $(cat "$work/denied") == 000 ]]
    printf '[PASS] SNI-negative %s unrecognized SNI blocked\n' "$alias"
    if status=$(request 127.0.0.2 example.com "$front" "$work/cam.pem"); then
        [[ $status == 404 ]]
    else
        printf '[FAIL] local camouflage request: '
        printf '[FAIL] camouflage probe; private log withheld\n' >&3
        exit 1
    fi
    printf '[PASS] camouflage-local %s relays local TLS fixture (404, certificate verified)\n' "$alias"
    kill "$xray_pid"
    wait "$xray_pid" || true
    unset 'pids[-1]'
done

# Original proposal A: fallbacks points at B, but unauthenticated TLS hits target.
jq --argjson cam "$camouflage" --argjson backend "$backend" '
    .inbounds[0].streamSettings.realitySettings.target=("127.0.0.1:"+($cam|tostring)) |
    .inbounds[0].streamSettings.realitySettings.xver=0 |
    .inbounds[0].settings.fallbacks=[{name:"cdn.example.com",dest:$backend,xver:2}]
    ' "$work/server.json" > "$work/original-a.json"
check_config "$work/original-a.json"
start_xray "$work/original-a.json"
timeout 5 openssl s_client -connect "127.0.0.1:$front" -servername cdn.example.com \
    -CAfile "$work/cam.pem" -verify_return_error -showcerts </dev/null > "$work/peer" 2> "$work/peer.log"
openssl x509 -in "$work/peer" -outform DER > "$work/peer.der"
openssl x509 -in "$work/cam.pem" -outform DER > "$work/cam.der"
cmp -s "$work/peer.der" "$work/cam.der"
printf '[PASS] E1-local original fallbacks proposal returns target certificate for CDN SNI\n'
printf 'LOCAL_POC: PASS (real Cloudflare and authenticated client traffic remain untested)\n'
