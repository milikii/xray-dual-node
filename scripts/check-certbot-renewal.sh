#!/usr/bin/env bash
# Read-only status by default; --dry-run explicitly exercises Certbot and the deployment hook.
set +x
set -Eeuo pipefail
umask 077
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: check-certbot-renewal.sh [--dry-run]\nRoot only. Verify public certificate, Certbot timer, installed hook and renewal rehearsal receipt.\n--dry-run runs Certbot staging renewal and deploys the CURRENT public certificate; may restart active Xray.\n'
    exit 0
fi
dry_run=false
if [[ ${1:-} == --dry-run ]]; then dry_run=true; shift; fi
[[ $# == 0 && $EUID == 0 ]] || exit 2
exec 3>&1 4>&2
exec 1>/dev/null 2>/dev/null
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
ok=false
finish() {
    local code=$?
    rm -rf -- "$work"
    if [[ $ok != true ]]; then
        printf '[FAIL] CERT: renewal timer, certificate deployment or hook rehearsal unverified; details withheld\n' >&4
        exit 1
    fi
    exit "$code"
}
trap finish EXIT
lineage=$(jq -er '.lineage' /etc/xray-skill/certbot.json)
[[ $lineage =~ ^/etc/letsencrypt/live/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
renewal=/etc/letsencrypt/renewal/${lineage##*/}.conf
[[ -f $renewal && -x /etc/letsencrypt/renewal-hooks/deploy/xray-skill.sh ]]
cmp -s "$root/templates/certbot-deploy-hook" /etc/letsencrypt/renewal-hooks/deploy/xray-skill.sh
for name in check-public-cert.sh check-policy.sh deploy-certbot-cert.sh; do
    [[ -x /opt/xray-skill/src/scripts/$name ]]
    cmp -s "$root/scripts/$name" "/opt/xray-skill/src/scripts/$name"
done
systemctl is-enabled --quiet certbot.timer
systemctl is-active --quiet certbot.timer
if systemctl is-enabled --quiet xray-skill-selfsigned.timer || systemctl is-active --quiet xray-skill-selfsigned.timer; then exit 1; fi
jq -e '.certificate_mode=="provided"' /etc/xray-skill/recovery.json
# Bind evidence to the renewal configuration, hooks and Certbot global configuration.
fingerprint() {
    {
        sha256sum "$renewal" /etc/letsencrypt/renewal-hooks/deploy/xray-skill.sh \
            /opt/xray-skill/src/scripts/{check-public-cert.sh,check-policy.sh,deploy-certbot-cert.sh}
        if [[ -f /etc/letsencrypt/cli.ini ]]; then sha256sum /etc/letsencrypt/cli.ini; fi
    } | sha256sum | cut -d ' ' -f 1
}
fingerprint_before=$(fingerprint)
if [[ $dry_run == true ]]; then
    rm -f /etc/xray-skill/certbot-renewal-verified.json
    before=$(jq -er '.deployment_id' /etc/xray-skill/certbot-deploy-receipt.json) || before=none
    certbot renew --non-interactive --cert-name "${lineage##*/}" --dry-run --run-deploy-hooks > "$work/certbot.log" 2>&1
    after=$(jq -er --arg lineage "$lineage" 'select(.status=="PASS" and .lineage==$lineage)|.deployment_id' /etc/xray-skill/certbot-deploy-receipt.json)
    [[ $after != "$before" && -n $after && $(fingerprint) == "$fingerprint_before" ]]
fi
hostname=$(jq -er '.inbounds[]|select(.tag=="xhttp-in")|.streamSettings.xhttpSettings.host' /etc/xray-skill/config.json)
"$root/scripts/check-public-cert.sh" --cert /etc/xray-skill/certs/origin/fullchain.pem \
    --key /etc/xray-skill/certs/origin/privkey.pem --hostname "$hostname"
cmp -s "$lineage/fullchain.pem" /etc/xray-skill/certs/origin/fullchain.pem
cmp -s "$lineage/privkey.pem" /etc/xray-skill/certs/origin/privkey.pem
if [[ $dry_run == true ]]; then
    jq -n --arg fingerprint "$fingerprint_before" --arg lineage "$lineage" --arg id "$after" \
        '{status:"PASS",lineage:$lineage,fingerprint:$fingerprint,deployment_id:$id,verified_at:(now|floor)}' > "$work/receipt.json"
    install -m 600 "$work/receipt.json" /etc/xray-skill/certbot-renewal-verified.json
fi
jq -e --arg fingerprint "$fingerprint_before" --arg lineage "$lineage" \
    '.status=="PASS" and .lineage==$lineage and .fingerprint==$fingerprint and (.deployment_id|length>0)' \
    /etc/xray-skill/certbot-renewal-verified.json
ok=true
printf '[PASS] CERT: public certificate deployed; Certbot timer, hook and matching renewal rehearsal verified\n' >&3
