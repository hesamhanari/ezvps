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
#      (xui_fetch_installer, xui_probe), the Nginx signing-key download
#      (ngx_fetch_key), the pinned acme.sh download (acme_fetch_script) and the
#      pinned Backpack/Lazyports installer download (lc_fetch_installer); never
#      from L2TP or anywhere else.
#    - git may touch the network only in lc_fetch_source (the pinned ctunnel commit).
#    - Nothing is ever piped or process-substituted from the network into a shell.
#    - install.sh downloads nothing.
bad_curl="$(awk '/^[A-Za-z_0-9]+\(\) \{/ {fn=$1} /^}/ {fn=""}
    !/^[[:space:]]*#/ && /(^|[[:space:]($`])(curl|wget)[[:space:]]+-/ {
        if (fn != "xui_fetch_installer()" && fn != "xui_probe()" && fn != "ngx_fetch_key()" && fn != "acme_fetch_script()" && fn != "lc_fetch_installer()") print NR": "$0 }' ezvps)"
if [[ -n "$bad_curl" ]]; then
    bad "ezvps: curl/wget outside xui_fetch_installer/xui_probe/ngx_fetch_key/acme_fetch_script/lc_fetch_installer:"
    printf '%s\n' "$bad_curl" >&2
fi
bad_git="$(awk '/^[A-Za-z_0-9]+\(\) \{/ {fn=$1} /^}/ {fn=""}
    !/^[[:space:]]*#/ && /[[:space:]](fetch|clone|pull|ls-remote|submodule)[[:space:]]/ && /"\$\{g\[@\]\}"|git[[:space:]]+-/ {
        if (fn != "lc_fetch_source()") print NR": "$0 }' ezvps)"
if [[ -n "$bad_git" ]]; then
    bad "ezvps: git network access outside lc_fetch_source:"
    printf '%s\n' "$bad_git" >&2
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
# acme.sh is installed from its official project at a pinned release tag, checked
# against a pinned SHA-256 (the tag is part of the URL, never a branch).
# shellcheck disable=SC2016 # the literal ${...} text of the URL line in ezvps
if ! grep -qE '^ACME_PINNED_TAG="[0-9]+\.[0-9]+\.[0-9]+"$' ezvps ||
    ! grep -qE '^ACME_SCRIPT_SHA256="[0-9a-f]{64}"$' ezvps ||
    ! grep -qE '^ACME_UPSTREAM="acmesh-official/acme\.sh"$' ezvps ||
    ! grep -qF 'ACME_SCRIPT_URL="https://raw.githubusercontent.com/${ACME_UPSTREAM}/${ACME_PINNED_TAG}/acme.sh"' ezvps; then
    bad "ezvps: the acme.sh pin (ACME_UPSTREAM, ACME_PINNED_TAG, ACME_SCRIPT_URL, ACME_SCRIPT_SHA256) is missing or malformed"
fi
if grep -vE '^[[:space:]]*#' ezvps | grep -qE 'get\.acme\.sh'; then
    bad "ezvps: never use get.acme.sh (it is piped into a shell and not pinned)"
fi
# Certificates validate with HTTP-01 through nginx only: no DNS API mode, no
# provider credentials, no certbot.
if grep -vE '^[[:space:]]*#' ezvps | grep -qiE -- '--dns|dns_[a-z]+|CF_Token|api_?key|certbot'; then
    bad "ezvps: DNS validation, DNS provider credentials and certbot are out of scope for the Certificates module"
fi
# Backpack, ctunnel and Lazyports: every upstream is pinned (a release tag or a full
# commit, plus a SHA-256 for the installer scripts), and the installer URLs are built
# from the pin, never a branch.
if ! grep -qE '^LC_BACKPACK_REPO="AminMGMT/BackPack"$' ezvps ||
    ! grep -qE '^LC_BACKPACK_TAG="v[0-9]+\.[0-9]+\.[0-9]+"$' ezvps ||
    ! grep -qE '^LC_BACKPACK_SHA256="[0-9a-f]{64}"$' ezvps ||
    ! grep -qE '^LC_CTUNNEL_REPO="alienrobotarmy/ctunnel"$' ezvps ||
    ! grep -qE '^LC_CTUNNEL_COMMIT="[0-9a-f]{40}"$' ezvps ||
    ! grep -qE '^LC_LAZYPORTS_REPO="v9mirza/lazyports"$' ezvps ||
    ! grep -qE '^LC_LAZYPORTS_COMMIT="[0-9a-f]{40}"$' ezvps ||
    ! grep -qE '^LC_LAZYPORTS_SHA256="[0-9a-f]{64}"$' ezvps; then
    bad "ezvps: the Backpack/ctunnel/Lazyports pins (repo, tag or commit, sha256) are missing or malformed"
