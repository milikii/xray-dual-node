#!/usr/bin/env bash
set +x
set -Eeuo pipefail
umask 077
if [[ ${1:-} == --help ]]; then
    printf 'Usage: tests/unit/private-export.sh\nOffline Bash/jq tests with synthetic credentials; no real deployment or network.\n'
    exit 0
fi
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/xray-export-test.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
trap 'printf "[FAIL] export test line %s (artifacts withheld)\n" "$LINENO" >&2' ERR
ctl=$root/scripts/xrayctl
mkdir "$work/input"
jq -n '{outbounds:[{tag:"node-a",protocol:"vless",settings:{vnext:[{address:"203.0.113.10",port:443,
    users:[{id:"00000000-0000-0000-0000-000000000000",encryption:"none",flow:"xtls-rprx-vision"}]}]},
    streamSettings:{network:"raw",security:"reality",realitySettings:{serverName:"example.com",fingerprint:"chrome",
    password:"PRIVATE_TEST_SENTINEL",shortId:"abcdef12",spiderX:"/test?x=1&y=中文+#%",mldsa65Verify:"SIGNATURE_TEST_SENTINEL"}}}]}' \
    > "$work/input/a.json"
jq -n '{outbounds:[{tag:"node-b",protocol:"vless",settings:{vnext:[{address:"2001:db8::10",port:443,
    users:[{id:"00000000-0000-0000-0000-000000000000",encryption:"mlkem768x25519plus.TEST+/=&?#%"}]}]},
    streamSettings:{network:"xhttp",security:"tls",xhttpSettings:{host:"cdn.example.com",path:"/path?+&#%中文",mode:"packet-up"},
    tlsSettings:{serverName:"cdn.example.com",fingerprint:"chrome",alpn:["h2","http/1.1"],
    echConfigList:"cloudflare-ech.com+https://dns.example.com/dns-query?x=1&y=2"}}}]}' > "$work/input/b.json"
args=(--client-a "$work/input/a.json" --client-b "$work/input/b.json" --output-dir "$work/export")
"$ctl" show-links "${args[@]}" --json > "$work/status" 2> "$work/error"
jq -e '.status=="PASS" and .links==2 and .gui_import=="untested"' "$work/status" >/dev/null
[[ ! -s $work/error && $(wc -l < "$work/export/links.txt") == 2 ]]
[[ $(stat -c %a "$work/export") == 700 ]]
for file in links.txt node-a.json node-b.json .export.lock; do
    [[ $(stat -c '%u:%a:%h' "$work/export/$file") == "$EUID:600:1" ]]
done
leak_check() {
    ! rg -q 'vless://|PRIVATE_TEST_SENTINEL|SIGNATURE_TEST_SENTINEL|mlkem768|203\.0\.113|2001:db8|example\.com|00000000-' \
        "$work/status" "$work/error"
}
leak_check
printf '[PASS] private files, exactly two links, no credentials in stdout/stderr\n'

# Check wire parameter values against independently encoded source fields.
jq -en --rawfile uris "$work/export/links.txt" --slurpfile a "$work/input/a.json" --slurpfile b "$work/input/b.json" '
    def params: split("?")[1] | split("#")[0] | split("&") |
        map(split("=") | {key:.[0],value:.[1]}) | from_entries;
    ($uris|split("\n")) as $l | ($l[0]|params) as $pa | ($l[1]|params) as $pb |
    ($a[0].outbounds[0].streamSettings.realitySettings) as $r |
    ($b[0].outbounds[0]) as $ob |
    ($l|length)==3 and $l[2]=="" and ($l[0]|endswith("#node-a")) and ($l[1]|endswith("#node-b")) and
    ($l[1]|contains("@[2001:db8::10]:443?")) and
    $pa.pbk==($r.password|@uri) and $pa.pqv==($r.mldsa65Verify|@uri) and $pa.spx==($r.spiderX|@uri) and
    $pa.type=="tcp" and $pb.type=="xhttp" and $pb.mode=="packet-up" and
    $pb.encryption==($ob.settings.vnext[0].users[0].encryption|@uri) and
    $pb.path==($ob.streamSettings.xhttpSettings.path|@uri) and
    $pb.ech==($ob.streamSettings.tlsSettings.echConfigList|@uri) and $pb.alpn=="h2%2Chttp%2F1.1"
