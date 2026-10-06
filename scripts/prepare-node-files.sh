#!/usr/bin/env bash
set +x
# Render private files for an agent-led deployment; never install or start a service.
set -Eeuo pipefail
umask 077
usage() {
    cat <<'EOF'
Usage: prepare-node-files.sh --xray PATH --work-dir NEW_DIR --dest DOMAIN --cdn DOMAIN --address VPS_IP
                             [--mldsa on|off] [--origin-cert FILE --origin-key FILE]
Prepare A-prime server and two clients using checksum-verified Xray v26.9.30.
The agent must first run check-reality-dest.sh; use --mldsa off if R13 is not established.
Fetches public CF IP ranges. Uses a 365-day self-signed origin certificate by default;
provide an existing matching certificate/key pair to use a public-CA certificate.
No CF token, DNS changes, ACME issuance, process startup, or firewall changes.
Server listens on 443 when explicitly started. Clients use loopback SOCKS 20808/20809.
Private output must not be committed or printed. This helper only prepares files.
EOF
}
xray_bin='' work='' dest='' cdn='' address='' mldsa=on origin_cert='' origin_key=''
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --xray|--work-dir|--dest|--cdn|--address|--mldsa|--origin-cert|--origin-key)
            (($# >= 2)) || { usage >&2; exit 2; }
            case "$1" in
                --xray) xray_bin=$2 ;;
                --work-dir) work=$2 ;;
                --dest) dest=$2 ;;
                --cdn) cdn=$2 ;;
                --address) address=$2 ;;
                --mldsa) mldsa=$2 ;;
                --origin-cert) origin_cert=$2 ;;
                --origin-key) origin_key=$2 ;;
            esac
            shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ $xray_bin = /* && -x $xray_bin && $work = /* && ! -e $work && -n $address ]] || { usage >&2; exit 2; }
[[ $mldsa == on || $mldsa == off ]] || exit 2
[[ -z $origin_cert && -z $origin_key || -f $origin_cert && -f $origin_key ]] || exit 2
for domain in "$dest" "$cdn"; do
    [[ $domain =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && $domain = *.* && $domain != *..* ]] || exit 2
done
for dep in jq curl openssl awk; do command -v "$dep" >/dev/null || exit 3; done
[[ $("$xray_bin" version) = 'Xray 26.9.30 '* ]] || exit 3
mkdir -p "$work"
chmod 700 "$work"
exec 3>&2 2>"$work/prepare-errors.log"
trap 'printf "[FAIL] prepare line %s; inspect private logs locally\n" "$LINENO" >&3' ERR

"$xray_bin" x25519 > "$work/x25519"
if [[ $mldsa == on ]]; then "$xray_bin" mldsa65 > "$work/mldsa65"; else : > "$work/mldsa65"; fi
"$xray_bin" uuid > "$work/uuid-a"
"$xray_bin" uuid > "$work/uuid-b"
"$xray_bin" vlessenc > "$work/vlessenc"
openssl rand -hex 8 > "$work/shortid"
openssl rand -hex 16 > "$work/path"
awk -F ': ' '$1=="PrivateKey" {print $2}' "$work/x25519" > "$work/private"
awk -F ': ' '$1=="Password (PublicKey)" || $1=="Password" || $1=="PublicKey" {print $2}' "$work/x25519" > "$work/public"
awk -F ': ' '$1=="Seed" {print $2}' "$work/mldsa65" > "$work/seed"
awk -F ': ' '$1=="Verify" {print $2}' "$work/mldsa65" > "$work/verify"
[[ $(wc -c < "$work/private") == 44 && $(wc -c < "$work/public") == 44 ]]
awk '/^Authentication: ML-KEM-768, Post-Quantum/ {pq=1; next} pq && /^"decryption":/ {sub(/^"decryption": /, ""); print}' \
    "$work/vlessenc" | jq -er 'select(startswith("mlkem768x25519plus."))' > "$work/decryption"
awk '/^Authentication: ML-KEM-768, Post-Quantum/ {pq=1; next} pq && /^"encryption":/ {sub(/^"encryption": /, ""); print}' \
    "$work/vlessenc" | jq -er 'select(startswith("mlkem768x25519plus."))' > "$work/encryption"
curl -fsS --max-time 20 https://www.cloudflare.com/ips-v4 > "$work/cf-v4"
curl -fsS --max-time 20 https://www.cloudflare.com/ips-v6 > "$work/cf-v6"
jq -n --rawfile v4 "$work/cf-v4" --rawfile v6 "$work/cf-v6" \
    '(($v4|split("\n"))+($v6|split("\n"))) | map(select(length>0))' > "$work/cf-ips.json"
jq -e 'length>10 and all(.[]; test("^[0-9a-fA-F.:]+/[0-9]+$"))' "$work/cf-ips.json" >/dev/null
cert_mode=self-signed
if [[ -n $origin_cert ]]; then
    cp -- "$origin_cert" "$work/tls.pem"
    cp -- "$origin_key" "$work/tls.key"
    cert_mode=provided
else
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -keyout "$work/tls.key" -out "$work/tls.pem" -days 365 -subj "/CN=$cdn" \
        -addext "subjectAltName=DNS:$cdn" > "$work/cert.log" 2>&1
fi
openssl x509 -in "$work/tls.pem" -noout -checkhost "$cdn" > "$work/cert-check.log" 2>&1
openssl x509 -in "$work/tls.pem" -noout -checkend 1209600 >> "$work/cert-check.log" 2>&1
openssl x509 -in "$work/tls.pem" -pubkey -noout > "$work/cert-public"
openssl pkey -in "$work/tls.key" -pubout > "$work/key-public" 2>> "$work/cert-check.log"
cmp -s "$work/cert-public" "$work/key-public"
jq -n --arg mode "$cert_mode" --arg mldsa "$mldsa" \
    '{certificate_mode:$mode,mldsa:$mldsa,tag:"v26.9.30",topology:"a-prime"}' > "$work/prepared.json"

jq -n --arg dest "$dest" --arg cdn "$cdn" --arg dir "$work" \
    --rawfile key "$work/private" --rawfile seed "$work/seed" \
    --rawfile a "$work/uuid-a" --rawfile b "$work/uuid-b" --rawfile sid "$work/shortid" \
    --rawfile path "$work/path" --rawfile dec "$work/decryption" --slurpfile cf "$work/cf-ips.json" '
    def trim: rtrimstr("\n");
    {log:{loglevel:"info",access:($dir+"/access.log"),error:($dir+"/error.log")},
     inbounds:[
       {tag:"reality-in",listen:"::",port:443,protocol:"vless",
        settings:{clients:[{id:($a|trim),flow:"xtls-rprx-vision",email:"poc-a"}],decryption:"none"},
        streamSettings:{network:"raw",security:"reality",realitySettings:{
          target:"127.0.0.1:8001",xver:2,serverNames:[$dest],privateKey:($key|trim),
          shortIds:[($sid|trim)],maxTimeDiff:60000,mldsa65Seed:($seed|trim)}}},
       {tag:"sni-router",listen:"127.0.0.1",port:8001,protocol:"tunnel",
        settings:{address:"127.0.0.1",port:9,network:"tcp"},
        streamSettings:{sockopt:{acceptProxyProtocol:true}},
        sniffing:{enabled:true,destOverride:["tls"],routeOnly:true}},
       {tag:"xhttp-in",listen:"127.0.0.1",port:8002,protocol:"vless",
        settings:{clients:[{id:($b|trim),email:"poc-b"}],decryption:($dec|trim)},
        streamSettings:{network:"xhttp",security:"tls",
          xhttpSettings:{host:$cdn,path:("/"+($path|trim)),mode:"packet-up"},
          tlsSettings:{alpn:["h2","http/1.1"],minVersion:"1.2",certificates:[{
            certificateFile:($dir+"/tls.pem"),keyFile:($dir+"/tls.key")}]},
          sockopt:{acceptProxyProtocol:true,trustedXForwardedFor:["CF-Connecting-IP"]}}}
     ],outbounds:[
       {tag:"direct",protocol:"freedom"},
       {tag:"to-node-b",protocol:"freedom",settings:{redirect:"127.0.0.1:8002",proxyProtocol:2}},
       {tag:"to-camouflage",protocol:"freedom",settings:{redirect:($dest+":443")}},
       {tag:"blackhole",protocol:"blackhole"}
     ],routing:{domainStrategy:"AsIs",rules:[
       {inboundTag:["sni-router"],domain:[("full:"+$cdn)],source:$cf[0],outboundTag:"to-node-b"},
       {inboundTag:["sni-router"],domain:[("full:"+$dest)],outboundTag:"to-camouflage"},
       {inboundTag:["sni-router"],outboundTag:"blackhole"},
       {inboundTag:["reality-in","xhttp-in"],ip:["geoip:private"],outboundTag:"blackhole"}
     ]}}
    | if ($seed|trim)=="" then del(.inbounds[0].streamSettings.realitySettings.mldsa65Seed) else . end
    ' > "$work/server.json"

jq -n --arg address "$address" --arg dest "$dest" --arg dir "$work" \
    --rawfile uuid "$work/uuid-a" --rawfile pub "$work/public" --rawfile verify "$work/verify" --rawfile sid "$work/shortid" '
    def trim: rtrimstr("\n");
    {log:{loglevel:"info",error:($dir+"/client-a.log")},
     inbounds:[{tag:"socks",listen:"127.0.0.1",port:20808,protocol:"socks",settings:{udp:false}}],
     outbounds:[{tag:"node-a",protocol:"vless",settings:{vnext:[{address:$address,port:443,
       users:[{id:($uuid|trim),flow:"xtls-rprx-vision",encryption:"none"}]}]},
       streamSettings:{network:"raw",security:"reality",realitySettings:{
         serverName:$dest,fingerprint:"chrome",password:($pub|trim),shortId:($sid|trim),
         spiderX:"/poc",mldsa65Verify:($verify|trim)}}}]}
    | if ($verify|trim)=="" then del(.outbounds[0].streamSettings.realitySettings.mldsa65Verify) else . end
    ' > "$work/client-a.json"
jq -n --arg cdn "$cdn" --arg dir "$work" --rawfile uuid "$work/uuid-b" \
    --rawfile enc "$work/encryption" --rawfile path "$work/path" '
    def trim: rtrimstr("\n");
    {log:{loglevel:"info",error:($dir+"/client-b.log")},
     inbounds:[{tag:"socks",listen:"127.0.0.1",port:20809,protocol:"socks",settings:{udp:false}}],
     outbounds:[{tag:"node-b",protocol:"vless",settings:{vnext:[{address:$cdn,port:443,
       users:[{id:($uuid|trim),encryption:($enc|trim)}]}]},
       streamSettings:{network:"xhttp",security:"tls",
         xhttpSettings:{host:$cdn,path:("/"+($path|trim)),mode:"packet-up"},
         tlsSettings:{serverName:$cdn,fingerprint:"chrome",alpn:["h2","http/1.1"],
           echConfigList:"cloudflare-ech.com+https://223.5.5.5/dns-query"}}}]}
    ' > "$work/client-b.json"
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/check-policy.sh" "$work/server.json"
for config in server client-a client-b; do
    "$xray_bin" run -test -c "$work/$config.json" > "$work/$config.test.log" 2>&1
    printf '[PASS] %s config test\n' "$config"
done
printf 'PREPARE: PASS (private files only; no services started)\n'
