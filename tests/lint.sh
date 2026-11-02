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

# 3. Download rules.
#    - ezvps may call curl only from the 3x-ui download/probe functions
#      (xui_fetch_installer, xui_probe) and the Nginx signing-key download
#      (ngx_fetch_key); never from L2TP or anywhere else.
#    - Nothing is ever piped or process-substituted from the network into a shell.
#    - install.sh downloads nothing.
bad_curl="$(awk '/^[A-Za-z_0-9]+\(\) \{/ {fn=$1} /^}/ {fn=""}
    !/^[[:space:]]*#/ && /(^|[[:space:]($`])(curl|wget)[[:space:]]+-/ {
        if (fn != "xui_fetch_installer()" && fn != "xui_probe()" && fn != "ngx_fetch_key()") print NR": "$0 }' ezvps)"
if [[ -n "$bad_curl" ]]; then
    bad "ezvps: curl/wget outside xui_fetch_installer/xui_probe/ngx_fetch_key:"
    printf '%s\n' "$bad_curl" >&2
fi
for f in ezvps install.sh; do
    if grep -vE '^[[:space:]]*#' "$f" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|da)?sh|(ba)?sh[[:space:]]+<\(|(source|\.)[[:space:]]+<\('; then
        bad "$f: pipes a download into a shell"
    fi
done
if grep -vE '^[[:space:]]*#' install.sh | grep -qE 'curl|wget'; then
    bad "install.sh must not download anything"
fi
# 3x-ui installer must be fetched from a pinned tag, never a moving branch.
if grep -nE 'raw\.githubusercontent\.com/[^"]*/(master|main|HEAD)/' ezvps | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
    bad "ezvps: installer URL must use a pinned tag, not master/main"
fi
if ! grep -qE '^XUI_INSTALLER_SHA256="[0-9a-f]{64}"' ezvps || ! grep -qE '^XUI_PINNED_TAG="v[0-9]+\.[0-9]+\.[0-9]+"' ezvps; then
    bad "ezvps: XUI_PINNED_TAG / XUI_INSTALLER_SHA256 pin missing or malformed"
fi
# Nginx must come from the nginx.org STABLE repository: the repo URL has no
# "mainline", the key URL is https, the pin is priority 900, and the key
# fingerprints are pinned (40 hex digits each).
if ! grep -qE '^NGX_ORG_REPO_URL="https://nginx\.org/packages/debian"$' ezvps ||
    grep -vE '^[[:space:]]*#' ezvps | grep -q 'nginx\.org/packages/mainline"'; then
    bad "ezvps: the nginx.org repo URL must be https://nginx.org/packages/debian (stable), never mainline"
fi
if ! grep -qE '^NGX_ORG_KEY_URL="https://nginx\.org/keys/nginx_signing\.key"$' ezvps; then
    bad "ezvps: NGX_ORG_KEY_URL missing or changed"
fi
if [[ "$(grep -cE '^    [0-9A-F]{40}$' ezvps)" -lt 1 ]]; then
    bad "ezvps: NGX_ORG_KEY_FPRS fingerprint pins missing or malformed"
fi
if ! grep -qF '"Pin-Priority: 900"' ezvps || ! grep -qF '"Pin: origin nginx.org"' ezvps; then
    bad "ezvps: the nginx.org apt pin (origin nginx.org, priority 900) is missing"
fi

if ((fail == 0)); then
    note "lint OK"
fi
exit "$fail"
