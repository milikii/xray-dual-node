#!/usr/bin/env bash
# Bind an existing Certbot lineage to this runtime without regenerating node credentials.
set +x
set -Eeuo pipefail
umask 077
usage() { printf 'Usage: configure-certbot-renewal.sh --lineage /etc/letsencrypt/live/CERT_NAME\nInstalls the deploy hook, applies a public certificate, enables certbot.timer. Root only.\nThen run check-certbot-renewal.sh --dry-run to verify issuance AND deployment.\n'; }
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
[[ $# == 2 && $1 == --lineage && $EUID == 0 ]] || { usage >&2; exit 2; }
lineage=$2
[[ $lineage =~ ^/etc/letsencrypt/live/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 2
exec 3>&1 4>&2
exec 1>/dev/null 2>/dev/null
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
complete=false stage='' rollback_ok=true
targets=(/etc/xray-skill/certbot.json /etc/letsencrypt/renewal-hooks/deploy/xray-skill.sh)
for name in check-public-cert.sh check-policy.sh deploy-certbot-cert.sh; do
    targets+=("/opt/xray-skill/src/scripts/$name")
done
finish() {
    local code=$? i
    trap - EXIT
    if [[ $complete != true ]]; then
        if [[ -n $stage ]]; then
            for i in "${!targets[@]}"; do
                if [[ -f $stage/$i ]]; then cp -p "$stage/$i" "${targets[$i]}" || rollback_ok=false
                elif [[ -f $stage/$i.absent ]]; then rm -f -- "${targets[$i]}" || rollback_ok=false; fi
            done
        fi
        printf '[FAIL] CERT: renewal setup failed; rollback_ok=%s; details withheld\n' "$rollback_ok" >&4
        code=1
    fi
    if [[ -n $stage ]]; then
        if [[ $rollback_ok == true ]]; then rm -rf -- "$stage"
        else printf '[FAIL] CERT: setup recovery backup retained at %s\n' "$stage" >&4; fi
    fi
    exit "$code"
}
trap finish EXIT
trap 'printf "[FAIL] CERT: setup step at line %s failed; details withheld\n" "$LINENO" >&4' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
command -v certbot
[[ -f /etc/xray-skill/config.json && -f /etc/xray-skill/recovery.json ]]
[[ -f /etc/letsencrypt/renewal/${lineage##*/}.conf ]]
hostname=$(jq -er '.inbounds[]|select(.tag=="xhttp-in")|.streamSettings.xhttpSettings.host' /etc/xray-skill/config.json)
"$root/scripts/check-public-cert.sh" --cert "$lineage/fullchain.pem" --key "$lineage/privkey.pem" --hostname "$hostname"
stage=$(mktemp -d /etc/xray-skill/.certbot-setup.XXXXXXXX)
for i in "${!targets[@]}"; do
    if [[ -e ${targets[$i]} ]]; then cp -p "${targets[$i]}" "$stage/$i"
    else touch "$stage/$i.absent"; fi
done
install -d -m 755 /opt/xray-skill/src/scripts /etc/letsencrypt/renewal-hooks/deploy
for name in check-public-cert.sh check-policy.sh deploy-certbot-cert.sh; do
    if [[ $(readlink -f "$root/scripts/$name") != "/opt/xray-skill/src/scripts/$name" ]]; then
        install -m 755 "$root/scripts/$name" /opt/xray-skill/src/scripts/
    fi
done
jq -n --arg lineage "$lineage" '{lineage:$lineage}' > "$stage/certbot.json"
install -m 600 "$stage/certbot.json" /etc/xray-skill/certbot.json
install -m 755 "$root/templates/certbot-deploy-hook" /etc/letsencrypt/renewal-hooks/deploy/xray-skill.sh
systemctl enable --now certbot.timer
systemctl is-enabled --quiet certbot.timer
systemctl is-active --quiet certbot.timer
# Do not hold the runtime lock here: the hook acquires it itself.
RENEWED_LINEAGE=$lineage /opt/xray-skill/src/scripts/deploy-certbot-cert.sh >&3 2>&4
# The certificate transaction succeeded. Keep the public certificate even if legacy cleanup fails.
complete=true
rm -f /etc/xray-skill/certbot-renewal-verified.json
if systemctl cat xray-skill-selfsigned.timer; then
    systemctl disable --now xray-skill-selfsigned.timer
fi
if systemctl is-active --quiet xray-skill-selfsigned.service; then
    systemctl stop xray-skill-selfsigned.service
fi
printf '[PASS] CERT: public certificate and deploy hook installed; certbot.timer enabled/active\n' >&3
printf '[INFO] CERT: renewal dry-run with deploy hooks still required\n' >&3
