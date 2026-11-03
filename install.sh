#!/usr/bin/env bash
# ezvps installer for Debian 12/13 and Ubuntu 22.04/24.04/26.04 LTS (run as root
# from a checkout of this repo). Any other system is refused.
#
#   git clone <repo-url> && cd ezvps && bash install.sh
#
# - Installs the `ezvps` script to /usr/local/bin/ezvps.
# - Safe to re-run: identical file => no-op; changed file => the existing
#   one is backed up first, then replaced atomically.
# - Never touches ezl2tp (command, config or state). It only reports whether
#   ezl2tp is present.
# - Records what it installed (version, commit, source repository, sha256) in
#   /var/lib/ezvps/install.state so Check For Updates can compare it with the
#   latest main. The commit is recorded only when this is a clean git checkout
#   whose ezvps is the committed one; otherwise it is left out (unknown). The
#   source address is the checkout's own `origin`, with any credentials removed.
# - Needs no extra packages and downloads nothing (git is only read locally).
#
# Overrides (mainly for tests):
#   EZVPS_BIN_DIR       install directory      (default /usr/local/bin)
#   EZVPS_BACKUP_DIR    backup directory       (default /var/backups/ezvps)
#   EZVPS_STATE_DIR     state directory        (default /var/lib/ezvps)
#   EZVPS_ALLOW_NONROOT=1  skip the root check
#   EZVPS_SKIP_OS_CHECK=1  skip the OS check (tests only)
#   EZVPS_OS_RELEASE    os-release file to read (default /etc/os-release)

set -uo pipefail

BIN_DIR="${EZVPS_BIN_DIR:-/usr/local/bin}"
BACKUP_DIR="${EZVPS_BACKUP_DIR:-/var/backups/ezvps}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${EZVPS_SOURCE:-${SCRIPT_DIR}/ezvps}"
TARGET="${BIN_DIR}/ezvps"
STATE_DIR="${EZVPS_STATE_DIR:-/var/lib/ezvps}"
STATE_FILE="${STATE_DIR}/install.state"
SOURCE_VERSION=""

info() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

check_root() {
    if ((EUID != 0)) && [[ "${EZVPS_ALLOW_NONROOT:-0}" != "1" ]]; then
        die "run as root (try: sudo bash install.sh)"
    fi
}

# BEGIN ezvps-os-allowlist (identical in ezvps and install.sh; tests/lint.sh compares the two copies)
#
# Supported systems (SPEC 1.1): an exact allowlist of ID + VERSION_ID +
# VERSION_CODENAME triples. All three values must agree, so "ubuntu 24.04 jammy"
# is a mismatch and is refused, not accepted as Ubuntu. Interim Ubuntu releases,
# Debian testing/sid (no VERSION_ID), older releases, other distros and
# derivatives (ID_LIKE is never read) are not in the list.
#
# os-release is parsed line by line, never sourced. detect_os sets:
#   OS_ID        ID, lower case (debian, ubuntu, ...; "" when unreadable)
#   OS_VERSION   VERSION_ID, for example 13 or 24.04
#   OS_CODENAME  VERSION_CODENAME, lower case, for example trixie or noble
OS_ID="" OS_VERSION="" OS_CODENAME=""
OS_ALLOWLIST=(
    "debian 12 bookworm"
    "debian 13 trixie"
    "ubuntu 22.04 jammy"
    "ubuntu 24.04 noble"
    "ubuntu 26.04 resolute"
)
OS_SUPPORTED_TEXT="Debian 12 (bookworm), Debian 13 (trixie), Ubuntu 22.04 LTS (jammy), Ubuntu 24.04 LTS (noble) or Ubuntu 26.04 LTS (resolute)"

