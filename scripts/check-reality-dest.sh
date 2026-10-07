#!/usr/bin/env bash
# Network observations only; the executing agent makes the deployment decision.
set +x
set -Eeuo pipefail
umask 077
usage() {
    cat <<'EOF'
Usage: check-reality-dest.sh [--strict] [--json] [--timeout SECONDS] [--source-ip VPS_IP] DOMAIN [DOMAIN...]
Checks DNS/TCP/TLS1.3/h2/certificates/HTTP, target exclusions, latency and stability.
ML-KEM unsupported by target or local OpenSSL is an accepted X25519 fallback (WARN).
No host changes. Prints only check IDs/results, never certificate contents.
R10 compares origin/target ASNs via RIPEstat (public IPs sent, no credentials).
Different/unknown ASNs are advisory WARN; a target resolving to the origin is FAIL.
Exit 4 on any FAIL. --strict is retained for the documented deployment invocation.
EOF
}
json=false timeout_s=5 domains=() source_ip=''
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --strict) shift ;;
        --json) json=true; shift ;;
        --timeout) (($# >= 2)) || exit 2; timeout_s=$2; shift 2 ;;
        --source-ip) (($# >= 2)) || exit 2; source_ip=$2; shift 2 ;;
        --*) usage >&2; exit 2 ;;
        *) domains+=("$1"); shift ;;
    esac
done
[[ $timeout_s =~ ^[1-9][0-9]?$ && ${#domains[@]} -gt 0 ]] || { usage >&2; exit 2; }
for dep in jq openssl curl timeout getent python3; do
    command -v "$dep" >/dev/null || { printf '[FAIL] missing target-check dependency\n' >&2; exit 3; }
done
for domain in "${domains[@]}"; do
    [[ $domain =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && $domain == *.* && $domain != *..* ]] || exit 2
done
work=$(mktemp -d)
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec 3>&2 2>"$work/errors.log"
trap 'rm -rf -- "$work"' EXIT
trap 'printf "[FAIL] target checker at line %s; details withheld\n" "$LINENO" >&3' ERR
result=$work/results.jsonl
touch "$result"
failed=false index=0
row() {
    jq -cn --argjson target "$index" --arg id "$1" --arg status "$2" --arg detail "$3" \
        '{target_index:$target,id:$id,status:$status,detail:$detail}' >> "$result"
    if [[ $2 == FAIL ]]; then failed=true; fi
}
for domain in "${domains[@]}"; do
    index=$((index + 1))
    if getent ahostsv4 "$domain" > "$work/dns" && [[ -s $work/dns ]]; then
        row R01 PASS 'IPv4 resolution available'
    else row R01 FAIL 'no IPv4 address'; fi
    # $1 is expanded by the child shell, not this shell.
    # shellcheck disable=SC2016
    if timeout "$timeout_s" bash -c 'exec 5<>/dev/tcp/$1/443' _ "$domain"; then row R02 PASS 'TCP 443 reachable'; else row R02 FAIL 'TCP connection failed'; fi
    handshake=false
    if timeout "$timeout_s" openssl s_client -connect "$domain:443" -servername "$domain" \
        -tls1_3 -alpn h2,http/1.1 -verify_hostname "$domain" -verify_return_error -showcerts \
        </dev/null > "$work/tls" 2>&1; then
        # OpenSSL prints this text in both 3.0 and the tested 3.5 output formats.
        if grep -q 'TLSv1.3' "$work/tls"; then handshake=true; fi
    fi
    if [[ $handshake == true ]]; then row R03 PASS 'TLS 1.3 handshake verified'; else row R03 FAIL 'TLS 1.3 handshake/verification failed'; fi
    if [[ $handshake == true ]] && grep -q 'ALPN protocol: h2' "$work/tls"; then row R04 PASS 'ALPN h2'; else row R04 FAIL 'ALPN h2 not negotiated in a verified handshake'; fi
    if timeout "$timeout_s" openssl s_client -connect "$domain:443" -servername "$domain" \
        -tls1_3 -groups X25519MLKEM768 -verify_hostname "$domain" -verify_return_error \
        </dev/null > "$work/pq" 2>&1; then
        row R05 PASS 'target accepts X25519MLKEM768'
    else row R05 WARN 'ML-KEM unavailable in target/probe; X25519 fallback is allowed'; fi
    if [[ $handshake == true ]] && openssl x509 -in "$work/tls" -out "$work/leaf.pem" && \
        openssl x509 -in "$work/leaf.pem" -noout -checkend 604800 >/dev/null; then
        row R06 PASS 'hostname/CA verification passed; leaf validity exceeds 7 days'
    else row R06 FAIL 'certificate verification or remaining validity failed'; fi
    status=$(curl --noproxy '*' -sS --http2 --connect-timeout "$timeout_s" --max-time "$timeout_s" \
        -I "https://$domain/" -D "$work/headers" -o /dev/null -w '%{http_code}') || status=000
    case "$status" in
        2??) row R07 PASS 'HTTP HEAD returned 2xx' ;;
        3??)
            location=$(awk 'tolower($1)=="location:" {$1=""; sub(/^ /, ""); sub(/\r$/, ""); print; exit}' "$work/headers")
            if [[ $domain != www.* && ( $location == "https://www.$domain" || $location == "https://www.$domain/"* ) ]]; then
                row R07 WARN 'same-site apex-to-www redirect; recheck the final hostname if selected'
            else row R07 FAIL 'redirect outside the permitted apex-to-www case'; fi ;;
        *) row R07 FAIL 'HTTP HEAD did not return a usable 2xx/allowed redirect' ;;
    esac
    blocked=false
    case "${domain,,}" in apple.com|*.apple.com|icloud.com|*.icloud.com|*.apple|mzstatic.com|*.mzstatic.com) blocked=true ;; esac
    if openssl x509 -in "$work/leaf.pem" -noout -subject -nameopt RFC2253 > "$work/subject" 2>/dev/null; then
        if grep -Eqi '(^|,|subject=)O=(Apple|iCloud)' "$work/subject"; then blocked=true; fi
    fi
    if [[ $blocked == true ]]; then row R08 FAIL 'target matches excluded Apple/iCloud family'; else row R08 PASS 'target exclusion list not matched'; fi
    case "${domain,,}" in
        www.microsoft.com|www.lovelive-anime.jp|addons.mozilla.org|www.cloudflare.com)
            row R09 WARN 'widely reused camouflage target' ;;
        *) row R09 PASS 'not on the small known-popular list; popularity is not exhaustive' ;;
    esac
    # Include both DNS families for ASN comparison; transport probes above retain their own DNS selection.
    cp "$work/dns" "$work/asn-dns"
    getent ahostsv6 "$domain" >> "$work/asn-dns" || true
    python3 "$root/scripts/check-reality-asn.py" --source-ip "$source_ip" \
        --dns-file "$work/asn-dns" --timeout "$timeout_s" > "$work/asn-result"
    row R10 "$(jq -er '.status' "$work/asn-result")" "$(jq -er '.detail' "$work/asn-result")"
    : > "$work/times"
    : > "$work/observations"
    for ((sample=0; sample<5; sample++)); do
        if curl --noproxy '*' -sS --http2 --connect-timeout "$timeout_s" --max-time "$timeout_s" \
            -I "https://$domain/" -o /dev/null -w '%{time_appconnect}\n' > "$work/time-one" && \
            timeout "$timeout_s" openssl s_client -connect "$domain:443" -servername "$domain" \
                -tls1_3 -alpn h2,http/1.1 -verify_hostname "$domain" -verify_return_error \
                </dev/null > "$work/sample" 2>&1; then
            cat "$work/time-one" >> "$work/times"
            openssl x509 -in "$work/sample" -noout -fingerprint -sha256 >> "$work/observations"
            grep 'ALPN protocol:' "$work/sample" >> "$work/observations" || true
        fi
    done
    if [[ $(wc -l < "$work/times") == 5 ]] && median=$(sort -n "$work/times" | sed -n '3p') && \
        awk -v latency="$median" 'BEGIN {exit !(latency>0 && latency<=0.3)}'; then
        row R11 PASS "five-probe median TLS seconds=$median"
    else row R11 WARN 'probe incomplete or median TLS latency above 300 ms'; fi
    if [[ $(grep -c '^sha256 Fingerprint=' "$work/observations" || true) == 5 && \
          $(sort -u "$work/observations" | wc -l) == 2 ]]; then
        row R12 PASS 'leaf fingerprint and ALPN stable across five successful probes'
    else row R12 WARN 'handshake/certificate/ALPN observations incomplete or changing'; fi
    # DER totals provide a lower bound for the certificate list length used by the ML-DSA guidance.
    awk -v prefix="$work/chain-" '/-----BEGIN CERTIFICATE-----/{n++;file=prefix n ".pem"} file!=""{print > file} /-----END CERTIFICATE-----/{close(file);file=""}' "$work/tls"
    bytes=0
    for pem in "$work"/chain-*.pem; do
        [[ -f $pem ]] || continue
        if openssl x509 -in "$pem" -outform DER -out "$work/der"; then bytes=$((bytes + $(wc -c < "$work/der"))); fi
        rm -f -- "$pem"
    done
    if ((bytes>3500)); then row R13 PASS "ML-DSA certificate-size prerequisite met; DER bytes=$bytes"; else row R13 WARN 'ML-DSA certificate-size prerequisite not established; use mldsa off'; fi
    rm -f "$work/leaf.pem"
done
if [[ $json == true ]]; then jq -s . "$result"; else
    jq -r '"[\(.status)] \(.id) target=\(.target_index) :: \(.detail)"' "$result"
    if [[ $failed == true ]]; then printf 'RESULT: FAIL\n'; else printf 'RESULT: PASS\n'; fi
fi
[[ $failed == false ]] || exit 4
