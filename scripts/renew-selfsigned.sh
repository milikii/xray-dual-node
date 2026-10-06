#!/usr/bin/env bash
# Only for an explicitly selected self-signed origin; not ACME/Full (Strict).
set +x
set -Eeuo pipefail
umask 077
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: renew-selfsigned.sh\n'
    printf 'Renew selected self-signed origin certificates below 30 days, retaining the key.\n'
    printf 'Requires recovery.json certificate_mode=self-signed. Tests config before restarting; errors stay private.\n'
    exit 0
fi
[[ $# == 0 && $EUID == 0 ]] || { printf '[FAIL] CERT: root required; no arguments accepted\n' >&2; exit 2; }
exec 3>&1 4>&2
exec 1>/dev/null 2>/dev/null
stage='' replaced=false active=false success=false
cert=/etc/xray-skill/certs/origin/fullchain.pem
key=/etc/xray-skill/certs/origin/privkey.pem
finish() {
    local result=$?
    trap - EXIT
    if [[ $success != true ]]; then
        if [[ $replaced == true ]]; then
            cp -p -- "$stage/previous.pem" "$cert"
            if [[ $active == true ]]; then systemctl restart xray-skill.service || true; fi
        fi
        printf '[FAIL] CERT: renewal failed; details withheld\n' >&4
        ((result != 0)) || result=5
    fi
    if [[ -n $stage ]]; then rm -rf -- "$stage"; fi
    exit "$result"
}
trap finish EXIT
trap 'printf "[FAIL] CERT: step at line %s failed; details withheld\n" "$LINENO" >&4' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
exec 9>/run/xray-skill.lock
flock -x 9
jq -e '.certificate_mode=="self-signed"' /etc/xray-skill/recovery.json
[[ -f $cert && ! -L $cert && -f $key && ! -L $key ]]
if openssl x509 -in "$cert" -noout -checkend 2592000; then
    success=true
    printf '[PASS] CERT: self-signed origin has more than 30 days remaining\n' >&3
    exit 0
fi
stage=$(mktemp -d /etc/xray-skill/certs/origin/.renew.XXXXXXXX)
cp -p -- "$cert" "$stage/previous.pem"
# Values go directly to a private OpenSSL config, never argv or stdout.
jq -er '
    [.inbounds[] | select(.tag=="xhttp-in") | .streamSettings.xhttpSettings.host] |
    select(length==1) | .[0] | select(test("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$")) |
    "[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=extensions\n"+
    "[dn]\nCN="+.+"\n[extensions]\nsubjectAltName=DNS:"+.+"\n"
' /etc/xray-skill/config.json > "$stage/openssl.cnf"
openssl req -new -x509 -sha256 -key "$key" -days 365 \
    -config "$stage/openssl.cnf" -out "$stage/new.pem"
openssl x509 -in "$stage/new.pem" -noout -checkend 2592000
openssl verify -CAfile "$stage/new.pem" "$stage/new.pem"
chown root:xray-skill "$stage/new.pem"
chmod 640 "$stage/new.pem"
if systemctl is-active --quiet xray-skill.service; then active=true; fi
mv -fT "$stage/new.pem" "$cert"
replaced=true
runuser -u xray-skill -- /usr/local/bin/xray-skill-xray run -test -format json -c /etc/xray-skill/config.json
if [[ $active == true ]]; then
    systemctl restart xray-skill.service
    systemctl is-active --quiet xray-skill.service
fi
success=true
printf '[PASS] CERT: self-signed origin renewed for 365 days; existing key retained\n' >&3
