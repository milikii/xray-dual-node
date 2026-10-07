#!/usr/bin/env bash
# Certbot deploy hook. Public cert validation + protected install + rollback on failure.
set +x
set -Eeuo pipefail
umask 077
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: deploy-certbot-cert.sh\nCertbot hook: reads RENEWED_LINEAGE and /etc/xray-skill/certbot.json. Root only.\n'
    exit 0
fi
[[ $# == 0 && $EUID == 0 ]] || exit 2
exec 3>&1 4>&2
exec 1>/dev/null 2>/dev/null
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec 9>/run/xray-skill.lock
flock -x 9
stage='' changed=false complete=false active=false web_active=false rollback_ok=true
finish() {
    local code=$?
    trap - EXIT
    if [[ $complete != true ]]; then
        if [[ $changed == true ]]; then
            cp -p "$stage/old.pem" /etc/xray-skill/certs/origin/fullchain.pem || rollback_ok=false
            cp -p "$stage/old.key" /etc/xray-skill/certs/origin/privkey.pem || rollback_ok=false
            cp -p "$stage/old-recovery.json" /etc/xray-skill/recovery.json || rollback_ok=false
            if [[ -f $stage/old-nginx.conf ]]; then cp -p "$stage/old-nginx.conf" /etc/xray-skill/nginx.conf || rollback_ok=false; fi
            if [[ $active == true ]]; then systemctl restart xray-skill.service || rollback_ok=false; fi
            if [[ $web_active == true ]]; then systemctl reload xray-skill-web.service || rollback_ok=false; fi
        fi
        printf '[FAIL] CERT: deploy failed; rollback_ok=%s; details withheld\n' "$rollback_ok" >&4
        code=1
    fi
    if [[ -n $stage ]]; then
        if [[ $rollback_ok == true ]]; then rm -rf -- "$stage"
        else printf '[FAIL] CERT: recovery backup retained at %s\n' "$stage" >&4; fi
    fi
    exit "$code"
}
trap finish EXIT
trap 'printf "[FAIL] CERT: deploy step at line %s failed; details withheld\n" "$LINENO" >&4' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
lineage=$(jq -er '.lineage' /etc/xray-skill/certbot.json)
[[ $lineage =~ ^/etc/letsencrypt/live/[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
if [[ ${RENEWED_LINEAGE:-} != "$lineage" ]]; then complete=true; exit 0; fi
hostname=$(jq -er '.inbounds[]|select(.tag=="xhttp-in")|.streamSettings.xhttpSettings.host' /etc/xray-skill/config.json)
"$root/scripts/check-public-cert.sh" --cert "$lineage/fullchain.pem" --key "$lineage/privkey.pem" --hostname "$hostname"
stage=$(mktemp -d /etc/xray-skill/certs/.deploy.XXXXXXXX)
cp -p /etc/xray-skill/certs/origin/fullchain.pem "$stage/old.pem"
cp -p /etc/xray-skill/certs/origin/privkey.pem "$stage/old.key"
cp -p /etc/xray-skill/recovery.json "$stage/old-recovery.json"
if [[ -f /etc/xray-skill/nginx.conf ]]; then cp -p /etc/xray-skill/nginx.conf "$stage/old-nginx.conf"; fi
if systemctl is-active --quiet xray-skill.service; then active=true; fi
if systemctl is-active --quiet xray-skill-web.service; then web_active=true; fi
install -m 640 -o root -g xray-skill "$lineage/fullchain.pem" "$stage/fullchain.pem"
install -m 640 -o root -g xray-skill "$lineage/privkey.pem" "$stage/privkey.pem"
changed=true
mv -fT "$stage/fullchain.pem" /etc/xray-skill/certs/origin/fullchain.pem
mv -fT "$stage/privkey.pem" /etc/xray-skill/certs/origin/privkey.pem
if [[ -f $stage/old-nginx.conf ]]; then
    # Replace only the known generated trust directive; unknown layouts require explicit migration.
    python3 - <<'PY'
from pathlib import Path
import os,re
p=Path('/etc/xray-skill/nginx.conf')
s=p.read_text()
pattern=r'proxy_ssl_trusted_certificate (?:/etc/xray-skill/certs/origin/fullchain\.pem|/etc/ssl/certs/ca-certificates\.crt);'
s,n=re.subn(pattern,'proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;',s)
if n!=1:raise SystemExit(1)
temp=p.with_name('.nginx-cert.conf');temp.write_text(s);temp.chmod(0o640)
os.chown(temp,p.stat().st_uid,p.stat().st_gid);os.replace(temp,p)
PY
fi
jq '.certificate_mode="provided"' /etc/xray-skill/recovery.json > "$stage/recovery.json"
install -m 600 "$stage/recovery.json" /etc/xray-skill/recovery.json
"$root/scripts/check-policy.sh" /etc/xray-skill/config.json
runuser -u xray-skill -- /usr/local/bin/xray-skill-xray run -test -format json -c /etc/xray-skill/config.json
if [[ -f /etc/xray-skill/nginx.conf ]]; then
    # systemd removes RuntimeDirectory when a website is deliberately stopped.
    if [[ ! -d /run/xray-skill-web ]]; then
        install -d -m 700 -o xray-skill -g xray-skill /run/xray-skill-web
    fi
    runuser -u xray-skill -- /usr/sbin/nginx -t -q -c /etc/xray-skill/nginx.conf
fi
if [[ $active == true ]]; then
    systemctl restart xray-skill.service
    systemctl is-active --quiet xray-skill.service
fi
if [[ $web_active == true ]]; then
    systemctl reload xray-skill-web.service
    systemctl is-active --quiet xray-skill-web.service
fi
receipt=$(openssl rand -hex 16)
jq -n --arg id "$receipt" --arg lineage "$lineage" '{deployment_id:$id,lineage:$lineage,status:"PASS"}' > "$stage/receipt.json"
install -m 600 "$stage/receipt.json" /etc/xray-skill/certbot-deploy-receipt.json
complete=true
printf '[PASS] CERT: public certificate deployed; active Xray restarted and active website reloaded\n' >&3