' >/dev/null
jq -en --slurpfile original "$work/input/a.json" --slurpfile exported "$work/export/node-a.json" '
    $original[0].outbounds==$exported[0].outbounds and
    all($exported[0].inbounds[]; .listen=="127.0.0.1") and
    $exported[0].log=={loglevel:"warning"}
' >/dev/null
cp "$work/export/links.txt" "$work/saved"
"$ctl" show-links "${args[@]}" > "$work/status" 2> "$work/error"
cmp -s "$work/saved" "$work/export/links.txt"
leak_check
printf '[PASS] IPv6, escaping, PQ/ECH fields, JSON preservation and stable re-export\n'

negative_case=0
must_fail() {
    negative_case=$((negative_case + 1))
    if "$@" > "$work/status" 2> "$work/error"; then
        printf '[FAIL] expected rejected export in case %s\n' "$negative_case" >&2; exit 1
    fi
    leak_check
    cmp -s "$work/saved" "$work/export/links.txt"
}
cp "$work/input/a.json" "$work/input/original.json"
printf '{"PRIVATE_TEST_SENTINEL": broken}\n' > "$work/input/a.json"
must_fail "$ctl" show-links "${args[@]}"
cp "$work/input/original.json" "$work/input/a.json"
jq '.outbounds[0].streamSettings.realitySettings.unhandled="PRIVATE_TEST_SENTINEL"' "$work/input/original.json" > "$work/input/a.json"
must_fail "$ctl" show-links "${args[@]}"
cp "$work/input/original.json" "$work/input/a.json"
chmod 644 "$work/input/a.json"
must_fail "$ctl" show-links "${args[@]}"
chmod 600 "$work/input/a.json"
ln -s "$work/input/a.json" "$work/input/link.json"
must_fail "$ctl" show-links "${args[@]}" --client-a "$work/input/link.json"
ln "$work/input/a.json" "$work/input/hard.json"
must_fail "$ctl" show-links "${args[@]}"
rm "$work/input/hard.json"
ln -s "$work/export" "$work/export-alias"
must_fail "$ctl" show-links "${args[@]}" --output-dir "$work/export-alias"
mkdir "$work/bad-output"
ln -s "$work/saved" "$work/bad-output/links.txt"
must_fail "$ctl" show-links "${args[@]}" --output-dir "$work/bad-output"
must_fail "$ctl" show-links "${args[@]}" --output-dir "$root/client"
mkdir -m 755 "$work/public"
must_fail "$ctl" show-links "${args[@]}" --output-dir "$work/public"
must_fail "$ctl" show-links "${args[@]}" --qr
printf '[PASS] malformed/unsupported input and unsafe output rejected; previous links preserved\n'

cat > "$work/failing-xray" <<'EOF'
#!/usr/bin/env bash
printf 'PRIVATE_TEST_SENTINEL\n'
printf 'SIGNATURE_TEST_SENTINEL\n' >&2
exit 6
EOF
chmod 700 "$work/failing-xray"
must_fail "$ctl" show-links "${args[@]}" --xray "$work/failing-xray"
bash -x "$root/scripts/show-links.sh" "${args[@]}" > "$work/status" 2> "$work/error"
leak_check
"$ctl" show-links "${args[@]}" > "$work/status-1" 2> "$work/error-1" &
p1=$!
"$ctl" show-links "${args[@]}" > "$work/status-2" 2> "$work/error-2" &
p2=$!
wait "$p1"
wait "$p2"
cmp -s "$work/saved" "$work/export/links.txt"
[[ -z $(find "$work/export" -maxdepth 1 -type d -name '.export.*' -print -quit) ]]
printf '[PASS] core errors and shell tracing cannot print credentials; concurrent export serialized\n'

jq -n '{inbounds:[{streamSettings:{security:"reality",realitySettings:{target:"example.com:443"}}}]}' > "$work/server.json"
"$ctl" check-policy "$work/server.json" > "$work/status"
for direction in limitFallbackUpload limitFallbackDownload; do
    for rate in 0 131072; do
        jq --arg field "$direction" --argjson rate "$rate" \
            '.inbounds[0].streamSettings.realitySettings[$field]={bytesPerSec:$rate}' \
            "$work/server.json" > "$work/limited.json"
        must_fail "$ctl" check-policy "$work/limited.json"
    done
done
printf '[PASS] REALITY limit fields rejected in both directions, including zero-valued fields\n'
printf 'PRIVATE_EXPORT_TESTS: PASS\n'
