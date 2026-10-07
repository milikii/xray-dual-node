#!/usr/bin/env bash
# Install agent-prepared files as a persistent service; the agent handles preflight and verification.
set +x
set -Eeuo pipefail
umask 077
usage() {
    cat <<'EOF'
Usage: install-runtime.sh --work-dir PREPARED_DIR --xray-dir VERIFIED_BIN_DIR
Installs agent-prepared v26.9.30 files as xray-skill.service with boot startup.
Requires root, free 443 (or the matching xray-poc.service), and no existing xray-skill runtime.
Preserves credentials and existing CF DNS. Self-signed mode gets a daily renewal check;
provided certificates require an agent-arranged renewal process. No ACME/DNS API calls.
Stops a matching transient unit only after the new configuration validates.
Does not export links or claim client connectivity; run end-to-end tests afterward.
Prepared websites require /usr/sbin/nginx; use the isolated xray-skill-web.service, not nginx.service.
EOF
}
work='' bin_dir=''
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --work-dir|--xray-dir)
            (($# >= 2)) || exit 2
            case "$1" in --work-dir) work=$2 ;; --xray-dir) bin_dir=$2 ;; esac
            shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ $EUID == 0 && $work = /* && $bin_dir = /* ]] || { usage >&2; exit 2; }
exec 3>&1 4>&2
exec 1>/dev/null 2>/dev/null
success=false old_stopped=false old_active=false switched=false website=false
finish() {
    local result=$?
    trap - EXIT
    if [[ $success != true ]]; then
        if [[ $switched == true ]]; then
            if [[ $website == true ]]; then
                systemctl disable --now xray-skill-news.timer xray-skill-web.service || true
                systemctl stop xray-skill-news.service || true
            fi
            systemctl disable --now xray-skill.service || true
        fi
        if [[ $old_stopped == true ]]; then
            systemd-run --quiet --unit=xray-poc-recovery --property=UMask=0077 \
                --property=Restart=on-failure \
                --property="StandardOutput=append:$work/recovery-process.log" \
                --property="StandardError=append:$work/recovery-process.log" \
                "$bin_dir/xray" run -format json -c "$work/server.json" || true
        fi
        printf '[FAIL] ACTIVATE: recovery failed; private source files retained\n' >&4
        ((result != 0)) || result=1
    fi
    exit "$result"
}
trap finish EXIT
trap 'printf "[FAIL] ACTIVATE: step at line %s failed; details withheld\n" "$LINENO" >&4' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec 9>/run/xray-skill.lock
flock -x 9
[[ ! -e /etc/xray-skill && ! -e /etc/systemd/system/xray-skill.service ]]
[[ $(stat -c '%u:%a' "$work") == '0:700' ]]
if [[ -f $work/prepared.json ]] && jq -e '.website==true' "$work/prepared.json"; then
    website=true
    [[ -x /usr/sbin/nginx && -f $work/website/nginx.conf && -d $work/website/site ]]
    [[ ! -e /var/www/xray-skill && ! -e /etc/systemd/system/xray-skill-web.service ]]
    [[ ! -e /var/lib/xray-skill-news && ! -e /etc/systemd/system/xray-skill-news.service && ! -e /etc/systemd/system/xray-skill-news.timer ]]
    [[ -z $(ss -Hltn 'sport = :8003') ]]
    # A prepared web topology cannot be recovered by restarting the old Xray-only PoC.
    if systemctl is-active --quiet xray-poc.service; then exit 1; fi
fi
if systemctl is-active --quiet xray-poc.service; then
    [[ $(systemctl show xray-poc.service -p ExecStart --value) == *"$work/server.json"* ]]
    old_active=true
else [[ -z $(ss -Hltn 'sport = :443') ]]; fi
[[ $("$bin_dir/xray" version) == 'Xray 26.9.30 '* ]]
"$root/scripts/check-policy.sh" "$work/server.json"
"$bin_dir/xray" run -test -format json -c "$work/server.json"
for name in xray geoip.dat geosite.dat; do [[ -s $bin_dir/$name ]]; done
if ! getent group xray-skill; then groupadd --system xray-skill; fi
if ! id -u xray-skill; then
    useradd --system --gid xray-skill --home-dir /nonexistent --shell /usr/sbin/nologin xray-skill
fi
[[ $(id -u xray-skill) != 0 ]]
install -d -m 755 /opt/xray-skill/bin/xray-v26.9.30 /opt/xray-skill/src/scripts /opt/xray-skill/src/scripts/lib
install -m 755 "$bin_dir/xray" /opt/xray-skill/bin/xray-v26.9.30/xray
install -m 644 "$bin_dir/geoip.dat" "$bin_dir/geosite.dat" /opt/xray-skill/bin/xray-v26.9.30/
ln -s /opt/xray-skill/bin/xray-v26.9.30/xray /usr/local/bin/xray-skill-xray
install -m 755 "$root/scripts/renew-selfsigned.sh" "$root/scripts/check-policy.sh" /opt/xray-skill/src/scripts/
install -d -m 750 -o root -g xray-skill /etc/xray-skill /etc/xray-skill/certs /etc/xray-skill/certs/origin
install -d -m 700 /etc/xray-skill/secrets
install -d -m 750 -o xray-skill -g xray-skill /var/log/xray-skill
install -m 640 -o root -g xray-skill "$work/tls.pem" /etc/xray-skill/certs/origin/fullchain.pem
install -m 640 -o root -g xray-skill "$work/tls.key" /etc/xray-skill/certs/origin/privkey.pem
install -m 600 "$work/client-a.json" "$work/client-b.json" /etc/xray-skill/secrets/
jq '
    .log={loglevel:"warning",access:"none",error:"/var/log/xray-skill/error.log"} |
    (.inbounds[] | select(.tag=="xhttp-in") | .streamSettings.tlsSettings.certificates)=[{
        certificateFile:"/etc/xray-skill/certs/origin/fullchain.pem",
        keyFile:"/etc/xray-skill/certs/origin/privkey.pem"}]
' "$work/server.json" > /etc/xray-skill/config.json
chown root:xray-skill /etc/xray-skill/config.json
chmod 640 /etc/xray-skill/config.json
cert_mode=self-signed
if [[ -f $work/prepared.json ]]; then cert_mode=$(jq -er '.certificate_mode|select(.=="self-signed" or .=="provided")' "$work/prepared.json"); fi
jq -n --arg mode "$cert_mode" --argjson website "$website" \
    '{kind:"agent-deployment",tag:"v26.9.30",topology:"a-prime",certificate_mode:$mode,website:$website}' \
    > /etc/xray-skill/recovery.json
if [[ $website == true ]]; then
    if ! getent group xray-news; then groupadd --system xray-news; fi
    if ! id -u xray-news; then
        useradd --system --gid xray-news --home-dir /nonexistent --shell /usr/sbin/nologin xray-news
    fi
    [[ $(id -u xray-news) != 0 && $(id -u xray-news) != "$(id -u xray-skill)" ]]
    install -d -m 755 -o xray-news -g xray-news /var/www/xray-skill /var/www/xray-skill/releases /var/www/xray-skill/releases/initial
    install -m 644 -o xray-news -g xray-news "$work/website/site/"* /var/www/xray-skill/releases/initial/
    ln -s releases/initial /var/www/xray-skill/current
    chown -h xray-news:xray-news /var/www/xray-skill/current
    install -d -m 700 -o xray-news -g xray-news /var/lib/xray-skill-news
    install -m 600 -o xray-news -g xray-news "$work/website/website.json" /var/lib/xray-skill-news/config.json
    install -m 600 -o xray-news -g xray-news "$work/website/news-cache.json" /var/lib/xray-skill-news/cache.json
    install -m 600 -o xray-news -g xray-news "$work/website/news-attempt.json" /var/lib/xray-skill-news/last-attempt.json
    install -m 644 "$root/scripts/news_site.py" /opt/xray-skill/src/scripts/
    install -m 640 -o root -g xray-skill "$work/website/nginx.conf" /etc/xray-skill/nginx.conf
    install -m 600 "$work/website/website.json" /etc/xray-skill/website.json
    install -d -m 700 -o xray-skill -g xray-skill /run/xray-skill-web
    runuser -u xray-skill -- /usr/sbin/nginx -t -q -c /etc/xray-skill/nginx.conf
    install -m 644 "$root/templates/systemd/xray-skill-web.service" \
        "$root/templates/systemd/xray-skill-news.service" "$root/templates/systemd/xray-skill-news.timer" /etc/systemd/system/
fi
"$root/scripts/check-policy.sh" /etc/xray-skill/config.json
runuser -u xray-skill -- /usr/local/bin/xray-skill-xray run -test -format json -c /etc/xray-skill/config.json
install -m 644 "$root/templates/systemd/xray-skill.service" \
    "$root/templates/systemd/xray-skill-selfsigned.service" \
    "$root/templates/systemd/xray-skill-selfsigned.timer" /etc/systemd/system/
systemctl daemon-reload
# The renewal helper takes the same lock and validates with the service user.
if [[ $cert_mode == self-signed ]]; then
    flock -u 9
    "$root/scripts/renew-selfsigned.sh" >&3 2>&4
    flock -x 9
fi
switched=true
if [[ $old_active == true ]]; then
    old_stopped=true
    systemctl stop xray-poc.service
fi
systemctl enable --now xray-skill.service
sleep 1
systemctl is-active --quiet xray-skill.service
systemctl is-enabled --quiet xray-skill.service
if [[ $website == true ]]; then
    systemctl enable --now xray-skill-web.service
    systemctl is-active --quiet xray-skill-web.service
    systemctl is-enabled --quiet xray-skill-web.service
    systemctl enable --now xray-skill-news.timer
    systemctl is-active --quiet xray-skill-news.timer
    systemctl is-enabled --quiet xray-skill-news.timer
fi
if [[ $cert_mode == self-signed ]]; then systemctl enable --now xray-skill-selfsigned.timer; fi
success=true
printf '[PASS] ACTIVATE: persistent xray-skill.service running as dedicated user; boot startup enabled\n' >&3
printf '[PASS] CERT: selected certificate mode installed; CF DNS unchanged\n' >&3
printf '[INFO] VERIFY: end-to-end client checks still required; node credentials retained\n' >&3
