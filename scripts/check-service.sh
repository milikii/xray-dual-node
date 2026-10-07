#!/usr/bin/env bash
set +x
set -Eeuo pipefail
umask 077
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: check-service.sh [--json]\n'
    printf 'Inspect installed service and run temporary same-core A/B authentication probes. No credentials printed.\n'
    printf 'Leaves the server running; only temporary test clients/files are cleaned up. Requires root.\n'
    exit 0
fi
json=false
if [[ ${1:-} == --json ]]; then json=true; shift; fi
[[ $# == 0 && $EUID == 0 ]] || { printf '[FAIL] root required; unsupported arguments\n' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d /run/xray-skill-check.XXXXXXXX)
exec 3>&1 4>&2
exec 1>/dev/null 2>"$work/errors.log"
trap 'rm -rf -- "$work"' EXIT
trap 'printf "[FAIL] service inspection at line %s; details withheld\n" "$LINENO" >&4' ERR
failed=false
row() {
    jq -cn --arg id "$1" --arg status "$2" --arg detail "$3" '{id:$id,status:$status,detail:$detail}' >> "$work/results"
    if [[ $2 == FAIL ]]; then failed=true; fi
}
if systemctl is-active --quiet xray-skill.service && systemctl is-enabled --quiet xray-skill.service && \
    [[ $(systemctl show xray-skill.service -p RuntimeMaxUSec --value) == infinity ]]; then
    row S01 PASS 'persistent service active/enabled, no runtime deadline'
else row S01 FAIL 'service inactive, disabled, or time-limited'; fi
if [[ $(systemctl show xray-skill.service -p User --value) == xray-skill ]]; then row S02 PASS 'dedicated service user'; else row S02 FAIL 'unexpected service user'; fi
expected_tag=$(jq -er '.tag' /etc/xray-skill/recovery.json) || expected_tag=unavailable
core_version=$(/usr/local/bin/xray-skill-xray version) || core_version=unavailable
if [[ $expected_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && $core_version == "Xray ${expected_tag#v} "* ]]; then
    row V03 PASS 'running core version matches recorded tag'
else row V03 FAIL 'core version differs from recorded tag'; fi
if /usr/local/bin/xray-skill-xray run -test -format json -c /etc/xray-skill/config.json && \
    "$root/scripts/check-policy.sh" /etc/xray-skill/config.json; then
    row S03 PASS 'core accepts config; REALITY fallback limit fields absent'
else row S03 FAIL 'config or no-throttling policy failed'; fi
if ss -Hltn 'sport = :8001 or sport = :8002' | awk '
    {if ($4!="127.0.0.1:8001" && $4!="127.0.0.1:8002") bad=1; n++} END {exit !(n==2 && !bad)}'; then
    row S04 PASS 'internal listeners restricted to loopback'
else row S04 FAIL 'internal listeners missing or exposed'; fi
website=false
if jq -e '.website==true' /etc/xray-skill/recovery.json; then
    website=true
    if systemctl is-active --quiet xray-skill-web.service && systemctl is-enabled --quiet xray-skill-web.service && \
        ss -Hltn 'sport = :8003' | awk '{if ($4!="127.0.0.1:8003") bad=1; n++} END {exit !(n==1 && !bad)}' && \
        runuser -u xray-skill -- /usr/sbin/nginx -t -q -c /etc/xray-skill/nginx.conf; then
        row W01 PASS 'isolated website service enabled/active, loopback TLS listener and config valid'
    else row W01 FAIL 'website service/config/listener check failed'; fi
    if systemctl is-active --quiet xray-skill-news.timer && systemctl is-enabled --quiet xray-skill-news.timer && \
        [[ $(systemctl show xray-skill-news.service -p User --value) == xray-news ]]; then
        row W02 PASS 'AI feed update timer enabled/active with a separate user'
    else row W02 FAIL 'AI feed update timer or service user not configured'; fi
fi
if openssl x509 -in /etc/xray-skill/certs/origin/fullchain.pem -noout -checkend 1209600; then
    row C02 PASS 'origin certificate has more than 14 days remaining'
else row C02 FAIL 'origin certificate missing, invalid or near expiry'; fi
if jq -e '.certificate_mode=="self-signed"' /etc/xray-skill/recovery.json; then
    if systemctl is-enabled --quiet xray-skill-selfsigned.timer && systemctl is-active --quiet xray-skill-selfsigned.timer; then
        row C03 PASS 'self-signed renewal timer enabled/active'
    else row C03 FAIL 'self-signed renewal timer missing or inactive'; fi
else row C03 WARN 'provided certificate: agent must verify external CA renewal'; fi
if [[ $failed == false ]]; then
    cp /etc/xray-skill/config.json "$work/server.json"
    cp /etc/xray-skill/secrets/client-a.json /etc/xray-skill/secrets/client-b.json "$work/"
    chmod 600 "$work"/*.json
    if "$root/tools/poc/check-live-auth.sh" --xray /usr/local/bin/xray-skill-xray --work-dir "$work" > "$work/auth-result" 2>&1; then
        row V05-V09 PASS 'A/B same-core proxy requests and wrong-credential controls passed'
    else row V05-V09 FAIL 'A/B proxy or credential controls failed; private details withheld'; fi
    cdn=$(jq -er '.inbounds[]|select(.tag=="xhttp-in")|.streamSettings.xhttpSettings.host' /etc/xray-skill/config.json)
    if [[ $website == true ]]; then website_snapshot=$(readlink -f /var/www/xray-skill/current); fi
    status=$(curl --noproxy '*' -sS --connect-timeout 5 --max-time 15 -o "$work/homepage" -w '%{http_code}' "https://$cdn/") || status=000
    if [[ $website == true ]]; then
        if [[ $status == 200 ]] && cmp -s "$work/homepage" "$website_snapshot/index.html"; then
            row V14 PASS 'Cloudflare serves the installed static homepage'
        else row V14 FAIL 'CDN homepage differs, fails, or is replaced by a challenge'; fi
    elif [[ $status == 404 ]]; then row V14 PASS 'Cloudflare origin responds with expected XHTTP 404'; else row V14 FAIL "unexpected CDN root HTTP status=$status"; fi
    timeout 5 openssl s_client -connect 127.0.0.1:443 -servername "$cdn" </dev/null > "$work/direct" 2>&1 || true
    if grep -q 'BEGIN CERTIFICATE' "$work/direct"; then row V13 FAIL 'non-CF direct CDN SNI receives a certificate'; else row V13 PASS 'non-CF direct CDN SNI does not receive origin certificate'; fi
else row V05-V09 WARN 'network probes not run because service prerequisites failed'; fi
if [[ $json == true ]]; then jq -s . "$work/results" >&3; else
    jq -r '"[\(.status)] \(.id) \(.detail)"' "$work/results" >&3
fi
[[ $failed == false ]] || exit 7
