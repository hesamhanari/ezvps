#!/usr/bin/env bash
# ezvps installer for Debian 13 (run as root from a checkout of this repo).
#
#   git clone <repo-url> && cd ezvps && bash install.sh
#
# - Installs the `ezvps` script to /usr/local/bin/ezvps.
# - Safe to re-run: identical file => no-op; changed file => the existing
#   one is backed up first, then replaced atomically.
# - Never touches ezl2tp (command, config or state). It only reports whether
#   ezl2tp is present.
# - Needs no extra packages and downloads nothing.
#
# Overrides (mainly for tests):
#   EZVPS_BIN_DIR       install directory      (default /usr/local/bin)
#   EZVPS_BACKUP_DIR    backup directory       (default /var/backups/ezvps)
#   EZVPS_ALLOW_NONROOT=1  skip the root check
#   EZVPS_SKIP_OS_CHECK=1  skip the Debian 13 check

set -uo pipefail

BIN_DIR="${EZVPS_BIN_DIR:-/usr/local/bin}"
BACKUP_DIR="${EZVPS_BACKUP_DIR:-/var/backups/ezvps}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${EZVPS_SOURCE:-${SCRIPT_DIR}/ezvps}"
TARGET="${BIN_DIR}/ezvps"

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

check_os() {
    [[ "${EZVPS_SKIP_OS_CHECK:-0}" == "1" ]] && return 0
    local id="" version_id=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id="$(. /etc/os-release && printf '%s' "${ID:-}")"
        # shellcheck disable=SC1091
        version_id="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
    fi
    if [[ "$id" != "debian" || "$version_id" != "13" ]]; then
        warn "ezvps targets Debian 13; found '${id:-unknown} ${version_id:-unknown}'. Continuing anyway."
    fi
}

check_source() {
    [[ -f "$SOURCE" ]] || die "ezvps script not found at ${SOURCE} (run install.sh from a repo checkout)"
    bash -n "$SOURCE" || die "${SOURCE} has a syntax error; refusing to install it"
    local out
    out="$(EZVPS_ALLOW_NONROOT=1 bash "$SOURCE" --version 2>&1)" ||
        die "${SOURCE} failed its --version check: ${out}"
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
    report_ezl2tp
    info "Done. Run: ezvps"
}

main "$@"