detect_os() {
    local f="${EZVPS_OS_RELEASE:-/etc/os-release}" line v
    OS_ID="" OS_VERSION="" OS_CODENAME=""
    if [[ -r "$f" ]]; then
        while IFS= read -r line; do
            v="${line#*=}"
            # Keep only characters that can appear in these fields: the values
            # end up in messages, so no control characters get through.
            v="${v//[^A-Za-z0-9._-]/}"
            case "$line" in
                ID=*) OS_ID="${v,,}" ;;
                VERSION_ID=*) OS_VERSION="$v" ;;
                VERSION_CODENAME=*) OS_CODENAME="${v,,}" ;;
            esac
        done <"$f"
    fi
    return 0
}

# The codename the allowlist requires for <id> <version> (empty when not listed).
os_expected_codename() { # os_expected_codename <id> <version>
    local e
    for e in "${OS_ALLOWLIST[@]}"; do
        if [[ "${e%% *}" == "$1" && "${e#* }" == "$2 "* ]]; then
            printf '%s' "${e##* }"
            return 0
        fi
    done
    return 0
}

# os_is_supported <id> <version> <codename>: true only for an exact allowlist entry.
os_is_supported() {
    local e
    for e in "${OS_ALLOWLIST[@]}"; do
        [[ "$e" == "$1 $2 $3" ]] && return 0
    done
    return 1
}

# The one error text for an unsupported system (ezvps and install.sh).
os_unsupported_message() { # os_unsupported_message <action>
    local want found="${OS_ID:-unknown} ${OS_VERSION:-unknown} ${OS_CODENAME:-unknown}" why=""
    want="$(os_expected_codename "$OS_ID" "$OS_VERSION")"
    [[ -n "$want" ]] && why=" (the codename does not match the version; ${OS_ID} ${OS_VERSION} is '${want}')"
    printf '%s needs a supported system: %s; found '"'"'%s'"'"'%s. Nothing was changed.' \
        "${1:-This action}" "$OS_SUPPORTED_TEXT" "$found" "$why"
}
# END ezvps-os-allowlist

# Same rule as require_supported_os in ezvps (the allowlist block above is a
# verbatim copy; tests/lint.sh keeps the two in sync). os-release is read,
# never sourced.
check_os() {
    [[ "${EZVPS_SKIP_OS_CHECK:-0}" == "1" ]] && return 0
    detect_os
    os_is_supported "$OS_ID" "$OS_VERSION" "$OS_CODENAME" ||
        die "$(os_unsupported_message "ezvps install")"
}

check_source() {
    [[ -f "$SOURCE" ]] || die "ezvps script not found at ${SOURCE} (run install.sh from a repo checkout)"
    bash -n "$SOURCE" || die "${SOURCE} has a syntax error; refusing to install it"
    local out
    out="$(EZVPS_ALLOW_NONROOT=1 bash "$SOURCE" --version 2>&1)" ||
        die "${SOURCE} failed its --version check: ${out}"
    [[ "$out" =~ ^ezvps\ ([A-Za-z0-9._+-]+)$ ]] && SOURCE_VERSION="${BASH_REMATCH[1]}"
    return 0
}

backup_existing() {
    local stamp dest
    stamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR" || die "cannot create backup directory ${BACKUP_DIR}"
    chmod 700 "$BACKUP_DIR" 2>/dev/null || true
    dest="${BACKUP_DIR}/ezvps.${stamp}.$$"
    cp -p "$TARGET" "$dest" || die "backup of ${TARGET} failed; leaving it untouched"
    info "Backed up existing ${TARGET} to ${dest}"
}

install_script() {
    mkdir -p "$BIN_DIR" || die "cannot create ${BIN_DIR}"

    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
        if [[ -f "$TARGET" && ! -L "$TARGET" ]] && cmp -s "$SOURCE" "$TARGET"; then
            chmod 0755 "$TARGET" || die "cannot set mode on ${TARGET}"
            info "ezvps is already up to date at ${TARGET}"
            return 0
        fi
        backup_existing
    fi

    # Write next to the target, then rename: the swap is atomic and a failed
    # copy never leaves a half-written ezvps behind.
    local tmp
    tmp="$(mktemp "${BIN_DIR}/.ezvps.XXXXXX")" || die "cannot create a temp file in ${BIN_DIR}"
    if ! cp "$SOURCE" "$tmp" || ! chmod 0755 "$tmp" || ! mv -f "$tmp" "$TARGET"; then
        rm -f "$tmp"
        die "installing ${TARGET} failed"
    fi
    info "Installed ezvps to ${TARGET}"
}

