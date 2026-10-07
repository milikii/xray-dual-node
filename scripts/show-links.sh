#!/usr/bin/env bash
# No credentials in argv or tool-visible output, including on failure.
set +x
set -Eeuo pipefail
umask 077
usage() {
    cat <<'EOF'
Usage: xrayctl show-links --country CODE --provider NAME
                          [--client-a FILE] [--client-b FILE] [--output-dir DIR]
                          [--xray BIN] [--json]
Reads private Xray client JSON files (one node-a / node-b outbound each).
Agent supplies the origin IP's verified country code and provider (e.g. US, oracle).
Names: CODE-provider-reality and CODE-provider-xhttp+tls+cdn; no network lookup here.
Defaults: /etc/xray-skill/secrets/client-a.json, /etc/xray-skill/secrets/client-b.json;
          output directory is the current working directory
Writes links.txt (exactly A then B), node-a.json and node-b.json (full clients).
Only paths/status reach stdout. Never prints links, credentials, QR or raw errors.
Inputs must be owned by the current user, mode 600, in mode 700 directories.
Files are mode 600; current directory permissions are preserved (no group/other writes).
Other output directories must be mode 700. No symlink components allowed.
Exports inside this repository must be ignored by Git and untracked.
Optional --xray validates both JSON clients before publication, without starting them.
URI fields are source-reviewed; GUI import compatibility remains untested.
EOF
}
a=/etc/xray-skill/secrets/client-a.json b=/etc/xray-skill/secrets/client-b.json
output=$PWD xray_bin='' json=false country='' provider=''
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --json) json=true; shift ;;
        --client-a|--client-b|--output-dir|--xray|--country|--provider)
            (($# >= 2)) || { printf '[FAIL] missing option value\n' >&2; exit 2; }
            case "$1" in
                --client-a) a=$2 ;; --client-b) b=$2 ;;
                --output-dir) output=$2 ;; --xray) xray_bin=$2 ;;
                --country) country=$2 ;; --provider) provider=$2 ;;
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
country=${country^^}
provider=${provider,,}
[[ $country =~ ^[A-Z]{2}$ && $provider =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#provider} -le 64 ]]
name_a=$country-$provider-reality
name_b=$country-$provider-xhttp+tls+cdn
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
if [[ $output == "$root" || $output == "$root/"* ]]; then
    for name in links.txt node-a.json node-b.json .export.lock .export.probe; do
        git -C "$root" check-ignore -q -- "$output/$name"
    done
fi
mkdir -p -- "$output"
if [[ $output == "$PWD" ]]; then
    [[ -d $output && $(stat -c %u -- "$output") == "$EUID" ]]
    output_mode=$(stat -c %a -- "$output")
    (( (8#$output_mode & 0022) == 0 ))
else
    private_dir "$output"
fi
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
jq -er --arg name_a "$name_a" --arg name_b "$name_b" -L "$root/scripts/lib" \
    'include "links"; uri(.a;"a";$name_a), uri(.b;"b";$name_b)' \
    "$stage/pair.json" > "$stage/links.txt"
[[ $(wc -l < "$stage/links.txt") == 2 ]]
for node in a b; do
    node_name=$name_a
    if [[ $node == b ]]; then node_name=$name_b; fi
    jq -e --arg node "$node" --arg name "$node_name" -L "$root/scripts/lib" \
        'include "links"; .[$node] | .tag=$name | full_client' \
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