fi
# shellcheck disable=SC2016 # the literal ${...} text of the URL lines in ezvps
if ! grep -qF 'LC_URL="https://raw.githubusercontent.com/${LC_BACKPACK_REPO}/${LC_BACKPACK_TAG}/install.sh"' ezvps ||
    ! grep -qF 'LC_URL="https://raw.githubusercontent.com/${LC_LAZYPORTS_REPO}/${LC_LAZYPORTS_COMMIT}/install.sh"' ezvps ||
    ! grep -qF 'LC_GIT_COMMIT="$LC_CTUNNEL_COMMIT"' ezvps; then
    bad "ezvps: the Backpack/Lazyports installer URLs must be built from the pinned tag/commit, and ctunnel from its pinned commit"
fi
# The upstream installers run with no terminal input (Backpack's would open its menu).
# shellcheck disable=SC2016 # the literal ${tmp} text in ezvps
if ! grep -qF 'bash "${tmp}/install.sh" </dev/null' ezvps; then
    bad "ezvps: the upstream installer must run with </dev/null so it can not open the tool"
fi
# SSH and Users: password hashes live in /etc/shadow, which ezvps never reads; a password is only
# ever asked for by the system's own passwd prompt; downloads are not part of this module.
ssh_users_code="$(awk '/^(usr_|ssh_|module_ssh)[a-z_]*\(\) \{/ {on=1} on {print} /^}/ {on=0}' ezvps | grep -vE '^[[:space:]]*#')"
if grep -q 'shadow' <<<"$ssh_users_code"; then
    bad "ezvps: the SSH and Users module must never touch /etc/shadow (password hashes)"
fi
if grep -qE '(curl|wget)' <<<"$ssh_users_code"; then
    bad "ezvps: the SSH and Users module must not download anything"
fi
if grep -qE 'read[^|]*-s[^|]*(pass|pw)' <<<"$ssh_users_code"; then
    bad "ezvps: the SSH and Users module must not read a password itself (use the system's passwd prompt)"
fi
# Nginx must come from the nginx.org STABLE repository: the repo URL has no
# "mainline", the key URL is https, the pin is priority 900, and the key
# fingerprints are pinned (40 hex digits each).
if ! grep -qE '^NGX_ORG_REPO_DEBIAN="https://nginx\.org/packages/debian"$' ezvps ||
    ! grep -qE '^NGX_ORG_REPO_UBUNTU="https://nginx\.org/packages/ubuntu"$' ezvps ||
    grep -vE '^[[:space:]]*#' ezvps | grep -q 'https://nginx\.org/packages/mainline'; then
    bad "ezvps: the nginx.org repo URLs must be https://nginx.org/packages/debian and .../ubuntu (stable), never mainline"
fi
# Every nginx.org repository URL in the script must be one of those two constants.
if grep -vE '^[[:space:]]*#' ezvps | grep -oE 'https://nginx\.org/packages/[a-z/]*' | sort -u |
    grep -vxE 'https://nginx\.org/packages/(debian|ubuntu)'; then
    bad "ezvps: unexpected nginx.org repository URL (only packages/debian and packages/ubuntu are allowed)"
fi
# One shared OS check: the Debian-only function must not come back, the
# allowlist must be exactly the five supported id + version + codename triples,
# and the block must be byte-identical in ezvps and install.sh.
if grep -q 'require_debian13' ezvps; then
    bad "ezvps: require_debian13 is gone; use require_supported_os"
fi
os_block() { sed -n '/^# BEGIN ezvps-os-allowlist/,/^# END ezvps-os-allowlist/p' "$1"; }
if [[ -z "$(os_block ezvps)" ]] || [[ "$(os_block ezvps)" != "$(os_block install.sh)" ]]; then
    bad "ezvps and install.sh must carry the identical '# BEGIN/END ezvps-os-allowlist' block"
fi
want_allow='    "debian 12 bookworm"
    "debian 13 trixie"
    "ubuntu 22.04 jammy"
    "ubuntu 24.04 noble"
    "ubuntu 26.04 resolute"'
got_allow="$(os_block ezvps | sed -n '/^OS_ALLOWLIST=(/,/^)/p' | sed '1d;$d')"
if [[ "$got_allow" != "$want_allow" ]]; then
    bad "ezvps: OS_ALLOWLIST must list exactly Debian 12/13 and Ubuntu 22.04/24.04/26.04 (bookworm trixie jammy noble resolute)"
fi
if grep -vE '^[[:space:]]*#' ezvps install.sh | grep -qE 'ID_LIKE|(source|\.)[[:space:]]+[^ ]*os-release'; then
    bad "os-release must be parsed, never sourced, and ID_LIKE must be ignored"
fi
# The nginx.org suite is the detected codename, never a per-distro constant.
if grep -vE '^[[:space:]]*#' ezvps | grep -E 'nginx\.org/packages|NGX_CODENAME=' | grep -E '(bookworm|trixie|jammy|noble|resolute)'; then
    bad "ezvps: the nginx.org suite must come from the detected codename, not a hardcoded one"
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
