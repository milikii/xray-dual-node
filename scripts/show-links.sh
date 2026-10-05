#!/usr/bin/env bash
# No credentials in argv or tool-visible output, including on failure.
set +x
set -Eeuo pipefail
umask 077
usage() {
    cat <<'EOF'
Usage: xrayctl show-links [--client-a FILE] [--client-b FILE] [--output-dir DIR]
                          [--xray BIN] [--json]
Reads private Xray client JSON files (one node-a / node-b outbound each).
Defaults: /etc/xray-skill/secrets/client-a.json, /etc/xray-skill/secrets/client-b.json;
          output directory /etc/xray-skill/client
Writes links.txt (exactly A then B), node-a.json and node-b.json (full clients).
Only paths/status reach stdout. Never prints links, credentials, QR or raw errors.
Inputs must be owned by the current user, mode 600, in mode 700 directories.
Output is mode 700/600, outside this repository; no symlink components allowed.
Optional --xray validates both JSON clients before publication, without starting them.
URI fields are source-reviewed; GUI import compatibility remains untested.
EOF
}
a=/etc/xray-skill/secrets/client-a.json b=/etc/xray-skill/secrets/client-b.json
output=/etc/xray-skill/client xray_bin='' json=false
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --json) json=true; shift ;;
        --client-a|--client-b|--output-dir|--xray)
            (($# >= 2)) || { printf '[FAIL] missing option value\n' >&2; exit 2; }
            case "$1" in
                --client-a) a=$2 ;; --client-b) b=$2 ;;
                --output-dir) output=$2 ;; --xray) xray_bin=$2 ;;
            esac
            shift 2 ;;
        *) printf '[FAIL] unsupported export option; use --help\n' >&2; exit 2 ;;
    esac
done

# Only explicit, constant diagnostic messages can use these descriptors.
exec 3>&1 4>&2
exec 1>/dev/null 2>/dev/null
stage='' completed=false
cleanup() {
    local result=$?
    trap - EXIT
    if [[ -n $stage ]]; then rm -rf -- "$stage"; fi
    if [[ $completed != true ]]; then
        printf '[FAIL] EXPORT: private export failed; check paths, permissions, schema or core locally; details withheld\n' >&4
        ((result != 0)) || result=1
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for dep in jq stat realpath flock mktemp; do command -v "$dep"; done
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

safe_path() {
    # A restricted path alphabet also prevents newline/control injection in status.
    [[ $1 =~ ^/[a-zA-Z0-9_./-]+$ && $1 != / && $1 != */ ]]
    [[ $(realpath -ms -- "$1") == "$1" ]]
    local part=$1 owner mode
    while [[ $part != / ]]; do
        [[ ! -L $part ]]
        if [[ -e $part ]]; then
            owner=$(stat -c %u -- "$part")
            [[ $owner == 0 || $owner == "$EUID" ]]
            mode=$(stat -c %a -- "$part")
            # Root-owned sticky /tmp is permitted; private leaf directories are checked below.
            if (( (8#$mode & 0022) != 0 )); then
                [[ -d $part && $owner == 0 ]] && (( (8#$mode & 01000) != 0 ))
            fi
        fi
        part=$(dirname -- "$part")
    done
}
private_file() {
    [[ -f $1 && ! -L $1 && $(stat -c '%u:%a:%h' -- "$1") == "$EUID:600:1" ]]
}
private_dir() {
    [[ -d $1 && ! -L $1 && $(stat -c '%u:%a' -- "$1") == "$EUID:700" ]]
}
for source in "$a" "$b"; do
    safe_path "$source"
    private_file "$source"
    private_dir "$(dirname -- "$source")"
done
safe_path "$output"
[[ $output != "$root" && $output != "$root/"* ]]
mkdir -p -- "$output"
private_dir "$output"
for name in links.txt node-a.json node-b.json .export.lock; do
    if [[ -e $output/$name || -L $output/$name ]]; then private_file "$output/$name"; fi
    [[ $a != "$output/$name" && $b != "$output/$name" ]]
done
exec 9>"$output/.export.lock"
flock -x 9
stage=$(mktemp -d "$output/.export.XXXXXXXX")
# Parse credentials only inside jq; error text is discarded, never echoed by traps.
jq -e -n -L "$root/scripts/lib" --slurpfile a "$a" --slurpfile b "$b" '
    include "links";
    if ($a|length)==1 and ($b|length)==1 then
        {a: ($a[0]|node("a")), b: ($b[0]|node("b"))}
    else error("one JSON document required") end
' > "$stage/pair.json"
jq -er -L "$root/scripts/lib" 'include "links"; uri(.a;"a"), uri(.b;"b")' \
    "$stage/pair.json" > "$stage/links.txt"
[[ $(wc -l < "$stage/links.txt") == 2 ]]
for node in a b; do
    jq -e --arg node "$node" -L "$root/scripts/lib" 'include "links"; .[$node] | full_client' \
        "$stage/pair.json" > "$stage/node-$node.json"
    if [[ -n $xray_bin ]]; then
        [[ $xray_bin = /* && -x $xray_bin ]]
        "$xray_bin" run -test -format json -c "$stage/node-$node.json"
    fi
done
# The links file is the commit point. Complete renders/tests precede any replacement.
for name in node-a.json node-b.json links.txt; do
    chmod 600 "$stage/$name"
    mv -fT -- "$stage/$name" "$output/$name"
done
if [[ $json == true ]]; then
    jq -cn --arg dir "$output" '{status:"PASS",links:2,links_file:($dir+"/links.txt"),
        client_a_file:($dir+"/node-a.json"),client_b_file:($dir+"/node-b.json"),
        gui_import:"untested"}' >&3
else
    printf '[PASS] EXPORT: 2 links; mode=600; file=%s/links.txt\n' "$output" >&3
    printf '[PASS] JSON: %s/node-a.json ; %s/node-b.json\n' "$output" "$output" >&3
    printf '[WARN] COMPAT: GUI import untested; private JSON clients are included\n' >&3
fi
completed=true