# The checkout's origin as an address ezvps Check For Updates accepts (https, ssh or
# user@host:path), with any user name or token in an https address removed. Empty
# when it is not such an address; git asks for credentials itself at update time.
clean_source() { # clean_source <url>
    local u="$1" rest auth
    if [[ "$u" == https://* ]]; then
        rest="${u#https://}"
        auth="${rest%%/*}"
        [[ "$auth" == *@* ]] && u="https://${auth##*@}${rest#"$auth"}"
    fi
    ((${#u} <= 300)) || return 0
    if [[ "$u" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/[A-Za-z0-9._~+-]+(/[A-Za-z0-9._~+-]+)*$ ||
        "$u" =~ ^ssh://([A-Za-z0-9_][A-Za-z0-9._-]*@)?[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/[A-Za-z0-9._~+-]+(/[A-Za-z0-9._~+-]+)*$ ||
        "$u" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9.-]*:[A-Za-z0-9._~+-]+(/[A-Za-z0-9._~+-]+)*$ ]]; then
        printf '%s' "$u"
    fi
    return 0
}

# Records what is installed. Never fatal: without a record, Check For Updates simply
# reports the installed commit as unknown.
record_install() {
    local commit="" source="" sha="" tmp
    if command -v git >/dev/null 2>&1 && [[ "$SOURCE" == "${SCRIPT_DIR}/ezvps" ]] &&
        git -C "$SCRIPT_DIR" ls-files --error-unmatch -- ezvps >/dev/null 2>&1 &&
        git -C "$SCRIPT_DIR" diff --quiet HEAD -- ezvps >/dev/null 2>&1; then
        commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)"
        [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || commit=""
    fi
    if command -v git >/dev/null 2>&1 && [[ "$SOURCE" == "${SCRIPT_DIR}/ezvps" ]]; then
        source="$(clean_source "$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)")"
    fi
    sha="$(sha256sum "$TARGET" 2>/dev/null)" || sha=""
    sha="${sha%% *}"
    if ! { mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"; } 2>/dev/null; then
        warn "cannot create ${STATE_DIR}; the installed version is not recorded"
        return 0
    fi
    tmp="${STATE_FILE}.tmp.$$"
    if ! {
        {
            printf 'version=%s\n' "$SOURCE_VERSION"
            printf 'commit=%s\n' "$commit"
            printf 'source=%s\n' "$source"
            printf 'sha256=%s\n' "$sha"
            printf 'installed=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } >"$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$STATE_FILE"
    } 2>/dev/null; then
        rm -f "$tmp"
        warn "cannot write ${STATE_FILE}; the installed version is not recorded"
        return 0
    fi
    if [[ -n "$commit" ]]; then
        info "Recorded version ${SOURCE_VERSION} and commit ${commit:0:12} in ${STATE_FILE}"
    else
        info "Recorded version ${SOURCE_VERSION} in ${STATE_FILE} (commit unknown: not a clean git checkout)"
    fi
}

report_ezl2tp() {
    if PATH="${BIN_DIR}:${PATH}" command -v ezl2tp >/dev/null 2>&1; then
        info "ezl2tp found; left untouched."
    else
        info "ezl2tp not found. The L2TP menu entry will show how to install it."
    fi
}

main() {
    check_root
    check_os
    check_source
    install_script
    record_install
    report_ezl2tp
    info "Done. Run: ezvps"
}

main "$@"
