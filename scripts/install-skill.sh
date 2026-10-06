#!/usr/bin/env bash
set -Eeuo pipefail
usage() {
    printf 'Usage: install-skill.sh [--project DIRECTORY] [--force]\n'
    printf 'Link this skill into both Codex and Claude skill directories. Default: current user.\n'
    printf 'Existing identical links are retained. --force moves conflicts to timestamped backups.\n'
}
base=${HOME:?} force=false
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --force) force=true; shift ;;
        --project) (($# >= 2)) || exit 2; base=$2; shift 2 ;;
        *) usage >&2; exit 2 ;;
    esac
done
[[ -d $base ]] || { printf '[FAIL] installation base directory does not exist\n' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
base=$(cd -- "$base" && pwd -P)
targets=("$base/.agents/skills/xray-dual-node" "$base/.claude/skills/xray-dual-node")
# Check both destinations before any replacement, so a conflict cannot produce a half install.
for target in "${targets[@]}"; do
    if [[ -L $target && $(readlink -f -- "$target") == "$root" ]]; then continue; fi
    if [[ -e $target || -L $target ]]; then
        [[ $force == true ]] || { printf '[FAIL] existing skill; use --force to preserve it as a backup\n' >&2; exit 1; }
    fi
done
for target in "${targets[@]}"; do
    if [[ -L $target && $(readlink -f -- "$target") == "$root" ]]; then
        printf '[PASS] already installed: %s\n' "$target"
        continue
    fi
    mkdir -p -- "$(dirname -- "$target")"
    if [[ -e $target || -L $target ]]; then
        backup=$(mktemp -d "${target}.backup.XXXXXXXX")
        mv -- "$target" "$backup/previous"
        printf '[INFO] previous skill preserved: %s/previous\n' "$backup"
    fi
    ln -s -- "$root" "$target"
    printf '[PASS] installed: %s\n' "$target"
done
