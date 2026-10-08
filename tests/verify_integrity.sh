#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="Dicklesworthstone/system_resource_protection_script"
# Exercise the actual pure URL parser without running the verifier's I/O.
parser_file="$(mktemp "${TMPDIR:-/tmp}/srps-verify-parser.XXXXXX")"
sed -n '/^latest_tag_from_url() {/,/^}/p' "$ROOT/verify.sh" > "$parser_file"
# shellcheck disable=SC1090
. "$parser_file"
printf 'Parser source retained in %s\n' "$parser_file"
prefix="https://github.com/${REPO}/releases/tag/"
for invalid in '' 'https://example.invalid/releases/tag/v1.4.2' "$prefix" \
    "${prefix}v1.4.2?wrong=1" "${prefix}v1.4.2#fragment" \
    "${prefix}../main" "${prefix}release/" "${prefix}v1.4.2 wrong"; do
    if latest_tag_from_url "$invalid"; then
        printf '%s\n' '{"test":"latest_url_parser","result":"fail","reason":"malformed URL accepted"}'
        exit 1
    fi
done
for tag in v1.4.2 v1.5.0-rc.1 release/v2.0.0; do
    [ "$(latest_tag_from_url "${prefix}${tag}")" = "$tag" ]
done
printf '%s\n' '{"test":"latest_url_parser","result":"pass","rejected":8,"preserved":3}'

# GitHub controls stable-release eligibility; a tag's spelling does not.
if [ "${SRPS_REAL_NETWORK_TESTS:-0}" != "1" ]; then
    printf '%s\n' '{"test":"real_latest_verification","result":"not_run","reason":"set SRPS_REAL_NETWORK_TESTS=1"}'
    exit 0
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/srps-verify-e2e.XXXXXX")"
mkdir "$scratch/latest" "$scratch/network-failure"
# Retain all verifier scratch instead of invoking its normal cleanup trap.
rm() { printf '[retained cleanup] %s\n' "$*" >&2; }
export -f rm
(
    cd "$scratch/latest"
    bash "$ROOT/verify.sh" latest > verify.log 2>&1
    grep -q '\[verify\] Checksum OK' verify.log
    [ -s install.sh ]
)
printf '%s\n' '{"test":"real_latest_verification","result":"pass"}'
(
    cd "$scratch/network-failure"
    if HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 NO_PROXY='' no_proxy='' \
        bash "$ROOT/verify.sh" latest > verify.log 2>&1; then
        printf '%s\n' '{"test":"real_network_failure","result":"fail","reason":"lookup failure accepted"}'
        exit 1
    fi
    grep -q '\[verify\] Failed to resolve latest release' verify.log
    [ ! -e install.sh ]
)
printf '%s\n' '{"test":"real_network_failure","result":"pass"}'
printf 'Evidence retained in %s\n' "$scratch"
