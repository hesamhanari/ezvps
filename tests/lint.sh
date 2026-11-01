#!/usr/bin/env bash
# Lint every shell script in the repo and check repo hygiene.
#   bash tests/lint.sh
# Needs shellcheck (apt install shellcheck). Exits non-zero on any finding.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
note() { printf '%s\n' "$*"; }
bad() {
    printf 'FAIL: %s\n' "$*" >&2
    fail=1
}

SCRIPTS=(ezvps install.sh tests/lint.sh tests/smoke-test.sh)

# 1. syntax + shellcheck
if ! command -v shellcheck >/dev/null 2>&1; then
    bad "shellcheck not found (install it: apt install shellcheck)"
else
    for f in "${SCRIPTS[@]}"; do
        if [[ ! -f "$f" ]]; then
            bad "missing script: $f"
            continue
        fi
        bash -n "$f" || bad "syntax error in $f"
        shellcheck -x -s bash "$f" || bad "shellcheck findings in $f"
    done
fi

# 2. hygiene: no real IPs, key material or tokens in tracked text files.
#    Allowed IPs: loopback, 0.0.0.0 and the RFC 5737 documentation ranges.
mapfile -t files < <(git ls-files --cached --others --exclude-standard 2>/dev/null)
if ((${#files[@]} == 0)); then
    mapfile -t files < <(find . -type f -not -path './.git/*' | sed 's|^\./||')
fi

ip_re='([0-9]{1,3}\.){3}[0-9]{1,3}'
allowed_ip_re='^(127\.0\.0\.1|0\.0\.0\.0|192\.0\.2\.[0-9]+|198\.51\.100\.[0-9]+|203\.0\.113\.[0-9]+)$'
secret_re='(-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})'

for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    while read -r ip; do
        [[ -z "$ip" ]] && continue
        [[ "$ip" =~ $allowed_ip_re ]] || bad "$f: non-documentation IP address: $ip"
    done < <(grep -Eoh "$ip_re" "$f" 2>/dev/null | sort -u)
    if grep -Eq "$secret_re" "$f" 2>/dev/null; then
        bad "$f: looks like a secret or key material"
    fi
done

# 3. L2TP rule: ezvps must not download anything or embed the ezl2tp installer.
if grep -nE 'curl|wget' ezvps | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
    bad "ezvps must not use curl/wget in this release"
fi

if ((fail == 0)); then
    note "lint OK"
fi
exit "$fail"
