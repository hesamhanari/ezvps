#!/usr/bin/env bash
# Smoke test for ezvps and install.sh. Safe to run anywhere: it never touches
# /usr/local/bin, /var/backups or a real ezl2tp. All data is fake.
#   bash tests/smoke-test.sh

# Helpers are invoked indirectly through `check`.
# shellcheck disable=SC2329,SC2317
# nginx variables ($host, $connection_upgrade, ...) appear as literal text in single quotes throughout.
# shellcheck disable=SC2016

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EZVPS="$ROOT/ezvps"
INSTALL="$ROOT/install.sh"
BASH_BIN="$(command -v bash)"

WORK="$(mktemp -d)"
PY_PID=""
cleanup() {
    [[ -n "$PY_PID" ]] && kill "$PY_PID" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

PASS=0
FAILS=0
check() { # check <description> <command...>
    local desc="$1"
    shift
    if "$@"; then
        PASS=$((PASS + 1))
        printf 'ok   - %s\n' "$desc"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL - %s\n' "$desc"
    fi
}

# Assertion helpers (each returns 0/1 so they work with `check`).
contains() { [[ "$1" == *"$2"* ]]; }
not_contains() { [[ "$1" != *"$2"* ]]; }
has_line() { printf '%s\n' "$1" | grep -qxF -- "$2"; }
count_lines() { printf '%s\n' "$1" | grep -cF -- "$2"; }
at_least_menus() { (($(count_lines "$1" "ezvps 0.0.1") >= $2)); }
equals() { [[ "$1" == "$2" ]]; }
dir_empty_or_missing() { [[ ! -d "$1" || -z "$(ls -A "$1")" ]]; }

export EZVPS_ALLOW_NONROOT=1 EZVPS_SKIP_OS_CHECK=1 NO_COLOR=1 TERM=dumb

# Fake os-release files (never the real /etc/os-release of the machine running the
# tests). Every run defaults to Debian 13; the "operating systems" section and a few
# precheck tests point EZVPS_OS_RELEASE at the others.
OSD="$WORK/os"
mkdir -p "$OSD"
printf '%s\n' 'PRETTY_NAME="Debian GNU/Linux 13 (trixie)"' 'NAME="Debian GNU/Linux"' 'VERSION_ID="13"' 'VERSION="13 (trixie)"' 'VERSION_CODENAME=trixie' 'ID=debian' >"$OSD/debian13"
printf '%s\n' 'PRETTY_NAME="Ubuntu 24.04.2 LTS"' 'NAME="Ubuntu"' 'VERSION_ID="24.04"' 'VERSION="24.04.2 LTS (Noble Numbat)"' 'VERSION_CODENAME=noble' 'ID=ubuntu' 'ID_LIKE=debian' 'UBUNTU_CODENAME=noble' >"$OSD/ubuntu2404"
printf '%s\n' 'PRETTY_NAME="Ubuntu 22.04.5 LTS"' 'NAME="Ubuntu"' 'VERSION_ID="22.04"' 'VERSION="22.04.5 LTS (Jammy Jellyfish)"' 'VERSION_CODENAME=jammy' 'ID=ubuntu' 'ID_LIKE=debian' 'UBUNTU_CODENAME=jammy' >"$OSD/ubuntu2204"
printf '%s\n' 'PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"' 'NAME="Debian GNU/Linux"' 'VERSION_ID="12"' 'VERSION="12 (bookworm)"' 'VERSION_CODENAME=bookworm' 'ID=debian' >"$OSD/debian12"
# Ubuntu 26.04 LTS, and releases/combinations that must be rejected (fake data).
printf '%s\n' 'PRETTY_NAME="Ubuntu 26.04 LTS"' 'NAME="Ubuntu"' 'VERSION_ID="26.04"' 'VERSION="26.04 LTS (Resolute Raccoon)"' 'VERSION_CODENAME=resolute' 'ID=ubuntu' 'ID_LIKE=debian' 'UBUNTU_CODENAME=resolute' >"$OSD/ubuntu2604"
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="25.10"' 'VERSION_CODENAME=questing' 'ID=ubuntu' 'ID_LIKE=debian' >"$OSD/ubuntu2510"
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="25.04"' 'VERSION_CODENAME=plucky' 'ID=ubuntu' 'ID_LIKE=debian' >"$OSD/ubuntu2504"
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="23.10"' 'VERSION_CODENAME=mantic' 'ID=ubuntu' 'ID_LIKE=debian' >"$OSD/ubuntu2310"
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="26.10"' 'VERSION_CODENAME=nextrelease' 'ID=ubuntu' 'ID_LIKE=debian' >"$OSD/ubuntu2610"
printf '%s\n' 'PRETTY_NAME="Debian GNU/Linux 11 (bullseye)"' 'NAME="Debian GNU/Linux"' 'VERSION_ID="11"' 'VERSION_CODENAME=bullseye' 'ID=debian' >"$OSD/debian11"
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="24.04"' 'VERSION_CODENAME=jammy' 'ID=ubuntu' 'ID_LIKE=debian' >"$OSD/ubuntu2404-jammy" # version/codename mismatch
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="22.04"' 'VERSION_CODENAME=noble' 'ID=ubuntu' >"$OSD/ubuntu2204-noble"                  # mismatch the other way
printf '%s\n' 'NAME="Debian GNU/Linux"' 'VERSION_ID="13"' 'VERSION_CODENAME=bookworm' 'ID=debian' >"$OSD/debian13-bookworm"         # mismatch
printf '%s\n' 'NAME="Debian GNU/Linux"' 'VERSION_ID="12"' 'VERSION_CODENAME=noble' 'ID=debian' >"$OSD/debian12-noble"              # Ubuntu codename on Debian
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="22.04"' 'ID=ubuntu' >"$OSD/ubuntu2204-nocodename"                                       # no VERSION_CODENAME
printf '%s\n' 'PRETTY_NAME="Debian GNU/Linux forky/sid"' 'ID=debian' 'VERSION_CODENAME=forky' >"$OSD/debian-testing"               # testing/sid: no VERSION_ID
printf '%s\n' 'NAME="Fedora Linux"' 'VERSION_ID=40' 'VERSION_CODENAME=""' 'ID=fedora' 'ID_LIKE="rhel centos"' >"$OSD/unknown"
export EZVPS_OS_RELEASE="$OSD/debian13"
# The one error text for an unsupported system (SPEC 1.1), as ezvps and install.sh print it.
OS_LIST_TEXT="Debian 12 (bookworm), Debian 13 (trixie), Ubuntu 22.04 LTS (jammy), Ubuntu 24.04 LTS (noble) or Ubuntu 26.04 LTS (resolute)"

# Sandbox PATHs. ezvps only needs bash builtins, so an empty dir is a PATH
# with no ezl2tp even if the host has one installed.
EMPTY_BIN="$WORK/empty-bin"
STUB_BIN="$WORK/stub-bin"
FAIL_BIN="$WORK/fail-bin"
mkdir -p "$EMPTY_BIN" "$STUB_BIN" "$FAIL_BIN"

cat >"$STUB_BIN/ezl2tp" <<'EOF'
#!/bin/sh
echo "FAKE-EZL2TP-RAN"
exit 0
EOF
cat >"$FAIL_BIN/ezl2tp" <<'EOF'
#!/bin/sh
echo "FAKE-EZL2TP-FAILED"
exit 3
EOF
chmod +x "$STUB_BIN/ezl2tp" "$FAIL_BIN/ezl2tp"

# run_ezvps <path-dir> <stdin-text> [args...]  -> sets OUT and RC
run_ezvps() {
    local pathdir="$1" input="$2"
    shift 2
    OUT="$(printf '%b' "$input" | PATH="$pathdir" "$BASH_BIN" "$EZVPS" "$@" 2>&1)"
    RC=$?
}

LABELS=("L2TP" "3x-ui" "Backpack" "ctunnel" "Nginx" "Certificates" "Lazyports" "SSH and Users" "Firewall" "Backup" "Check For Updates" "Uninstall")
KEYS=(l2tp 3x-ui backpack ctunnel nginx certs lazyports ssh firewall backup update uninstall)

echo "== basics"
run_ezvps "$EMPTY_BIN" "" --version
check "--version exits 0" equals "$RC" 0
check "--version prints version" contains "$OUT" "ezvps 0.0.1"
run_ezvps "$EMPTY_BIN" "" --help
check "--help exits 0" equals "$RC" 0
check "--help shows usage" contains "$OUT" "Usage:"
run_ezvps "$EMPTY_BIN" "" bogus
check "unknown command exits 2" equals "$RC" 2

echo "== menu"
run_ezvps "$EMPTY_BIN" "0\n"
check "menu exits 0 on '0'" equals "$RC" 0
for i in "${!LABELS[@]}"; do
    line="$(printf '%2d) %s' "$((i + 1))" "${LABELS[$i]}")"
    check "menu line '${line}' is exact (clean label, no description)" has_line "$OUT" "$line"
done
check "menu has Exit as 0" has_line "$OUT" " 0) Exit"
numbered="$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+\) ')"
check "menu has exactly 13 numbered entries" equals "$numbered" 13

run_ezvps "$EMPTY_BIN" ""
check "EOF on stdin exits 0 cleanly" equals "$RC" 0
run_ezvps "$EMPTY_BIN" "abc\n\n99\n\n0\n"
check "invalid input exits 0 at the end" equals "$RC" 0
check "non-numeric input is reported" contains "$OUT" "Invalid choice: abc"
check "out-of-range input is reported" contains "$OUT" "Invalid choice: 99"

echo "== L2TP: ezl2tp present (fake stub)"
run_ezvps "$STUB_BIN" "1\n\n0\n"
check "stub ezl2tp is launched" contains "$OUT" "FAKE-EZL2TP-RAN"
check "returns to ezvps afterwards" contains "$OUT" "Returned to ezvps."
check "menu is shown again after ezl2tp" at_least_menus "$OUT" 2
check "exit status 0" equals "$RC" 0
run_ezvps "$STUB_BIN" "" l2tp
check "'ezvps l2tp' launches the stub" contains "$OUT" "FAKE-EZL2TP-RAN"
check "'ezvps l2tp' exits 0" equals "$RC" 0

echo "== L2TP: ezl2tp exits non-zero"
run_ezvps "$FAIL_BIN" "1\n\n0\n"
check "failing ezl2tp ran" contains "$OUT" "FAKE-EZL2TP-FAILED"
check "failure status is reported" contains "$OUT" "exited with status 3"
check "ezvps still returns to the menu" contains "$OUT" "Returned to ezvps."
check "ezvps still exits 0" equals "$RC" 0

echo "== L2TP: ezl2tp missing"
run_ezvps "$EMPTY_BIN" "1\n\n0\n"
check "says ezl2tp is not installed" contains "$OUT" "ezl2tp is not installed"
check "gives git clone instructions" contains "$OUT" "git clone"
check "explains the repo is private" contains "$OUT" "private"
check "no raw-download hint" not_contains "$OUT" "raw.githubusercontent"
check "no curl/wget hint" not_contains "$OUT" "curl"
check "does not claim to have launched ezl2tp" not_contains "$OUT" "Launching ezl2tp"
check "menu is shown again after the help" at_least_menus "$OUT" 2
check "exit status 0" equals "$RC" 0
run_ezvps "$EMPTY_BIN" "" l2tp
check "'ezvps l2tp' without ezl2tp gives instructions" contains "$OUT" "git clone"
check "'ezvps l2tp' without ezl2tp exits 0" equals "$RC" 0

echo "== not-yet-implemented modules"
for i in "${!KEYS[@]}"; do
    [[ "${KEYS[$i]}" == "l2tp" || "${KEYS[$i]}" == "3x-ui" || "${KEYS[$i]}" == "nginx" || "${KEYS[$i]}" == "certs" || "${KEYS[$i]}" == "backpack" || "${KEYS[$i]}" == "ctunnel" || "${KEYS[$i]}" == "lazyports" || "${KEYS[$i]}" == "ssh" || "${KEYS[$i]}" == "firewall" ]] && continue
    n=$((i + 1))
    label="${LABELS[$i]}"
    run_ezvps "$STUB_BIN" "${n}\n\n0\n"
    check "menu ${n} (${label}): shows not-implemented message" contains "$OUT" "${label} is not implemented yet."
    check "menu ${n} (${label}): returns to the menu" at_least_menus "$OUT" 2
    check "menu ${n} (${label}): does not launch ezl2tp" not_contains "$OUT" "FAKE-EZL2TP-RAN"
    check "menu ${n} (${label}): exits 0" equals "$RC" 0
    run_ezvps "$STUB_BIN" "" "${KEYS[$i]}"
    check "cli '${KEYS[$i]}': not-implemented message, exit 0" contains "$OUT" "${label} is not implemented yet."
    check "cli '${KEYS[$i]}': exits 0" equals "$RC" 0
done

echo "== 3x-ui module (fake panel CLI, fake systemctl/curl/ss, no network)"

PINNED_TAG="$(grep -oE '^XUI_PINNED_TAG="[^"]+"' "$EZVPS" | cut -d'"' -f2)"
PINNED_SHA="$(grep -oE '^XUI_INSTALLER_SHA256="[0-9a-f]{64}"' "$EZVPS" | cut -d'"' -f2)"
check "pinned tag is declared (vX.Y.Z)" test -n "$PINNED_TAG" -a "${PINNED_TAG#v}" != "$PINNED_TAG"
check "pinned installer sha256 is declared" test "${#PINNED_SHA}" -eq 64

mkstub() { # mkstub <path>   (script body on stdin)
    {
        printf '#!%s\n' "$BASH_BIN"
        cat
    } >"$1"
    chmod +x "$1"
}

# The module's real dependencies are coreutils + bash; everything else is a stub.
CORE_BIN="$WORK/core-bin"
mkdir -p "$CORE_BIN"
for c in bash cp mkdir mv rm rmdir mktemp date chmod ln readlink; do
    ln -s "$(command -v "$c")" "$CORE_BIN/$c"
done
STUBS="$WORK/xui-stubs"
SBOX="$WORK/sbox"               # coreutils + all stubs
SBOX_NOCURL="$WORK/sbox-nocurl" # same, without curl (apt-get stub can add it)
mkdir -p "$STUBS" "$SBOX" "$SBOX_NOCURL"

# fake `x-ui` panel CLI; its "database" is $EZVPS_XUI_DB_DIR/x-ui.db (key=value)
mkstub "$WORK/fake-xui" <<'EOF'
db="$EZVPS_XUI_DB_DIR/x-ui.db"
port="" path="" user="" pass="" cert=""
if [[ -f "$db" ]]; then
    while IFS='=' read -r k v; do
        case "$k" in port) port="$v" ;; path) path="$v" ;; user) user="$v" ;; pass) pass="$v" ;; cert) cert="$v" ;; esac
    done <"$db"
fi
save() { printf 'port=%s\npath=%s\nuser=%s\npass=%s\ncert=%s\n' "$port" "$path" "$user" "$pass" "$cert" >"$db"; }
masked=() prev=""
for a in "$@"; do
    if [[ "$prev" == "-password" ]]; then masked+=("***"); else masked+=("$a"); fi
    prev="$a"
done
printf 'x-ui %s\n' "${masked[*]}" >>"$FAKE_LOG"
cmd="${1:-}"
shift
nu="" np="" nport="" npath="" show=0 getcert=0 reset=0
while (($#)); do
    case "$1" in
        -username) nu="$2"; shift ;;
        -password) np="$2"; shift ;;
        -port) nport="$2"; shift ;;
        -webBasePath) npath="$2"; shift ;;
        -show=true | -show) show=1 ;;
        -getCert=true | -getCert) getcert=1 ;;
        -reset) reset=1 ;;
    esac
    shift
done
case "$cmd" in
    setting)
        [[ -n "$nport" ]] && { port="$nport"; echo "Port set successfully: $port"; }
        [[ -n "$npath" ]] && path="$npath"
        if [[ -n "$nu" || -n "$np" ]]; then
            if [[ -z "$nu" || -z "$np" ]]; then
                echo "Failed to update username and password: can not be empty"
            else
                user="$nu"; pass="$np"; echo "Username and password updated successfully"
            fi
        fi
        save
        if ((show)); then
            echo "current panel settings as follows:"
            if [[ -z "$cert" ]]; then echo "Warning: Panel is not secure with SSL"; else echo "Panel is secure with SSL"; fi
            echo "hasDefaultCredential: false"
            echo "port: $port"
            echo "webBasePath: /${path}/"
        fi
        if ((getcert)); then echo "cert: $cert"; echo "key: $cert"; fi
        ;;
    cert)
        if ((reset)); then cert=""; save; echo "set certificate public key success"; fi
        ;;
    *) echo "Invalid subcommands" ;;
esac
exit 0
EOF

# fake official installer (what the curl stub "downloads")
mkstub "$WORK/fake-installer.sh" <<'EOF'
echo "FAKE-INSTALLER-RAN args=$* noninteractive=${XUI_NONINTERACTIVE:-} ssl=${XUI_SSL_MODE:-} port=${XUI_PANEL_PORT:-}" >>"$FAKE_LOG"
[[ "${FAKE_INSTALLER_FAIL:-0}" == "1" ]] && exit 1
mkdir -p "$EZVPS_XUI_DIR" "$EZVPS_XUI_DB_DIR"
cp "$FAKE_XUI_TEMPLATE" "$EZVPS_XUI_DIR/x-ui"
chmod +x "$EZVPS_XUI_DIR/x-ui"
if [[ "${FAKE_INSTALLER_ASKS:-0}" == "1" ]]; then
    echo "FAKE-INSTALLER-PROMPTED" >>"$FAKE_LOG"
    read -r -p "Panel port: " p
    read -r -p "Username: " u
    read -r -p "Password: " w
    printf 'port=%s\npath=selfpath\nuser=%s\npass=%s\ncert=\n' "$p" "$u" "$w" >"$EZVPS_XUI_DB_DIR/x-ui.db"
else
    printf 'port=41234\npath=randompath\nuser=randuser\npass=randpass\ncert=\n' >"$EZVPS_XUI_DB_DIR/x-ui.db"
fi
echo active >"$FAKE_SVC"
exit 0
EOF

mkstub "$STUBS/systemctl" <<'EOF'
# one fake unit per service: x-ui (state file $FAKE_SVC) and nginx ($FAKE_NGX_SVC)
verb="${1:-}"
svc="${*: -1}"
if [[ "$svc" == "nginx" ]]; then
    state="${FAKE_NGX_SVC:-/nonexistent}"
    fail_restart="${FAKE_NGX_RESTART_FAIL:-0}"
else
    state="$FAKE_SVC"
    fail_restart="${FAKE_RESTART_FAIL:-0}"
fi
case "$verb" in
    is-active)
        [[ -f "$state" && "$(<"$state")" == "active" ]] && exit 0
        exit 3 ;;
    is-enabled) [[ -f "$state" ]] && { echo enabled; exit 0; }; exit 1 ;;
    list-unit-files) [[ -f "$FAKE_SVC" ]] && echo "x-ui.service enabled enabled"; exit 0 ;;
    restart | start)
        echo "systemctl $*" >>"$FAKE_LOG"
        [[ "$fail_restart" == "1" ]] && exit 1
        echo active >"$state"
        exit 0 ;;
    reload)
        echo "systemctl $*" >>"$FAKE_LOG"
        [[ "${FAKE_NGX_RELOAD_FAIL:-0}" == "1" ]] && exit 1
        [[ -f "$state" && "$(<"$state")" == "active" ]] || exit 1
        exit 0 ;;
    enable)
        echo "systemctl $*" >>"$FAKE_LOG"
        if [[ "$svc" == "nginx" ]]; then
            [[ "$*" == *"--now"* ]] && echo active >"$state" || { [[ -f "$state" ]] || echo inactive >"$state"; }
            exit 0
        fi
        echo "systemctl UNEXPECTED $*" >>"$FAKE_LOG"; exit 0 ;;
    *) echo "systemctl UNEXPECTED $*" >>"$FAKE_LOG"; exit 0 ;;
esac
EOF

# fake nginx: `-t` fails if nginx.conf, a conf.d/*.conf or a sites-enabled file
# contains BROKEN_DIRECTIVE, if conf.d/$FAKE_NGX_FAIL_DOMAIN.conf exists, on the
# $FAKE_NGX_FAIL_NTH-th call, or always when FAKE_NGX_TEST_FAIL=1. Each call
# also logs how many legacy/conf.d site files were present (nginx-t-state).
mkstub "$STUBS/nginx" <<'EOF'
case "${1:-}" in
    -v)
        ver="${FAKE_NGX_VERSION:-1.30.2}"
        if [[ -f "${FAKE_DPKG:-/nonexistent}" ]]; then
            while read -r st pkg v; do
                [[ "$st" == ii && "$pkg" == nginx ]] && ver="${v%%-*}"
            done <"$FAKE_DPKG"
        fi
        echo "nginx version: nginx/$ver" >&2
        exit 0 ;;
    -t)
        echo "nginx -t" >>"$FAKE_LOG"
        n=0 c=0
        for f in "$EZVPS_NGINX_DIR"/sites-enabled/*; do [[ -e "$f" || -L "$f" ]] && n=$((n + 1)); done
        for f in "$EZVPS_NGINX_DIR"/conf.d/*.conf; do [[ -e "$f" ]] && c=$((c + 1)); done
        echo "nginx-t-state enabled=$n confd=$c" >>"$FAKE_LOG"
        calls=0
        [[ -f "$FAKE_LOG.tcount" ]] && calls="$(<"$FAKE_LOG.tcount")"
        calls=$((calls + 1))
        echo "$calls" >"$FAKE_LOG.tcount"
        bad=""
        [[ "${FAKE_NGX_TEST_FAIL:-0}" == "1" ]] && bad="forced failure"
        [[ "${FAKE_NGX_FAIL_NTH:-0}" == "$calls" ]] && bad="forced failure on call $calls"
        if [[ -n "${FAKE_NGX_FAIL_DOMAIN:-}" && -e "$EZVPS_NGINX_DIR/conf.d/$FAKE_NGX_FAIL_DOMAIN.conf" ]]; then
            bad="$FAKE_NGX_FAIL_DOMAIN"
        fi
        for f in "$EZVPS_NGINX_DIR/nginx.conf" "$EZVPS_NGINX_DIR"/conf.d/*.conf "$EZVPS_NGINX_DIR"/sites-enabled/*; do
            [[ -f "$f" ]] || continue
            while IFS= read -r line; do
                [[ "$line" == *BROKEN_DIRECTIVE* ]] && bad="$f"
            done <"$f"
        done
        if [[ -n "$bad" ]]; then
            echo "nginx: [emerg] unknown directive \"BROKEN_DIRECTIVE\" in ${bad}:3" >&2
            echo "nginx: configuration file /etc/nginx/nginx.conf test failed" >&2
            exit 1
        fi
        echo "nginx: the configuration file /etc/nginx/nginx.conf syntax is ok" >&2
        echo "nginx: configuration file /etc/nginx/nginx.conf test is successful" >&2
        exit 0 ;;
    *) echo "nginx UNEXPECTED $*" >>"$FAKE_LOG"; exit 0 ;;
esac
EOF

# fake dpkg state: $FAKE_DPKG holds lines "<status> <package> <version>" (e.g. "ii nginx 1.30.2-1~trixie")
mkstub "$STUBS/dpkg-query" <<'EOF'
fmt="" pats=() prev=""
for a in "$@"; do
    if [[ "$a" == -f* && "$a" != -f ]]; then # dpkg accepts -f='...' (value starts with '=')
        fmt="${a#-f}"
        fmt="${fmt#=}"
    elif [[ "$prev" == "-f" ]]; then
        fmt="$a"
    elif [[ "$a" != -* ]]; then
        pats+=("$a")
    fi
    prev="$a"
done
state="${FAKE_DPKG:-/nonexistent}"
[[ -f "$state" ]] || exit 1
found=0
while read -r st pkg ver; do
    for p in "${pats[@]}"; do
        # shellcheck disable=SC2053 # glob patterns on purpose
        if [[ "$pkg" == $p ]]; then
            out="${fmt//'${db:Status-Abbrev}'/$st }"
            out="${out//'${Package}'/$pkg}"
            out="${out//'${Version}'/$ver}"
            printf '%b' "$out"
            found=1
        fi
    done
done <"$state"
((found == 1))
EOF

# fake `apt-cache policy nginx`: the nginx.org package only when BOTH the apt source and
# the pin exist (that is what the real pin guarantees), unless FAKE_APT_IGNORE_PIN=1
mkstub "$STUBS/apt-cache" <<'EOF'
# the pin only helps when the source line names the right repository for the distro and codename
pinned=0 want="https://nginx.org/packages/${FAKE_DISTRO:-debian} ${FAKE_CODENAME:-trixie} nginx"
if [[ -f "$EZVPS_APT_DIR/preferences.d/99nginx" && -f "$EZVPS_APT_DIR/sources.list.d/nginx.list" ]]; then
    while IFS= read -r l; do [[ "$l" == *"] $want" ]] && pinned=1; done <"$EZVPS_APT_DIR/sources.list.d/nginx.list"
fi
cand="${FAKE_DISTRO_NGX_VERSION:-1.26.3-3+deb13u1}"
[[ "$pinned" == 1 && "${FAKE_APT_IGNORE_PIN:-0}" != 1 ]] && cand="${FAKE_ORG_VERSION:-1.30.2-1~trixie}"
[[ "${FAKE_APT_NOCAND:-0}" == 1 ]] && cand="(none)"
printf 'nginx:\n  Installed: (none)\n  Candidate: %s\n  Version table:\n' "$cand"
EOF

# fake gpg: --dearmor copies the file; --show-keys prints a pub/fpr pair (plus a sub/fpr pair that must be
# ignored) for every "fpr=HEX" line of the fake key file
mkstub "$STUBS/gpg" <<'EOF'
mode="" out="" last=""
prev=""
for a in "$@"; do
    case "$a" in
        --dearmor) mode=dearmor ;;
        --show-keys) mode=show ;;
    esac
    [[ "$prev" == "-o" ]] && out="$a"
    prev="$a"
    last="$a"
done
case "$mode" in
    dearmor)
        : >"$out"
        while IFS= read -r line; do printf '%s\n' "$line" >>"$out"; done <"$last"
        ;;
    show)
        while IFS= read -r line; do
            [[ "$line" == fpr=* ]] || continue
            printf 'pub:-:4096:1:0000000000000000:1716988950:::-:::scSC::::::23::0:\nfpr:::::::::%s:\n' "${line#fpr=}"
            printf 'sub:-:4096:1:1111111111111111:1716988950::::::e::::::23:\nfpr:::::::::DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF:\n'
        done <"$last"
        ;;
    *) echo "gpg UNEXPECTED $*" >>"$FAKE_LOG"; exit 2 ;;
esac
EOF


mkstub "$STUBS/curl" <<'EOF'
out="" url="" prev=""
for a in "$@"; do
    [[ "$prev" == "-o" ]] && out="$a"
    [[ "$a" == http* ]] && url="$a"
    prev="$a"
done
case "$url" in
    */install.sh)
        echo "curl DOWNLOAD $url" >>"$FAKE_LOG"
        [[ "${FAKE_DOWNLOAD_FAIL:-0}" == "1" ]] && exit 22
        cp "$WORK_FAKE_INSTALLER" "$out"
        exit 0 ;;
    */acme.sh)
        echo "curl ACME $url" >>"$FAKE_LOG"
        [[ "$*" == *"--proto =https"* && "$*" == *"--tlsv1.2"* ]] || echo "curl ACME-INSECURE" >>"$FAKE_LOG"
        [[ "${FAKE_DOWNLOAD_FAIL:-0}" == "1" ]] && exit 22
        cp "$FAKE_ACME_SCRIPT" "$out"
        exit 0 ;;
    https://nginx.org/keys/nginx_signing.key)
        echo "curl KEY $url" >>"$FAKE_LOG"
        [[ "$*" == *"--proto =https"* && "$*" == *"--tlsv1.2"* ]] || echo "curl KEY-INSECURE" >>"$FAKE_LOG"
        [[ "${FAKE_KEY_FAIL:-0}" == "1" ]] && exit 22
        cp "$FAKE_KEY_FILE" "$out"
        exit 0 ;;
    http*://127.0.0.1:*)
        hostpart="${url#*127.0.0.1:}"
        want_port="${hostpart%%/*}"
        want_path="${hostpart#*/}"
        want_path="${want_path%/}"
        echo "curl PROBE $url" >>"$FAKE_LOG"
        have_port="" have_path=""
        if [[ -f "$EZVPS_XUI_DB_DIR/x-ui.db" ]]; then
            while IFS='=' read -r k v; do
                [[ "$k" == port ]] && have_port="$v"
                [[ "$k" == path ]] && have_path="$v"
            done <"$EZVPS_XUI_DB_DIR/x-ui.db"
        fi
        if [[ -f "$FAKE_SVC" && "$(<"$FAKE_SVC")" == "active" && "$want_port" == "$have_port" ]]; then
            [[ "$want_path" == "$have_path" ]] && code=200 || code=404
            echo -n "$code"; exit 0
        fi
        echo -n "000"; exit 7 ;;
    *) echo "curl UNEXPECTED $*" >>"$FAKE_LOG"; exit 1 ;;
esac
EOF

mkstub "$STUBS/sha256sum" <<'EOF'
printf '%s  %s\n' "$FAKE_SHA" "$1"
EOF

mkstub "$STUBS/ss" <<'EOF'
arg="${*: -1}"
port="${arg##*:}"
port="${port//[!0-9]/}"
for p in $FAKE_LISTEN; do
    [[ "$p" == "$port" ]] && echo "LISTEN 0 4096 0.0.0.0:$p 0.0.0.0:*"
done
exit 0
EOF

mkstub "$STUBS/hostname" <<'EOF'
echo "192.0.2.10 198.51.100.7 "
EOF

mkstub "$STUBS/apt-get" <<'EOF'
echo "apt-get $*" >>"$FAKE_LOG"
verb="" pkgs=()
for a in "$@"; do
    [[ "$a" == -* ]] && continue
    if [[ -z "$verb" ]]; then verb="$a"; else pkgs+=("$a"); fi
done
if [[ "$verb" == install && "$*" == *"curl"* ]]; then
    cp "$STUBS_DIR/curl" "$SBOX_NOCURL_DIR/curl"
    if [[ "$*" == *"gnupg"* ]]; then
        tools="${FAKE_TOOLS_DIR:-$NGX_BOX_DIR}"
        cp "$STUBS_DIR/curl" "$tools/curl"
        cp "$STUBS_DIR/gpg" "$tools/gpg"
    fi
fi
etc="$EZVPS_NGINX_DIR"
if [[ "$verb" == update ]]; then
    [[ "${FAKE_APT_UPDATE_FAIL:-0}" == "1" ]] && exit 100
fi
if [[ "$verb" == purge ]]; then
    n=0
    for d in "$EZVPS_BACKUP_DIR"/nginx-etc.*; do [[ -e "$d" ]] && n=$((n + 1)); done
    echo "purge-state etc-backup=$n" >>"$FAKE_LOG"
    : >"$FAKE_DPKG.new"
    while read -r st pkg ver; do
        keep=1
        for p in "${pkgs[@]}"; do [[ "$p" == "$pkg" ]] && keep=0; done
        ((keep == 1)) && printf '%s %s %s\n' "$st" "$pkg" "$ver" >>"$FAKE_DPKG.new"
    done <"$FAKE_DPKG"
    mv -f "$FAKE_DPKG.new" "$FAKE_DPKG"
    rm -f "$NGX_BOX_DIR/nginx" "$FAKE_NGX_SVC" "$etc/nginx.conf" "$etc/mime.types"
    [[ "${FAKE_PURGE_WIPES_SITES:-0}" == "1" ]] && rm -rf "$etc/sites-available" "$etc/sites-enabled"
    [[ "${FAKE_PURGE_WIPES_CONFD:-0}" == "1" ]] && rm -rf "$etc/conf.d"
fi
if [[ "$verb" == install && "$*" == *"nginx"* ]]; then
    [[ "${FAKE_APT_FAIL:-0}" == "1" ]] && exit 100
    # without the repository + pin apt would choose Debian's package
    ver="${FAKE_DISTRO_NGX_VERSION:-1.26.3-3+deb13u1}"
    pinned=0 want="https://nginx.org/packages/${FAKE_DISTRO:-debian} ${FAKE_CODENAME:-trixie} nginx"
    if [[ -f "$EZVPS_APT_DIR/preferences.d/99nginx" && -f "$EZVPS_APT_DIR/sources.list.d/nginx.list" ]]; then
        while IFS= read -r l; do [[ "$l" == *"] $want" ]] && pinned=1; done <"$EZVPS_APT_DIR/sources.list.d/nginx.list"
    fi
    [[ "$pinned" == 1 && "${FAKE_APT_IGNORE_PIN:-0}" != 1 ]] && ver="${FAKE_ORG_VERSION:-1.30.2-1~trixie}"
    [[ -n "${FAKE_APT_INSTALL_VERSION:-}" ]] && ver="$FAKE_APT_INSTALL_VERSION"
    : >"$FAKE_DPKG.new"
    if [[ -f "$FAKE_DPKG" ]]; then
        while read -r st pkg v; do
            [[ "$pkg" == nginx ]] || printf '%s %s %s\n' "$st" "$pkg" "$v" >>"$FAKE_DPKG.new"
        done <"$FAKE_DPKG"
    fi
    printf 'ii nginx %s\n' "$ver" >>"$FAKE_DPKG.new"
    mv -f "$FAKE_DPKG.new" "$FAKE_DPKG"
    cp "$STUBS_DIR/nginx" "$NGX_BOX_DIR/nginx"
    mkdir -p "$etc/conf.d"
    if [[ ! -f "$etc/nginx.conf" ]]; then
        printf '%s\n' "user nginx;" "events {" "}" "http {" "    include $etc/mime.types;" "    include $etc/conf.d/*.conf;" "}" >"$etc/nginx.conf"
    fi
    if [[ "$ver" == *"~"* && ! -f "$etc/conf.d/default.conf" && ! -f "$etc/conf.d/default.conf.disabled" ]]; then
        printf '%s\n' "server {" "    listen       80;" "    server_name  localhost;" "    location / { root /usr/share/nginx/html; }" "}" >"$etc/conf.d/default.conf"
    fi
    [[ "${FAKE_NGX_NOSTART:-0}" == "1" ]] || echo active >"$FAKE_NGX_SVC"
fi
exit 0
EOF

for c in systemctl curl sha256sum ss apt-get hostname; do ln -s "$STUBS/$c" "$SBOX/$c"; done
ln -s "$STUBS/apt-get" "$SBOX_NOCURL/apt-get"
for c in systemctl sha256sum ss; do ln -s "$STUBS/$c" "$SBOX_NOCURL/$c"; done
# Nginx sandboxes: NGX_BOX has no nginx (apt-get stub "installs" it), NGX_BOX_INST
# has it, NGX_BOX_DPKG has everything but the nginx command (a package that is
# installed without the command in PATH), NGX_BOX_NOTOOLS has no curl/gpg.
NGX_BOX="$WORK/ngx-box"
NGX_BOX_INST="$WORK/ngx-box-inst"
NGX_BOX_DPKG="$WORK/ngx-box-dpkg"
NGX_BOX_NOTOOLS="$WORK/ngx-box-notools"
mkdir -p "$NGX_BOX" "$NGX_BOX_INST" "$NGX_BOX_DPKG" "$NGX_BOX_NOTOOLS"
for box in "$NGX_BOX" "$NGX_BOX_INST" "$NGX_BOX_DPKG" "$NGX_BOX_NOTOOLS"; do
    for c in systemctl ss apt-get apt-cache dpkg-query; do ln -s "$STUBS/$c" "$box/$c"; done
done
for box in "$NGX_BOX" "$NGX_BOX_INST" "$NGX_BOX_DPKG"; do
    for c in curl gpg; do ln -s "$STUBS/$c" "$box/$c"; done
done
ln -s "$STUBS/nginx" "$NGX_BOX_INST/nginx"
for c in "$CORE_BIN"/*; do
    ln -s "$c" "$SBOX/${c##*/}"
    ln -s "$c" "$SBOX_NOCURL/${c##*/}"
    for box in "$NGX_BOX" "$NGX_BOX_INST" "$NGX_BOX_DPKG" "$NGX_BOX_NOTOOLS"; do ln -s "$c" "$box/${c##*/}"; done
done
export WORK_FAKE_INSTALLER="$WORK/fake-installer.sh" FAKE_XUI_TEMPLATE="$WORK/fake-xui"
export STUBS_DIR="$STUBS" SBOX_NOCURL_DIR="$SBOX_NOCURL" NGX_BOX_DIR="$NGX_BOX"
export EZVPS_XUI_WAIT_SECONDS=0
export EZVPS_IF_INET6_FILE="$WORK/no-such-if_inet6"

# new_scn <name>: a fresh fake machine (no panel installed yet)
new_scn() {
    SCN="$WORK/scn-$1"
    rm -rf "$SCN"
    mkdir -p "$SCN"
    export EZVPS_XUI_DIR="$SCN/usr-local-x-ui" EZVPS_XUI_DB_DIR="$SCN/etc-x-ui"
    export EZVPS_STATE_DIR="$SCN/state" EZVPS_BACKUP_DIR="$SCN/backup"
    export FAKE_SVC="$SCN/svc-state" FAKE_LOG="$SCN/calls.log"
    export FAKE_LISTEN="" FAKE_SHA="$PINNED_SHA" FAKE_INSTALLER_FAIL=0 FAKE_DOWNLOAD_FAIL=0
    export FAKE_INSTALLER_ASKS=0 FAKE_RESTART_FAIL=0
    : >"$FAKE_LOG"
}
# existing_panel <port> <path> <user> <pass> [active|inactive]
existing_panel() {
    mkdir -p "$EZVPS_XUI_DIR" "$EZVPS_XUI_DB_DIR"
    cp "$FAKE_XUI_TEMPLATE" "$EZVPS_XUI_DIR/x-ui"
    printf 'port=%s\npath=%s\nuser=%s\npass=%s\ncert=\n' "$1" "$2" "$3" "$4" >"$EZVPS_XUI_DB_DIR/x-ui.db"
    echo "${5:-active}" >"$FAKE_SVC"
}
log() { cat "$FAKE_LOG"; }
log_count() { grep -cE -- "$1" "$FAKE_LOG"; }
db_has() { grep -qxF -- "$1" "$EZVPS_XUI_DB_DIR/x-ui.db"; }
state_has() { grep -qxF -- "$1" "$EZVPS_STATE_DIR/3x-ui.state"; }
backup_dirs() { find "$EZVPS_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'x-ui.*' 2>/dev/null | wc -l; }
only_backup() { find "$EZVPS_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'x-ui.*' | head -n1; }
no_panel_installed() { [[ ! -e "$EZVPS_XUI_DIR/x-ui" ]]; }
no_x_ui_calls() { [[ "$(log_count '^x-ui ')" -eq 0 ]]; }
no_download() { [[ "$(log_count 'DOWNLOAD')" -eq 0 ]]; }
only_file_with() { # only_file_with <text> <expected-file>: the text appears in exactly that one file under $SCN
    [[ "$(grep -rlF -- "$1" "$SCN" | sort)" == "$2" ]]
}

echo "-- submenu"
new_scn menu
run_ezvps "$SBOX" "2\n0\n\n0\n"
for line in " 1) Install 3x-ui" " 2) Install with 3x-ui self installer" " 3) Status" " 4) Restart" " 5) Panel info" " 6) Change password" " 0) Back"; do
    check "submenu line '${line}' is exact (clean label)" has_line "$OUT" "$line"
done
check "Back returns to the main menu" at_least_menus "$OUT" 2
check "submenu exits 0" equals "$RC" 0
run_ezvps "$SBOX" "2\nabc\n\n0\n\n0\n"
check "invalid submenu input is reported" contains "$OUT" "Invalid choice: abc"
check "invalid submenu input keeps the menu alive" equals "$RC" 0
run_ezvps "$SBOX" "2\n"
check "EOF inside the submenu exits 0" equals "$RC" 0
run_ezvps "$SBOX" "" 3x-ui
check "'ezvps 3x-ui' opens the submenu" contains "$OUT" " 6) Change password"
check "'ezvps 3x-ui' exits 0" equals "$RC" 0
check "3x-ui is no longer reported as not implemented" not_contains "$OUT" "not implemented yet"

echo "-- prechecks"
new_scn pre
OUT="$(printf '2\n1\n\n0\n\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/ubuntu2510" PATH="$SBOX" "$BASH_BIN" "$EZVPS" 2>&1)"
RC=$?
check "unsupported system (Ubuntu 25.10) is refused" contains "$OUT" "3x-ui install needs a supported system: ${OS_LIST_TEXT}; found 'ubuntu 25.10 questing'"
check "unsupported system: nothing downloaded" no_download
check "unsupported system: menu survives" equals "$RC" 0
OUT="$(printf '2\n1\nn\n\n0\n\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/debian13" PATH="$SBOX" "$BASH_BIN" "$EZVPS" 2>&1)"
check "Debian 13 passes the OS check" contains "$OUT" "will download the official 3x-ui installer"
OUT="$(printf '2\n1\nn\n\n0\n\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/ubuntu2404" PATH="$SBOX" "$BASH_BIN" "$EZVPS" 2>&1)"
check "Ubuntu 24.04 passes the OS check" contains "$OUT" "will download the official 3x-ui installer"
FAKE_LISTEN="3389"
run_ezvps "$SBOX" "2\n1\n\n0\n\n0\n"
check "busy port 3389 is refused" contains "$OUT" "Port 3389 is already in use"
check "busy port: nothing downloaded" no_download
check "busy port: no panel installed" no_panel_installed
check "busy port: menu survives" equals "$RC" 0

echo "-- default install, fresh machine"
new_scn fresh
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n"
check "shows the pinned source URL" contains "$OUT" "https://raw.githubusercontent.com/MHSanaei/3x-ui/${PINNED_TAG}/install.sh"
check "source URL is a pinned tag, not a branch" not_contains "$OUT" "/master/install.sh"
check "shows the expected sha256" contains "$OUT" "$PINNED_SHA"
check "installer downloaded exactly once" equals "$(log_count 'curl DOWNLOAD')" 1
check "installer ran with the pinned version, non-interactive, no SSL" contains "$(log)" "FAKE-INSTALLER-RAN args=${PINNED_TAG} noninteractive=1 ssl=none port=3389"
check "panel CLI: port/user/path set via its own settings command" contains "$(log)" "x-ui setting -username admin -password *** -port 3389 -webBasePath xuipanel"
check "panel CLI: certificates cleared" contains "$(log)" "x-ui cert -reset"
check "db: port 3389" db_has "port=3389"
check "db: path xuipanel" db_has "path=xuipanel"
check "db: username admin" db_has "user=admin"
check "db: password Admin123" db_has "pass=Admin123"
check "db: no certificate" db_has "cert="
check "panel service restarted once" equals "$(log_count '^systemctl restart x-ui$')" 1
check "verified the panel responds on port and path" contains "$OUT" "Verified: the panel answers on http://127.0.0.1:3389/xuipanel/ (HTTP 200)"
check "prints the change-password warning" contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
check "warns that Admin123 is a known default" contains "$OUT" "admin / Admin123 is a well-known default"
check "warns about plain HTTP" contains "$OUT" "plain HTTP"
check "points to Change password" contains "$OUT" "3x-ui -> Change password"
check "state: default mode" state_has "mode=default"
check "state: username admin" state_has "username=admin"
check "state: password still default" state_has "password_default=1"
check "state file never stores the password" not_contains "$(<"$EZVPS_STATE_DIR/3x-ui.state")" "Admin123"
check "fresh install made no backup (nothing existed)" equals "$(backup_dirs)" 0
check "returned to the menu, exit 0" equals "$RC" 0

echo "-- default install, re-run is idempotent"
FAKE_LISTEN="3389"
cp "$EZVPS_XUI_DB_DIR/x-ui.db" "$SCN/db-before"
run_ezvps "$SBOX" "2\n1\n\n0\n\n0\n"
check "re-run recognises the defaults" contains "$OUT" "already has the ezvps default settings"
check "re-run downloads nothing more" equals "$(log_count 'curl DOWNLOAD')" 1
check "re-run changes no settings" cmp -s "$SCN/db-before" "$EZVPS_XUI_DB_DIR/x-ui.db"
check "re-run makes no backup" equals "$(backup_dirs)" 0
check "re-run still warns" contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
check "re-run still verifies" contains "$OUT" "Verified: the panel answers"

echo "-- default install, cancelled and failure paths"
new_scn cancel
run_ezvps "$SBOX" "2\n1\nn\n\n0\n\n0\n"
check "declining the download changes nothing" contains "$OUT" "Cancelled. Nothing was changed."
check "declined: nothing downloaded" no_download
check "declined: no panel installed" no_panel_installed
check "declined: exit 0" equals "$RC" 0
new_scn badsha
FAKE_SHA="0000000000000000000000000000000000000000000000000000000000000000"
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n"
check "sha256 mismatch is refused" contains "$OUT" "SHA-256 mismatch"
check "sha256 mismatch: installer never ran" not_contains "$(log)" "FAKE-INSTALLER-RAN"
check "sha256 mismatch: no panel installed" no_panel_installed
check "sha256 mismatch: menu survives" equals "$RC" 0
new_scn dlfail
FAKE_DOWNLOAD_FAIL=1
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n"
check "download failure is reported" contains "$OUT" "Download failed"
check "download failure: menu survives" equals "$RC" 0
new_scn instfail
FAKE_INSTALLER_FAIL=1
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n"
check "installer failure is reported" contains "$OUT" "installer exited with status 1"
check "installer failure: no settings applied" no_x_ui_calls
check "installer failure: no default-password warning for a panel that was not set up" not_contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
check "installer failure: menu survives" equals "$RC" 0

echo "-- default install, curl missing"
new_scn nocurl
rm -f "$SBOX_NOCURL/curl"
run_ezvps "$SBOX_NOCURL" "2\n1\nn\n\n0\n\n0\n"
check "missing curl is detected" contains "$OUT" "curl is not installed"
check "declining the curl install changes nothing" contains "$OUT" "Cancelled. Nothing was changed."
check "no apt-get call without consent" equals "$(log_count '^apt-get')" 0
run_ezvps "$SBOX_NOCURL" "2\n1\ny\nn\n\n0\n\n0\n"
check "curl installed only after a yes" contains "$(log)" "apt-get install -y -q curl"
check "install continues after curl is available" contains "$OUT" "will download the official 3x-ui installer"
rm -f "$SBOX_NOCURL/curl"

echo "-- default install, existing panel"
new_scn exist_no
existing_panel 2053 oldpath testuser oldpass
FAKE_LISTEN="2053"
run_ezvps "$SBOX" "2\n1\nn\n\n0\n\n0\n"
check "existing panel is detected first" contains "$OUT" "An existing 3x-ui panel was found"
check "existing: current port is shown" contains "$OUT" "port:     2053"
check "existing: config backed up before asking" equals "$(backup_dirs)" 1
check "existing: backup holds the old settings" grep -qxF "port=2053" "$(only_backup)/db/x-ui.db"
check "existing: backup dir is mode 700" equals "$(stat -c %a "$(only_backup)")" 700
check "existing: declining leaves settings unchanged" db_has "port=2053"
check "existing: declining leaves the password unchanged" db_has "pass=oldpass"
check "existing: declining changes nothing via the CLI" contains "$(log)" "x-ui setting -show=true"
check "existing: no settings write when declined" equals "$(log_count 'x-ui setting -username')" 0
check "existing: declined, nothing downloaded" no_download
check "existing: declined, exit 0" equals "$RC" 0

new_scn exist_yes
existing_panel 2053 oldpath testuser oldpass
FAKE_LISTEN="2053"
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n"
check "existing: confirmed overwrite applies the defaults" db_has "port=3389"
check "existing: path set" db_has "path=xuipanel"
check "existing: username set" db_has "user=admin"
check "existing: password set" db_has "pass=Admin123"
check "existing: backup still holds the OLD settings" grep -qxF "port=2053" "$(only_backup)/db/x-ui.db"
check "existing: panel software is not re-downloaded" no_download
check "existing: panel restarted" equals "$(log_count '^systemctl restart x-ui$')" 1
check "existing: verified after overwrite" contains "$OUT" "Verified: the panel answers on http://127.0.0.1:3389/xuipanel/"
check "existing: warning printed" contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"

new_scn exist_busy
existing_panel 2053 oldpath testuser oldpass
FAKE_LISTEN="2053 3389"
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n"
check "existing: 3389 held by something else is refused" contains "$OUT" "Port 3389 is already in use"
check "existing: busy port leaves settings unchanged" db_has "port=2053"
check "existing: busy port makes no backup or change" equals "$(backup_dirs)" 0

new_scn exist_own
existing_panel 3389 oldpath testuser oldpass
FAKE_LISTEN="3389"
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n"
check "existing panel already on 3389 is not 'busy'" not_contains "$OUT" "already in use"
check "existing panel on 3389 gets the defaults" db_has "path=xuipanel"

echo "-- self installer"
new_scn self
FAKE_INSTALLER_ASKS=1
run_ezvps "$SBOX" "2\n2\ny\n9999\nselfuser\nselfsecret1\n\n0\n\n0\n"
check "self: shows the pinned source" contains "$OUT" "/${PINNED_TAG}/install.sh"
check "self: installer launched with only the pinned version" contains "$(log)" "FAKE-INSTALLER-RAN args=${PINNED_TAG} noninteractive= ssl= port="
check "self: installer asked its own questions (read from the user's input)" contains "$(log)" "FAKE-INSTALLER-PROMPTED"
check "self: installer's answers are used as given (port)" db_has "port=9999"
check "self: installer's answers are used as given (user)" db_has "user=selfuser"
check "self: ezvps applied no settings of its own" equals "$(log_count 'x-ui setting -username')" 0
check "self: ezvps did not clear certificates" equals "$(log_count 'x-ui cert')" 0
check "self: returns to ezvps" contains "$OUT" "Returned to ezvps."
check "self: shows status afterwards" contains "$OUT" "3x-ui status"
check "self: no default-password warning" not_contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
check "self: state records self mode" state_has "mode=self"
check "self: password never stored" only_file_with "selfsecret1" "$EZVPS_XUI_DB_DIR/x-ui.db"
check "self: returned to the menu, exit 0" equals "$RC" 0

new_scn self_no
run_ezvps "$SBOX" "2\n2\nn\n\n0\n\n0\n"
check "self: declining runs nothing" no_download
check "self: declined, exit 0" equals "$RC" 0

new_scn self_exist
existing_panel 2053 oldpath testuser oldpass
FAKE_INSTALLER_ASKS=1
run_ezvps "$SBOX" "2\n2\ny\n7777\nnewuser\nnewsecret12\n\n0\n\n0\n"
check "self: existing panel backed up first (config)" grep -qxF "port=2053" "$(only_backup)/db/x-ui.db"
check "self: existing panel backed up first (binary)" test -f "$(only_backup)/x-ui"
check "self: upgrade ran after the backup" db_has "port=7777"

new_scn self_fail
FAKE_INSTALLER_FAIL=1
run_ezvps "$SBOX" "2\n2\ny\n\n0\n\n0\n"
check "self: installer failure is reported" contains "$OUT" "installer exited with status 1"
check "self: failure still returns to ezvps" contains "$OUT" "Returned to ezvps."
check "self: failure keeps the menu alive" equals "$RC" 0

echo "-- status"
new_scn st_none
run_ezvps "$SBOX" "2\n3\n\n0\n\n0\n"
check "status: not installed" contains "$OUT" "3x-ui is not installed."
check "status: not installed, exit 0" equals "$RC" 0
new_scn st_up
existing_panel 3389 xuipanel admin Admin123
FAKE_LISTEN="3389"
run_ezvps "$SBOX" "2\n3\n\n0\n\n0\n"
check "status: service running" contains "$OUT" "x-ui - running"
check "status: port" contains "$OUT" "Port:      3389"
check "status: path" contains "$OUT" "Path:      /xuipanel/"
check "status: responds" contains "$OUT" "Responds:  yes (HTTP 200 at http://127.0.0.1:3389/xuipanel/)"
check "status: reports plain HTTP" contains "$OUT" "no (plain HTTP)"
check "status: changes nothing (no restart)" equals "$(log_count '^systemctl')" 0
echo inactive >"$FAKE_SVC"
run_ezvps "$SBOX" "2\n3\n\n0\n\n0\n"
check "status: stopped service" contains "$OUT" "x-ui - not running"
check "status: does not respond" contains "$OUT" "Responds:  NO (HTTP 000"
check "status: still exit 0" equals "$RC" 0
echo active >"$FAKE_SVC"
run_ezvps "$SBOX_NOCURL" "2\n3\n\n0\n\n0\n"
check "status: no curl degrades with a message" contains "$OUT" "unknown (curl is not installed)"
mkdir -p "$EZVPS_STATE_DIR"
printf 'mode=default\nusername=admin\npassword_default=1\n' >"$EZVPS_STATE_DIR/3x-ui.state"
run_ezvps "$SBOX" "2\n3\n\n0\n\n0\n"
check "status: nags while the default password is unchanged" contains "$OUT" "still uses the known default password"

echo "-- restart"
new_scn rs_none
run_ezvps "$SBOX" "2\n4\n\n0\n\n0\n"
check "restart: not installed" contains "$OUT" "3x-ui is not installed."
check "restart: nothing restarted" equals "$(log_count '^systemctl')" 0
new_scn rs
existing_panel 3389 xuipanel admin Admin123
echo inactive >"$FAKE_SVC"
run_ezvps "$SBOX" "2\n4\n\n0\n\n0\n"
check "restart: restarts the x-ui service" has_line "$(log)" "systemctl restart x-ui"
check "restart: ONLY that one systemctl call" equals "$(log_count '^systemctl')" 1
check "restart: no unexpected service calls" equals "$(log_count 'UNEXPECTED')" 0
check "restart: panel is back and verified" contains "$OUT" "Verified: the panel answers on http://127.0.0.1:3389/xuipanel/ (HTTP 200)"
check "restart: changes no panel settings" equals "$(log_count 'x-ui setting -username')" 0
new_scn rs_fail
existing_panel 3389 xuipanel admin Admin123
FAKE_RESTART_FAIL=1
run_ezvps "$SBOX" "2\n4\n\n0\n\n0\n"
check "restart: failure is reported" contains "$OUT" "systemctl restart x-ui failed"
check "restart: failure keeps the menu alive" equals "$RC" 0

echo "-- panel info"
new_scn info_none
run_ezvps "$SBOX" "2\n5\n\n0\n\n0\n"
check "info: not installed" contains "$OUT" "3x-ui is not installed."
new_scn info_def
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n" # default install first (also sets the state file)
run_ezvps "$SBOX" "2\n5\n\n0\n\n0\n"
check "info: URL" contains "$OUT" "http://<server-ip>:3389/xuipanel/"
check "info: port" contains "$OUT" "Port:      3389"
check "info: path" contains "$OUT" "Path:      /xuipanel/"
check "info: username" contains "$OUT" "Username:  admin"
check "info: lists this server's addresses when hostname -I works" contains "$OUT" "This server's addresses: 192.0.2.10 198.51.100.7"
check "info: default password is flagged" contains "$OUT" "still the known default"
check "info: default password comes with the warning" contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
new_scn info_self
existing_panel 9999 selfpath selfuser selfsecret1
mkdir -p "$EZVPS_STATE_DIR"
printf 'mode=self\nusername=\npassword_default=0\n' >"$EZVPS_STATE_DIR/3x-ui.state"
run_ezvps "$SBOX" "2\n5\n\n0\n\n0\n"
check "info (self): port" contains "$OUT" "Port:      9999"
check "info (self): path" contains "$OUT" "Path:      /selfpath/"
check "info (self): password is the one set during the install" contains "$OUT" "the one you set during the 3x-ui self installer"
check "info (self): not stored by ezvps" contains "$OUT" "not stored by ezvps"
check "info (self): never prints the password" not_contains "$OUT" "selfsecret1"
check "info (self): no default-password warning" not_contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
new_scn info_other
existing_panel 2053 abc testuser otherpass
run_ezvps "$SBOX" "2\n5\n\n0\n\n0\n"
check "info (unmanaged): says ezvps does not manage the password" contains "$OUT" "not managed by ezvps"
check "info (unmanaged): never prints the password" not_contains "$OUT" "otherpass"

echo "-- change password"
new_scn pw
run_ezvps "$SBOX" "2\n1\ny\n\n0\n\n0\n" # default install first
BACKUPS_BEFORE="$(backup_dirs)"
run_ezvps "$SBOX" "2\n6\nNewSecret99\nNewSecret99\n\n0\n\n0\n"
check "password: changed through the panel CLI" db_has "pass=NewSecret99"
check "password: username untouched" db_has "user=admin"
check "password: the CLI call was made with the known username" contains "$(log)" "x-ui setting -username admin -password ***"
check "password: panel restarted" equals "$(log_count '^systemctl restart x-ui$')" 2 # once at install, once now
check "password: panel verified after restart" contains "$OUT" "Verified: the panel answers"
check "password: config backed up first" equals "$(backup_dirs)" "$((BACKUPS_BEFORE + 1))"
check "password: not printed" not_contains "$OUT" "NewSecret99"
check "password: not in the call log" not_contains "$(log)" "NewSecret99"
check "password: written nowhere but the panel's own db" only_file_with "NewSecret99" "$EZVPS_XUI_DB_DIR/x-ui.db"
check "password: state no longer flags the default" state_has "password_default=0"
check "password: exit 0" equals "$RC" 0
run_ezvps "$SBOX" "2\n5\n\n0\n\n0\n"
check "password: info no longer shows the default warning" not_contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
check "password: info says ezvps does not store it" contains "$OUT" "ezvps does not store it"

new_scn pw_bad
existing_panel 3389 xuipanel admin Admin123
mkdir -p "$EZVPS_STATE_DIR"
printf 'mode=default\nusername=admin\npassword_default=1\n' >"$EZVPS_STATE_DIR/3x-ui.state"
run_ezvps "$SBOX" "2\n6\nNewSecret99\nDifferent99\n\n0\n\n0\n"
check "password: mismatch is rejected" contains "$OUT" "Passwords do not match"
check "password: mismatch changes nothing" db_has "pass=Admin123"
run_ezvps "$SBOX" "2\n6\nshort\nshort\n\n0\n\n0\n"
check "password: too short is rejected" contains "$OUT" "at least 8 characters"
check "password: too short changes nothing" db_has "pass=Admin123"
run_ezvps "$SBOX" "2\n6\nAdmin123\nAdmin123\n\n0\n\n0\n"
check "password: the known default is rejected" contains "$OUT" "well-known default"
check "password: default rejected changes nothing" db_has "pass=Admin123"
check "password: rejected attempts made no panel write" equals "$(log_count 'x-ui setting -username')" 0
check "password: rejected attempts restarted nothing" equals "$(log_count '^systemctl')" 0

new_scn pw_self
existing_panel 9999 selfpath selfuser selfsecret1
mkdir -p "$EZVPS_STATE_DIR"
printf 'mode=self\nusername=\npassword_default=0\n' >"$EZVPS_STATE_DIR/3x-ui.state"
run_ezvps "$SBOX" "2\n6\nselfuser\nAnother-Pass-1\nAnother-Pass-1\n\n0\n\n0\n"
check "password (self): explains why it needs the current username" contains "$OUT" "does not know the current username"
check "password (self): changed with the username given" db_has "pass=Another-Pass-1"
check "password (self): username kept" db_has "user=selfuser"
check "password (self): not printed" not_contains "$OUT" "Another-Pass-1"
check "password (self): written nowhere but the panel's own db" only_file_with "Another-Pass-1" "$EZVPS_XUI_DB_DIR/x-ui.db"
new_scn pw_self_cancel
existing_panel 9999 selfpath selfuser selfsecret1
mkdir -p "$EZVPS_STATE_DIR"
printf 'mode=self\nusername=\npassword_default=0\n' >"$EZVPS_STATE_DIR/3x-ui.state"
run_ezvps "$SBOX" "2\n6\n\n\n0\n\n0\n"
check "password (self): empty username cancels" contains "$OUT" "Cancelled. Nothing was changed."
check "password (self): cancel changes nothing" db_has "pass=selfsecret1"

new_scn pw_none
run_ezvps "$SBOX" "2\n6\n\n0\n\n0\n"
check "password: not installed" contains "$OUT" "3x-ui is not installed."

echo "== Nginx module (fake nginx/systemctl/apt-get/ss stubs, no network, no real nginx)"

# A tiny local HTTP server stands in for "nginx answering on port 80". Without
# python3 the checks that need it are skipped (and say so).
HAVE_PY=0
PORT_UP=1
PORT_DOWN=1 # nothing listens on port 1 of the loopback
if command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.end_headers()
    do_GET = do_HEAD
    def log_message(self, *a):
        pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
' >"$WORK/pyport" 2>/dev/null &
    PY_PID=$!
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        [[ -s "$WORK/pyport" ]] && break
        sleep 0.2
    done
    if [[ -s "$WORK/pyport" ]]; then
        PORT_UP="$(<"$WORK/pyport")"
        HAVE_PY=1
    fi
fi
check_py() { # like check, but skipped when no local HTTP server could be started
    if ((HAVE_PY)); then
        check "$@"
    else
        printf 'skip - %s (python3 not available)\n' "$1"
    fi
}

file_sum() { cksum <"$1"; }

# Fixtures: the primary-key fingerprints nginx.org publishes (as the fake gpg reads them),
# and the Debian 13 os-release (codename trixie) for the nginx.org repository line.
printf 'fpr=%s\n' 8540A6F18833A80E9C1653A42FD21310B49F6B46 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3 >"$WORK/nginx-key"
export EZVPS_OS_RELEASE="$OSD/debian13"

# new_ngx <name>: a fresh fake machine without nginx
new_ngx() {
    new_scn "ngx-$1"
    export EZVPS_NGINX_DIR="$SCN/etc-nginx" FAKE_NGX_SVC="$SCN/ngx-svc"
    export EZVPS_NGINX_HTTP_PORT="$PORT_UP" EZVPS_NGINX_WAIT_SECONDS=0
    export FAKE_NGX_FAIL_DOMAIN="" FAKE_NGX_TEST_FAIL=0 FAKE_NGX_NOSTART=0 FAKE_APT_FAIL=0
    export FAKE_NGX_RESTART_FAIL=0 FAKE_NGX_RELOAD_FAIL=0 FAKE_NGX_FAIL_NTH=0
    # nginx.org source: fake apt/dpkg/gpg state, key file and apt/keyring dirs of this scenario
    export FAKE_DPKG="$SCN/dpkg" FAKE_KEY_FILE="$WORK/nginx-key" FAKE_KEY_FAIL=0
    export EZVPS_APT_DIR="$SCN/apt" EZVPS_KEYRING_DIR="$SCN/keyrings"
    export FAKE_ORG_VERSION="1.30.2-1~trixie" FAKE_APT_INSTALL_VERSION="" FAKE_APT_IGNORE_PIN=0
    export FAKE_DISTRO=debian FAKE_CODENAME=trixie FAKE_DISTRO_NGX_VERSION="1.26.3-3+deb13u1"
    export FAKE_APT_NOCAND=0 FAKE_APT_UPDATE_FAIL=0 FAKE_PURGE_WIPES_SITES=0 FAKE_PURGE_WIPES_CONFD=0
    export FAKE_NGX_VERSION="1.30.2" FAKE_TOOLS_DIR="$NGX_BOX" NGX_BOX_DIR="$NGX_BOX"
    rm -f "$NGX_BOX/nginx" "$NGX_BOX_NOTOOLS/nginx" "$NGX_BOX_NOTOOLS/curl" "$NGX_BOX_NOTOOLS/gpg"
}
# nginx.conf fixture shaped like Debian's: mk_nginx_conf [1|0] [1|0]
#   1st: 0 = the conf.d include is missing; only a commented-out one remains
#   2nd: 0 = no `map $http_upgrade $connection_upgrade` (default 1 = present, so
#        the older Nginx tests see exactly one config test per change; the
#        "connection map" section uses 0 to test the insertion)
mk_nginx_conf() {
    {
        printf '%s\n' "user www-data;" "events {" "    worker_connections 768;" "}" "http {" "    sendfile on;" "    include $EZVPS_NGINX_DIR/mime.types;"
        if [[ "${2:-1}" == "1" ]]; then
            printf '%s\n' '    map $http_upgrade $connection_upgrade {' "        default upgrade;" "        ''      close;" "    }"
        fi
        if [[ "${1:-1}" == "1" ]]; then
            printf '%s\n' "    include $EZVPS_NGINX_DIR/conf.d/*.conf;"
        else
            printf '%s\n' "    #include $EZVPS_NGINX_DIR/conf.d/*.conf;"
        fi
        printf '%s\n' "    include $EZVPS_NGINX_DIR/sites-enabled/*;" "}"
    } >"$EZVPS_NGINX_DIR/nginx.conf"
}
ngx_layout() {
    mkdir -p "$EZVPS_NGINX_DIR/conf.d" "$EZVPS_NGINX_DIR/sites-available" "$EZVPS_NGINX_DIR/sites-enabled"
    mk_nginx_conf 1
}
# the installed package, as dpkg reports it: ngx_dpkg [version]
ngx_dpkg() { printf 'ii nginx %s\n' "${1:-1.30.2-1~trixie}" >"$FAKE_DPKG"; }
ngx_up() { ngx_layout && ngx_dpkg && echo active >"$FAKE_NGX_SVC"; }
ngx_down() { ngx_layout && ngx_dpkg && echo inactive >"$FAKE_NGX_SVC"; }
CF() { printf '%s' "$EZVPS_NGINX_DIR/conf.d/$1.conf"; }
# legacy layout (what an older ezvps wrote); used for the migration and "not touched" tests
AV() { printf '%s' "$EZVPS_NGINX_DIR/sites-available/$1"; }
EN() { printf '%s' "$EZVPS_NGINX_DIR/sites-enabled/$1"; }
# fixtures written independently of the module's own renderer
ezvps_site_text() { # ezvps_site_text <domain> <upstream>
    printf '%s\n' "# Managed by ezvps (Nginx module). fixture" "# ezvps:domain=$1" "# ezvps:upstream=$2" \
        "server {" "    listen 80;" "    server_name $1;" "    location / { proxy_pass http://$2; }" "}"
}
mk_ezvps_site() { # mk_ezvps_site <domain> <upstream>   -> conf.d/<domain>.conf
    ezvps_site_text "$1" "$2" >"$(CF "$1")"
}
mk_foreign_site() { # mk_foreign_site <file-name-without-.conf> <server_name>   -> conf.d
    printf '%s\n' "server {" "    listen 80;" "    server_name $2;" "    return 200 'hand written';" "}" >"$(CF "$1")"
}
mk_legacy_site() { # mk_legacy_site <domain> <upstream> [enable 1|0]   -> sites-available (+ symlink)
    ezvps_site_text "$1" "$2" >"$(AV "$1")"
    [[ "${3:-1}" == "1" ]] && ln -s "$(AV "$1")" "$(EN "$1")"
    return 0
}
mk_legacy_foreign() { # mk_legacy_foreign <name> <server_name> [enable 1|0] [listen line]
    printf '%s\n' "server {" "    ${4:-listen 80;}" "    server_name $2;" "    return 200 'hand written';" "}" >"$(AV "$1")"
    [[ "${3:-1}" == "1" ]] && ln -s "$(AV "$1")" "$(EN "$1")"
    return 0
}
# does nginx.conf have the conf.d include inside the http block, exactly once?
INC_RE='^[[:space:]]+include .*/conf\.d/\*\.conf;$'
has_include() { grep -qE "$INC_RE" "$1"; }
include_in_http() {
    local start inc end
    start="$(grep -n '^http {' "$1" | head -n1 | cut -d: -f1)"
    end="$(grep -n '^}' "$1" | tail -n1 | cut -d: -f1)"
    [[ "$(grep -cE "$INC_RE" "$1")" -eq 1 ]] || return 1
    inc="$(grep -nE "$INC_RE" "$1" | cut -d: -f1)"
    [[ -n "$start" && -n "$end" ]] && ((start < inc && inc < end))
}
bk_count() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name "$1" 2>/dev/null | wc -l; }
nlog_count() { grep -cE -- "$1" "$FAKE_LOG"; }
no_mutation() { [[ "$(nlog_count '^systemctl (restart|reload|start|enable)')" -eq 0 ]]; }
no_apt() { [[ "$(nlog_count '^apt-get')" -eq 0 ]]; }
file_has() { grep -qxF -- "$2" "$1"; }
file_lacks() { ! grep -qF -- "$2" "$1"; }
has_row() { printf '%s\n' "$1" | grep -qE -- "$2"; }
line_no() { grep -nE -- "$1" "$FAKE_LOG" | head -n1 | cut -d: -f1; }
runs_before() { local a b; a="$(line_no "$1")"; b="$(line_no "$2")"; [[ -n "$a" && -n "$b" ]] && ((a < b)); }
ngx_backups() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -type f -name "nginx-site-$1*" 2>/dev/null | wc -l; }
ngx_backup_file() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -type f -name "nginx-site-$1*" | head -n1; }
N="5\n" # main menu choice for Nginx

echo "-- submenu"
new_ngx menu
run_ezvps "$NGX_BOX_INST" "${N}0\n\n0\n"
for line in " 1) Install Nginx" " 2) Status" " 3) Restart" " 4) List sites" " 5) Add site" " 6) Remove site" " 0) Back"; do
    check "nginx submenu line '${line}' is exact (clean label)" has_line "$OUT" "$line"
done
check "Back returns to the main menu" at_least_menus "$OUT" 2
check "submenu exits 0" equals "$RC" 0
run_ezvps "$NGX_BOX_INST" "${N}abc\n\n0\n\n0\n"
check "invalid submenu input is reported" contains "$OUT" "Invalid choice: abc"
check "invalid submenu input keeps the menu alive" equals "$RC" 0
run_ezvps "$NGX_BOX_INST" "$N"
check "EOF inside the submenu exits 0" equals "$RC" 0
run_ezvps "$NGX_BOX_INST" "" nginx
check "'ezvps nginx' opens the submenu" contains "$OUT" " 6) Remove site"
check "nginx is no longer reported as not implemented" not_contains "$OUT" "Nginx is not implemented yet"

KR() { printf '%s' "$EZVPS_KEYRING_DIR/nginx-archive-keyring.gpg"; }
LST() { printf '%s' "$EZVPS_APT_DIR/sources.list.d/nginx.list"; }
PRF() { printf '%s' "$EZVPS_APT_DIR/preferences.d/99nginx"; }
repo_absent() { [[ ! -e "$(KR)" && ! -e "$(LST)" && ! -e "$(PRF)" ]]; }
no_key_download() { [[ "$(nlog_count '^curl KEY ')" -eq 0 ]]; }
no_apt_install_or_purge() { [[ "$(nlog_count '^apt-get (install|purge)')" -eq 0 ]]; }
nothing_installed() { no_apt_install_or_purge && repo_absent && no_mutation; }
etc_backups() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name 'nginx-etc.*' 2>/dev/null | wc -l; }
etc_backup() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name 'nginx-etc.*' | head -n1; }
FPR_A=8540A6F18833A80E9C1653A42FD21310B49F6B46
FPR_B=573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62
FPR_C=9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3

echo "-- install: an existing nginx"
new_ngx inst_have
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}1\n\n0\n\n0\n"
check "nginx.org stable is detected" contains "$OUT" "Nginx is already installed (nginx/1.30.2; nginx.org stable package 1.30.2-1~trixie)"
check "nginx.org stable is not reinstalled" contains "$OUT" "Not reinstalling"
check "nginx.org stable: apt-get is never called" no_apt
check "nginx.org stable: no key download" no_key_download
check "nginx.org stable: nothing is enabled/started/restarted" no_mutation
check "nginx.org stable: warns that the apt pin is missing" contains "$OUT" "apt pin"
check "nginx.org stable: status is reported instead" contains "$OUT" "Nginx status"
check "nginx.org stable: exit 0" equals "$RC" 0
new_ngx inst_have_pin
ngx_up
mkdir -p "$EZVPS_APT_DIR/preferences.d"
: >"$(PRF)"
run_ezvps "$NGX_BOX_INST" "${N}1\n\n0\n\n0\n"
check "with the pin in place there is no pin warning" not_contains "$OUT" "apt pin"
new_ngx inst_dpkg
ngx_dpkg
run_ezvps "$NGX_BOX_DPKG" "${N}1\n\n0\n\n0\n"
check "an installed nginx.org package without the command counts as installed" contains "$OUT" "Not reinstalling"
check "dpkg-detected nginx: apt-get is never called" no_apt
check "dpkg-detected nginx without the command is explained" contains "$OUT" "not in PATH"
new_ngx inst_manual
rm -f "$FAKE_DPKG"
ngx_layout
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "nginx without an apt package (built by hand) is not replaced" contains "$OUT" "not as an apt package"
check "built-by-hand nginx: nothing installed or removed" nothing_installed
check "built-by-hand nginx: no key download" no_key_download

echo "-- install: fresh machine, nginx.org stable"
new_ngx inst_new
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "plan: says nginx.org stable only" contains "$OUT" "ONLY from the official nginx.org STABLE repository"
check "plan: shows the repository line" contains "$OUT" "deb [signed-by=$(KR)] https://nginx.org/packages/debian trixie nginx"
check "plan: shows the key URL" contains "$OUT" "https://nginx.org/keys/nginx_signing.key"
check "plan: shows the pin" contains "$OUT" "origin nginx.org, priority 900"
check "key is downloaded over https/TLS1.2" has_line "$(log)" "curl KEY https://nginx.org/keys/nginx_signing.key"
check "key download uses --proto =https --tlsv1.2" equals "$(nlog_count 'KEY-INSECURE')" 0
check "fingerprints are verified and reported" contains "$OUT" "key fingerprint ${FPR_B}: matches the pinned nginx.org key"
check "all three pinned nginx.org keys are accepted" equals "$(count_lines "$OUT" "matches the pinned nginx.org key")" 3
check "...including the other two fingerprints" contains "$OUT" "${FPR_A}: matches"
check "...and the third" contains "$OUT" "${FPR_C}: matches"
check "keyring stored at the keyring path" file_has "$(KR)" "fpr=${FPR_B}"
check "keyring is mode 644" equals "$(stat -c %a "$(KR)")" 644
check "apt source: stable repo for the current codename, signed-by the keyring" file_has "$(LST)" "deb [signed-by=$(KR)] https://nginx.org/packages/debian trixie nginx"
check "apt source: never mainline" file_lacks "$(LST)" "mainline"
check "apt pin: all packages" file_has "$(PRF)" "Package: *"
check "apt pin: origin nginx.org" file_has "$(PRF)" "Pin: origin nginx.org"
check "apt pin: priority 900" file_has "$(PRF)" "Pin-Priority: 900"
check "pin and source exist before nginx is installed" runs_before '^apt-get update' '^apt-get install .*nginx$'
check "key is verified before apt is touched" runs_before '^curl KEY ' '^apt-get update'
check "installs the nginx package non-interactively, keeping existing config" has_line "$(log)" "apt-get install -y -q -o Dpkg::Options::=--force-confold nginx"
check "what dpkg now has is the nginx.org package" file_has "$FAKE_DPKG" "ii nginx 1.30.2-1~trixie"
check "Debian's package is never installed" file_lacks "$FAKE_DPKG" "deb13"
check "fresh install: nothing is purged" equals "$(nlog_count '^apt-get purge')" 0
check "fresh install: no /etc/nginx backup" equals "$(etc_backups)" 0
check "version is checked after the install" contains "$OUT" "Version check passes: nginx/1.30.2 (nginx.org stable)"
check "enables and starts the service" has_line "$(log)" "systemctl enable --now nginx"
check "runs the config test" contains "$(log)" "nginx -t"
check "service ends up running" equals "$(<"$FAKE_NGX_SVC")" active
check_py "verifies that nginx responds" contains "$OUT" "Verified: nginx answers on 127.0.0.1:${PORT_UP} (HTTP 200)"
check "mentions that upgrades stay on nginx.org stable" contains "$OUT" "Upgrades stay on nginx.org stable"
check "says it is HTTP only and defers HTTPS to Certificates" contains "$OUT" "Certificates module"
check "does not touch the firewall" contains "$OUT" "firewall is not changed"
check "fresh install exits 0" equals "$RC" 0
echo "-- install: re-run is a no-op"
KEYS_BEFORE="$(nlog_count '^curl KEY ')"
run_ezvps "$NGX_BOX_INST" "${N}1\n\n0\n\n0\n"
check "re-run: recognised as already installed" contains "$OUT" "Not reinstalling"
check "re-run: no second key download" equals "$(nlog_count '^curl KEY ')" "$KEYS_BEFORE"
check "re-run: exactly one install" equals "$(nlog_count '^apt-get install .*nginx$')" 1
check "re-run: pin and source exist, so no pin warning" not_contains "$OUT" "apt pin"
echo "-- install: repository files that already exist"
ngx_dpkg 1.31.0-1~trixie # simulate: an unsuitable nginx.org build is installed, source/pin/key from the first run
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "existing identical key/source/pin are left alone" equals "$(count_lines "$OUT" "already up to date")" 3
check "identical files: no apt-* backups" equals "$(bk_count 'apt-*')" 0
new_ngx inst_oldlist
mkdir -p "$EZVPS_APT_DIR/sources.list.d"
echo "deb http://nginx.org/packages/debian trixie nginx" >"$(LST)"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a different nginx.list is backed up first" file_has "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name 'apt-nginx.list.*' | head -n1)" "deb http://nginx.org/packages/debian trixie nginx"
check "a different nginx.list is replaced by the https stable line" file_has "$(LST)" "deb [signed-by=$(KR)] https://nginx.org/packages/debian trixie nginx"

echo "-- install: key and source checks (nothing may change)"
new_ngx inst_badkey
printf 'fpr=%s\n' 0123456789ABCDEF0123456789ABCDEF01234567 >"$SCN/badkey"
FAKE_KEY_FILE="$SCN/badkey"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "wrong key fingerprint is refused" contains "$OUT" "NOT a pinned nginx.org key"
check "wrong key fingerprint: refusal is explicit" contains "$OUT" "Fingerprint check FAILED"
check "wrong key fingerprint: no keyring, source or pin" repo_absent
check "wrong key fingerprint: apt is never called" no_apt
check "wrong key fingerprint: menu survives" equals "$RC" 0
new_ngx inst_extrakey
printf 'fpr=%s\nfpr=%s\n' "$FPR_B" 0123456789ABCDEF0123456789ABCDEF01234567 >"$SCN/extrakey"
FAKE_KEY_FILE="$SCN/extrakey"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a good key plus an unknown key is refused too" contains "$OUT" "Fingerprint check FAILED"
check "extra key: nothing written" repo_absent
new_ngx inst_keyfail
FAKE_KEY_FAIL=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "key download failure is reported" contains "$OUT" "Download failed: https://nginx.org/keys/nginx_signing.key"
check "key download failure: nothing written, apt untouched" repo_absent
check "key download failure: apt never called" no_apt
new_ngx inst_mainline_src
mkdir -p "$EZVPS_APT_DIR/sources.list.d"
echo "deb https://nginx.org/packages/mainline/debian trixie nginx" >"$EZVPS_APT_DIR/sources.list.d/other.list"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a configured mainline source is refused" contains "$OUT" "MAINLINE source is configured in ${EZVPS_APT_DIR}/sources.list.d/other.list"
check "mainline source: no key download, no apt, nothing written" no_key_download
check "mainline source: apt never called" no_apt
new_ngx inst_mainline_comment
mkdir -p "$EZVPS_APT_DIR/sources.list.d"
echo "#deb https://nginx.org/packages/mainline/debian trixie nginx" >"$EZVPS_APT_DIR/sources.list.d/other.list"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a commented-out mainline line is ignored" contains "$OUT" "Version check passes"
new_ngx inst_nopin
FAKE_APT_IGNORE_PIN=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "candidate that is not from nginx.org is refused" contains "$OUT" "which is not the nginx.org package"
check "candidate not from nginx.org: the pin is reported as not working" contains "$OUT" "pin is not taking effect"
check "candidate not from nginx.org: nothing installed or purged" no_apt_install_or_purge
check "candidate not from nginx.org: repository files rolled back" repo_absent
new_ngx inst_cand_main
FAKE_ORG_VERSION="1.31.0-1~trixie"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "mainline 1.31 candidate is refused" contains "$OUT" "a MAINLINE build"
check "mainline candidate: nothing installed" no_apt_install_or_purge
check "mainline candidate: repository files rolled back" repo_absent
new_ngx inst_cand_old
FAKE_ORG_VERSION="1.28.3-1~trixie"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "candidate below 1.30 is refused" contains "$OUT" "older than 1.30"
check "old candidate: nothing installed" no_apt_install_or_purge
new_ngx inst_cand_none
FAKE_APT_NOCAND=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "no candidate at all is reported" contains "$OUT" "no installation candidate"
check "no candidate: nothing installed" no_apt_install_or_purge
new_ngx inst_updfail
FAKE_APT_UPDATE_FAIL=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a failing apt-get update is reported and rolled back" contains "$OUT" "apt-get update failed"
check "failing apt-get update: repository files rolled back" repo_absent
check "failing apt-get update: nothing installed" no_apt_install_or_purge

echo "-- install: version check after the install"
new_ngx inst_v_main
FAKE_APT_INSTALL_VERSION="1.31.0-1~trixie"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "mainline build after install aborts" contains "$OUT" "VERSION CHECK FAILED: nginx/1.31.0 is a mainline build"
check "mainline build: nginx is not started" no_mutation
check "mainline build: says it aborted" contains "$OUT" "Aborting: nginx was NOT started"
check "mainline build: menu survives" equals "$RC" 0
new_ngx inst_v_old
FAKE_APT_INSTALL_VERSION="1.28.3-1~trixie"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "version below 1.30 after install aborts" contains "$OUT" "VERSION CHECK FAILED: nginx/1.28.3 is older than 1.30"
check "version below 1.30: nginx is not started" no_mutation
new_ngx inst_v_deb
FAKE_APT_INSTALL_VERSION="1.26.3-3+deb13u1"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a Debian package version after install aborts" contains "$OUT" "still the Debian package version (1.26.3-3+deb13u1)"
check "Debian package version: nginx is not started" no_mutation
new_ngx inst_v_even
FAKE_ORG_VERSION="1.32.0-1~trixie"
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a newer stable (1.32) is accepted" contains "$OUT" "Version check passes: nginx/1.32.0"

echo "-- install: declined, other failures, tools, platform"
new_ngx inst_no
run_ezvps "$NGX_BOX" "${N}1\nn\n\n0\n\n0\n"
check "declining the install changes nothing" contains "$OUT" "Cancelled. Nothing was changed."
check "declined: no key download, no apt, no files" no_key_download
check "declined: apt-get never called" no_apt
check "declined: no repository files" repo_absent
check "declined: exit 0" equals "$RC" 0
new_ngx inst_nostart
FAKE_NGX_NOSTART=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a package that does not auto-start is started by enable --now" equals "$(<"$FAKE_NGX_SVC")" active
new_ngx inst_deb
OUT="$(printf '%b' "${N}1\ny\n\n0\n\n0\n" | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/ubuntu2510" PATH="$NGX_BOX" "$BASH_BIN" "$EZVPS" 2>&1)"
RC=$?
check "unsupported system (Ubuntu 25.10) is refused" contains "$OUT" "Nginx install needs a supported system: ${OS_LIST_TEXT}; found 'ubuntu 25.10 questing'"
check "unsupported system: apt-get never called" no_apt
check "unsupported system: menu survives" equals "$RC" 0
new_ngx inst_nocodename
printf 'ID=debian\nVERSION_ID="13"\n' >"$SCN/os-nocodename"
EZVPS_OS_RELEASE="$SCN/os-nocodename" run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "missing Debian codename is refused" contains "$OUT" "Could not read the Debian codename"
check "missing codename: nothing changed" nothing_installed
new_ngx inst_aptfail
FAKE_APT_FAIL=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a failed apt install is reported" contains "$OUT" "apt-get install nginx failed"
check "a failed apt install: nothing enabled" no_mutation
check "a failed apt install: menu survives" equals "$RC" 0
new_ngx inst_tools
FAKE_TOOLS_DIR="$NGX_BOX_NOTOOLS" NGX_BOX_DIR="$NGX_BOX_NOTOOLS" run_ezvps "$NGX_BOX_NOTOOLS" "${N}1\ny\n\n0\n\n0\n"
check "missing curl/gpg are installed first (and said so in the plan)" contains "$OUT" "apt-get install curl gnupg ca-certificates"
check "missing curl/gpg: apt installs them" has_line "$(log)" "apt-get install -y -q curl gnupg ca-certificates"
check "missing curl/gpg: tools come before the key download" runs_before '^apt-get install -y -q curl' '^curl KEY '
check "missing curl/gpg: the install then goes ahead" contains "$OUT" "Version check passes"

echo "-- install: port 80 busy"
new_ngx inst_busy
FAKE_LISTEN="$PORT_UP"
run_ezvps "$NGX_BOX" "${N}1\nn\n\n0\n\n0\n"
check "busy port is warned about" contains "$OUT" "Port ${PORT_UP} is already in use by another service"
check "busy port: the listener is shown" contains "$OUT" "LISTEN 0 4096 0.0.0.0:${PORT_UP}"
check "busy port: declining installs nothing" no_apt
run_ezvps "$NGX_BOX" "${N}1\ny\ny\n\n0\n\n0\n"
check "busy port: the user may install anyway" has_line "$(log)" "apt-get install -y -q -o Dpkg::Options::=--force-confold nginx"
new_ngx inst_free
FAKE_LISTEN=""
run_ezvps "$NGX_BOX" "${N}1\nn\n\n0\n\n0\n"
check "free port: no port warning" not_contains "$OUT" "already in use"

echo "-- install: replacing a Debian nginx"
# new_deb: Debian nginx installed with ezvps sites in both layouts and a hand-written one
new_deb() {
    new_ngx "$1"
    ngx_up
    ngx_dpkg 1.26.3-3+deb13u1
    printf 'ii nginx-common 1.26.3-3+deb13u1\nii libnginx-mod-http-geoip2 1.26.3-3+deb13u1\nii unrelated-pkg 1.0\n' >>"$FAKE_DPKG"
    mk_ezvps_site example.com 127.0.0.1:3000
    mk_foreign_site handmade hand.example.com
    mk_legacy_site old.example.com 127.0.0.1:3001 1
    cp "$(CF example.com)" "$SCN/example-original"
    cp "$(AV old.example.com)" "$SCN/old-original"
}
new_deb rep
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "replace: the Debian package is called out" contains "$OUT" "not from nginx.org is installed (1.26.3-3+deb13u1; for example Debian's). It will be REPLACED"
check "replace: plan names the packages that will be purged" contains "$OUT" "the old package(s) are purged: nginx nginx-common libnginx-mod-http-geoip2"
check "replace: /etc/nginx is backed up" equals "$(etc_backups)" 1
check "replace: the backup holds the old nginx.conf" test -f "$(etc_backup)/nginx.conf"
check "replace: the backup holds the sites" test -f "$(etc_backup)/conf.d/example.com.conf" -a -f "$(etc_backup)/sites-available/old.example.com"
check "replace: backup was taken BEFORE the purge" has_line "$(log)" "purge-state etc-backup=1"
check "replace: Debian packages purged" has_line "$(log)" "apt-get purge -y -q nginx nginx-common libnginx-mod-http-geoip2"
check "replace: unrelated packages untouched" file_has "$FAKE_DPKG" "ii unrelated-pkg 1.0"
check "replace: repository and pin set up before the purge" runs_before '^apt-get update' '^apt-get purge'
check "replace: key checked before the purge" runs_before '^curl KEY ' '^apt-get purge'
check "replace: purge before the nginx.org install" runs_before '^apt-get purge' '^apt-get install .*nginx$'
check "replace: only the nginx.org package is left" file_has "$FAKE_DPKG" "ii nginx 1.30.2-1~trixie"
check "replace: Debian's nginx-common is gone" file_lacks "$FAKE_DPKG" "nginx-common"
check "replace: version check passes" contains "$OUT" "Version check passes: nginx/1.30.2 (nginx.org stable)"
check "replace: ezvps conf.d site still there, unchanged" cmp -s "$SCN/example-original" "$(CF example.com)"
check "replace: old-layout ezvps site moved to conf.d" cmp -s "$SCN/old-original" "$(CF old.example.com)"
check "replace: ...and its legacy files are gone" test ! -e "$(AV old.example.com)" -a ! -L "$(EN old.example.com)"
check "replace: hand-written site untouched" test -f "$(CF handmade)"
check "replace: the config test ran before the reload" runs_before '^nginx-t-state' '^systemctl reload nginx$'
check "replace: nginx was enabled and started" has_line "$(log)" "systemctl enable --now nginx"
check "replace: exit 0" equals "$RC" 0
new_deb rep_wipe
FAKE_PURGE_WIPES_SITES=1 FAKE_PURGE_WIPES_CONFD=1
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "replace, purge removed the sites: ezvps conf.d site restored from the backup" cmp -s "$SCN/example-original" "$(CF example.com)"
check "replace, purge removed the sites: old-layout site restored and moved to conf.d" cmp -s "$SCN/old-original" "$(CF old.example.com)"
check "replace, purge removed the sites: no legacy files left behind" test ! -e "$(AV old.example.com)" -a ! -L "$(EN old.example.com)"
check "replace, purge removed the sites: hand-written site is NOT restored" test ! -e "$(CF handmade)"
check "replace, purge removed the sites: ...but listed, with the backup path" contains "$OUT" "conf.d/handmade.conf"
check "replace, purge removed the sites: hand-written site still in the backup" test -f "$(etc_backup)/conf.d/handmade.conf"
check "replace, purge removed the sites: nginx.org default site present" test -f "$(CF default)"
check "replace, purge removed the sites: config test before reload" runs_before '^nginx-t-state' '^systemctl reload nginx$'
new_deb rep_fail
rm -f "$(AV old.example.com)" "$(EN old.example.com)" # only the conf.d site is restored here
FAKE_PURGE_WIPES_CONFD=1 FAKE_NGX_FAIL_DOMAIN="example.com"
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "replace, failing config test with the restored site: reported" contains "$OUT" "config test FAILED with the restored sites"
check "replace, failing config test: nginx is NOT reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "replace, failing config test: the restored file is removed again" test ! -e "$(CF example.com)"
check "replace, failing config test: the site is still in the backup" test -f "$(etc_backup)/conf.d/example.com.conf"
check "replace, failing config test: nginx.org stable is installed anyway" file_has "$FAKE_DPKG" "ii nginx 1.30.2-1~trixie"
check "replace, failing config test: menu survives" equals "$RC" 0
new_deb rep_nopin
FAKE_APT_IGNORE_PIN=1
SUM_ETC="$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")"
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "never over a Debian nginx without a working pin: refused" contains "$OUT" "pin is not taking effect"
check "no working pin: the Debian package is not purged" no_apt_install_or_purge
check "no working pin: dpkg still has the Debian nginx" file_has "$FAKE_DPKG" "ii nginx 1.26.3-3+deb13u1"
check "no working pin: /etc/nginx untouched" equals "$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")" "$SUM_ETC"
check "no working pin: no /etc/nginx backup was needed" equals "$(etc_backups)" 0
check "no working pin: repository files rolled back" repo_absent
check "no working pin: nginx not touched" no_mutation
new_deb rep_cand_main
FAKE_ORG_VERSION="1.31.0-1~trixie"
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "mainline candidate: the Debian nginx is left alone" no_apt_install_or_purge
check "mainline candidate: dpkg unchanged" file_has "$FAKE_DPKG" "ii nginx 1.26.3-3+deb13u1"
new_deb rep_verify
FAKE_APT_INSTALL_VERSION="1.26.3-3+deb13u1" FAKE_PURGE_WIPES_CONFD=1
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "replace, wrong version installed: aborts" contains "$OUT" "still the Debian package version"
check "replace, wrong version installed: tells where the old /etc/nginx is" contains "$OUT" "previous /etc/nginx is backed up in $(etc_backup)"
check "replace, wrong version installed: nginx not started, no site restored" test ! -e "$(CF example.com)"
check "replace, wrong version installed: nginx not started" no_mutation
new_deb rep_orgbad
ngx_dpkg 1.31.0-1~trixie
run_ezvps "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "an nginx.org mainline package is replaced by stable" contains "$OUT" "from nginx.org but is not stable 1.30+"
check "mainline nginx.org package: purged and replaced" file_has "$FAKE_DPKG" "ii nginx 1.30.2-1~trixie"
check "mainline nginx.org package: /etc/nginx backed up first" has_line "$(log)" "purge-state etc-backup=1"

echo "-- status"
new_ngx st_none
run_ezvps "$NGX_BOX" "${N}2\n\n0\n\n0\n"
check "status: not installed" contains "$OUT" "Nginx is not installed."
check "status: not installed, exit 0" equals "$RC" 0
new_ngx st_ok
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}2\n\n0\n\n0\n"
check "status: service running" contains "$OUT" "nginx - running (boot: enabled)"
check "status: config test passes" contains "$OUT" "Config test:  passes"
check_py "status: responds" contains "$OUT" "Responds:     yes (HTTP 200 on 127.0.0.1:${PORT_UP})"
check "status: version" contains "$OUT" "nginx/1.30.2"
check "status changes nothing (no restart/reload)" no_mutation
new_ngx st_down
ngx_down
EZVPS_NGINX_HTTP_PORT="$PORT_DOWN"
run_ezvps "$NGX_BOX_INST" "${N}2\n\n0\n\n0\n"
check "status: stopped service" contains "$OUT" "nginx - not running"
check "status: does not respond" contains "$OUT" "Responds:     NO"
check "status: stopped, exit 0" equals "$RC" 0
new_ngx st_bad
ngx_up
mk_foreign_site broken.example.com broken.example.com
echo "    BROKEN_DIRECTIVE on;" >>"$(CF broken.example.com)"
run_ezvps "$NGX_BOX_INST" "${N}2\n\n0\n\n0\n"
check "status: failing config test is reported" contains "$OUT" "Config test:  FAILS"
check "status: shows the nginx error" contains "$OUT" 'unknown directive "BROKEN_DIRECTIVE"'
check "status: failing config, still no reload/restart" no_mutation
check "status: failing config, menu survives" equals "$RC" 0

echo "-- restart"
new_ngx rs_none
run_ezvps "$NGX_BOX" "${N}3\n\n0\n\n0\n"
check "restart: not installed" contains "$OUT" "Nginx is not installed."
check "restart: not installed, nothing run" no_mutation
new_ngx rs_ok
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}3\n\n0\n\n0\n"
check "restart: restarts nginx" has_line "$(log)" "systemctl restart nginx"
check "restart: config test runs BEFORE the restart" runs_before '^nginx -t$' '^systemctl restart nginx$'
check "restart: exactly one restart" equals "$(nlog_count '^systemctl restart')" 1
check "restart: no reload" equals "$(nlog_count '^systemctl reload')" 0
check_py "restart: verifies nginx responds" contains "$OUT" "Verified: nginx answers"
check "restart: exit 0" equals "$RC" 0
new_ngx rs_bad
ngx_up
mk_foreign_site broken.example.com broken.example.com
echo "    BROKEN_DIRECTIVE on;" >>"$(CF broken.example.com)"
run_ezvps "$NGX_BOX_INST" "${N}3\n\n0\n\n0\n"
check "restart: failing config test is reported" contains "$OUT" "config test FAILED"
check "restart: says nginx was NOT restarted or reloaded" contains "$OUT" "NOT restarted or reloaded"
check "restart: shows the nginx error" contains "$OUT" 'unknown directive "BROKEN_DIRECTIVE"'
check "restart: a broken config is never restarted" equals "$(nlog_count '^systemctl restart')" 0
check "restart: a broken config is never reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "restart: the test did run" equals "$(nlog_count '^nginx -t$')" 1
check "restart: failing test, menu survives" equals "$RC" 0
new_ngx rs_fail
ngx_up
FAKE_NGX_RESTART_FAIL=1
run_ezvps "$NGX_BOX_INST" "${N}3\n\n0\n\n0\n"
check "restart: a failing systemctl is reported" contains "$OUT" "systemctl restart nginx failed"
check "restart: failing systemctl, menu survives" equals "$RC" 0

echo "-- list sites"
new_ngx ls_none
run_ezvps "$NGX_BOX" "${N}4\n\n0\n\n0\n"
check "list: nginx not installed" contains "$OUT" "Nginx is not installed."
new_ngx ls_empty
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}4\n\n0\n\n0\n"
check "list: no sites" contains "$OUT" "(none)"
new_ngx ls
ngx_up
mk_ezvps_site example.com 127.0.0.1:3000
mk_ezvps_site api.example.com 127.0.0.1:8080
mk_foreign_site legacy old.example.org
ln -s "$SCN/does-not-exist" "$(CF dangling.example.com)"
printf 'server_name notes.example.com;\n' >"$EZVPS_NGINX_DIR/conf.d/notes.txt"
printf 'server { server_name hidden.example.com; }\n' >"$EZVPS_NGINX_DIR/conf.d/old.conf.disabled"
mk_legacy_foreign default _ 1 # Debian's own default site: not an ezvps site, not listed
mk_legacy_foreign spare.example.com spare.example.com 0
SUM_CONF="$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")"
run_ezvps "$NGX_BOX_INST" "${N}4\n\n0\n\n0\n"
check "list: header names conf.d" contains "$OUT" "Sites (${EZVPS_NGINX_DIR}/conf.d/*.conf):"
check "list: ezvps site shows domain and upstream" has_row "$OUT" '^  example\.com\.conf +example\.com +127\.0\.0\.1:3000 +ezvps$'
check "list: second ezvps site" has_row "$OUT" '^  api\.example\.com\.conf +api\.example\.com +127\.0\.0\.1:8080 +ezvps$'
check "list: other conf.d file shows its server_name, no upstream" has_row "$OUT" '^  legacy\.conf +old\.example\.org +- +not ezvps$'
check "list: broken symlink is flagged" has_row "$OUT" 'dangling\.example\.com\.conf .*broken symlink'
check "list: files that are not *.conf are ignored" not_contains "$OUT" "notes"
check "list: *.conf.disabled is ignored" not_contains "$OUT" "hidden.example.com"
check "list: sites-enabled/sites-available are not read for listing" not_contains "$OUT" "spare.example.com"
check "list: Debian default site is not listed" not_contains "$(printf '%s\n' "$OUT" | grep -E '^  default')" "default"
check "list: no migration prompt without legacy ezvps sites" not_contains "$OUT" "old layout"
check "list: nginx.conf with the include is left alone" equals "$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")" "$SUM_CONF"
check "list changes nothing" no_mutation
check "list runs no config test" equals "$(nlog_count '^nginx -t$')" 0
check "list: exit 0" equals "$RC" 0
new_ngx ls_inc
ngx_up
mk_nginx_conf 0
SUM_CONF="$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")"
run_ezvps "$NGX_BOX_INST" "${N}4\n\n0\n\n0\n"
check "list: missing conf.d include is reported" contains "$OUT" "does not include ${EZVPS_NGINX_DIR}/conf.d/*.conf"
check "list: read-only even when the include is missing" equals "$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")" "$SUM_CONF"
check "list: missing include, no backup" equals "$(bk_count 'nginx.conf.*')" 0

echo "-- add site"
new_ngx add
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}5\nExample.COM\n127.0.0.1:3000\n\n0\n\n0\n"
F="$(CF example.com)"
check "add: site file is conf.d/<domain>.conf (domain lower-cased)" test -f "$F"
check "add: a plain file, not a symlink" test ! -L "$F"
check "add: nothing created in sites-available" dir_empty_or_missing "$EZVPS_NGINX_DIR/sites-available"
check "add: nothing created in sites-enabled" dir_empty_or_missing "$EZVPS_NGINX_DIR/sites-enabled"
check "add: marker with the domain" file_has "$F" "# ezvps:domain=example.com"
check "add: marker with the upstream" file_has "$F" "# ezvps:upstream=127.0.0.1:3000"
check "add: server_name" file_has "$F" "    server_name example.com;"
check "add: reverse proxy to the upstream" file_has "$F" "        proxy_pass http://127.0.0.1:3000;"
# shellcheck disable=SC2016 # $host is a literal nginx variable
check "add: forwards the Host header" file_has "$F" '        proxy_set_header Host $host;'
check "add: HTTP only (listens on 80)" file_has "$F" "    listen 80;"
check "add: IPv6 listener only when the kernel has IPv6 (not here)" file_lacks "$F" "[::]:80"
check "add: no TLS directives in the file" file_lacks "$F" "ssl"
check "add: no port 443 in the file" file_lacks "$F" "443"
check "add: only the one site file exists in conf.d" equals "$(find "$EZVPS_NGINX_DIR/conf.d" -mindepth 1 | wc -l)" 1
check "add: no temp file left in conf.d" equals "$(find "$EZVPS_NGINX_DIR/conf.d" -name '.*' | wc -l)" 0
check "add: config test ran" equals "$(nlog_count '^nginx -t$')" 1
check "add: config test ran BEFORE the reload" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "add: nginx reloaded once" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "add: no restart" equals "$(nlog_count '^systemctl restart')" 0
check "add: tells the user to use Certificates for HTTPS" contains "$OUT" "use Certificates -> Issue certificate"
check "add: says HTTP only" contains "$OUT" "HTTP only"
check "add: warns that nothing listens on the upstream yet" contains "$OUT" "Nothing is listening on 127.0.0.1:3000"
check "add: nothing existed, so no site backup" equals "$(ngx_backups example.com)" 0
check "add: nginx.conf already had the include: not touched, no backup" equals "$(bk_count 'nginx.conf.*')" 0
check "add: exit 0" equals "$RC" 0
SUM="$(file_sum "$F")"

echo "-- add site: no duplicates"
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "add again: recognised as existing" contains "$OUT" "already exists with the same upstream"
check "add again: file unchanged" equals "$(file_sum "$F")" "$SUM"
check "add again: still a single site file" equals "$(find "$EZVPS_NGINX_DIR/conf.d" -type f | wc -l)" 1
check "add again: no second reload" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "add again: no backup" equals "$(ngx_backups example.com)" 0
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:4000\nn\n\n0\n\n0\n"
check "different upstream: finds the existing site and asks before overwriting" contains "$OUT" "A site for example.com already exists"
check "different upstream, declined: cancelled" contains "$OUT" "Cancelled. Nothing was changed."
check "different upstream, declined: file unchanged" equals "$(file_sum "$F")" "$SUM"
check "different upstream, declined: no backup" equals "$(ngx_backups example.com)" 0
check "different upstream, declined: no reload" equals "$(nlog_count '^systemctl reload nginx$')" 1
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:4000\ny\n\n0\n\n0\n"
check "overwrite confirmed: new upstream written" file_has "$F" "# ezvps:upstream=127.0.0.1:4000"
check "overwrite confirmed: proxy_pass updated" file_has "$F" "        proxy_pass http://127.0.0.1:4000;"
check "overwrite confirmed: old file backed up first" equals "$(ngx_backups example.com)" 1
check "overwrite confirmed: backup holds the OLD upstream" file_has "$(ngx_backup_file example.com)" "# ezvps:upstream=127.0.0.1:3000"
check "overwrite confirmed: backup dir is mode 700" equals "$(stat -c %a "$EZVPS_BACKUP_DIR")" 700
check "overwrite confirmed: reloaded after the test" equals "$(nlog_count '^systemctl reload nginx$')" 2
check "overwrite confirmed: still a single site file" equals "$(find "$EZVPS_NGINX_DIR/conf.d" -type f | wc -l)" 1

echo "-- add site: IPv6 listener follows the kernel"
new_ngx add_v6
ngx_up
: >"$SCN/if_inet6"
EZVPS_IF_INET6_FILE="$SCN/if_inet6" run_ezvps "$NGX_BOX_INST" "${N}5\nv6.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "add: IPv6 listener written when IPv6 exists" file_has "$(CF v6.example.com)" "    listen [::]:80;"
check "add: IPv4 listener always written" file_has "$(CF v6.example.com)" "    listen 80;"

echo "-- add site: domain sanitising and input validation"
new_ngx add_bad
ngx_up
for bad in "not a domain" "exam ple.com" "localhost" "-bad.example.com" "a..example.com" "exa_mple.com" "x.example.com;rm" "exämple.com" "a*.example.com"; do
    run_ezvps "$NGX_BOX_INST" "${N}5\n${bad}\n127.0.0.1:3000\n\n0\n\n0\n"
    check "invalid domain '${bad}' is rejected" contains "$OUT" "is not a valid domain name"
done
for bad in "../etc/passwd" "example.com/x" "/etc/passwd" "a/b.example.com" "..%2f.example.com/"; do
    run_ezvps "$NGX_BOX_INST" "${N}5\n${bad}\n127.0.0.1:3000\n\n0\n\n0\n"
    check "domain with a path separator '${bad}' is rejected" contains "$OUT" "contains a path separator"
done
for bad in "127.0.0.1" "127.0.0.1:0" "127.0.0.1:99999" "192.0.2.256:80" "https://127.0.0.1:443" "host name:80" ":80" "127.0.0.1:80x"; do
    run_ezvps "$NGX_BOX_INST" "${N}5\nok.example.com\n${bad}\n\n0\n\n0\n"
    check "invalid upstream '${bad}' is rejected" equals "$([[ "$OUT" == *"Upstream must look like"* || "$OUT" == *"Not a valid"* || "$OUT" == *"Port must be"* || "$OUT" == *"plain http upstreams"* ]] && echo yes)" yes
done
check "invalid input created no *.conf file anywhere (only nginx.conf)" equals "$(find "$SCN" -name '*.conf' | wc -l)" 1
check "invalid input reloaded nothing" no_mutation
check "invalid input ran no config test" equals "$(nlog_count '^nginx -t$')" 0
run_ezvps "$NGX_BOX_INST" "${N}5\n\n\n0\n\n0\n"
check "empty domain cancels" contains "$OUT" "Cancelled. Nothing was changed."
new_ngx add_forms
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}5\na.example.com\nhttp://localhost:8080/\n\n0\n\n0\n"
check "upstream with http:// and trailing slash is normalised" file_has "$(CF a.example.com)" "# ezvps:upstream=localhost:8080"
run_ezvps "$NGX_BOX_INST" "${N}5\nb.example.com\n[::1]:3000\n\n0\n\n0\n"
check "IPv6 upstream is accepted" file_has "$(CF b.example.com)" "# ezvps:upstream=[::1]:3000"
run_ezvps "$NGX_BOX_INST" "${N}5\nc.example.com\nbackend.internal:9000\n\n0\n\n0\n"
check "hostname upstream is accepted" file_has "$(CF c.example.com)" "        proxy_pass http://backend.internal:9000;"
run_ezvps "$NGX_BOX_INST" "${N}5\nxn--bcher-kva.example\n192.0.2.5:0080\n\n0\n\n0\n"
check "punycode domain and leading-zero port are accepted and normalised" file_has "$(CF xn--bcher-kva.example)" "# ezvps:upstream=192.0.2.5:80"

echo "-- add site: conflicts, foreign files, failing config test"
new_ngx add_conf
ngx_up
mk_foreign_site legacy taken.example.com
run_ezvps "$NGX_BOX_INST" "${N}5\ntaken.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "domain served by another conf.d file is refused" contains "$OUT" "already served by another nginx site file: conf.d/legacy.conf"
check "conflict: no new site file" test ! -e "$(CF taken.example.com)"
check "conflict: nothing reloaded" no_mutation
new_ngx add_conf2
ngx_up
mk_legacy_foreign handmade taken.example.com 1
run_ezvps "$NGX_BOX_INST" "${N}5\ntaken.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "domain served by a legacy sites-enabled file is refused too" contains "$OUT" "already served by another nginx site file: sites-enabled/handmade"
check "legacy conflict: no new site file" test ! -e "$(CF taken.example.com)"
new_ngx add_foreign
ngx_up
mk_foreign_site hand.example.com hand.example.com
cp "$(CF hand.example.com)" "$SCN/hand-original"
run_ezvps "$NGX_BOX_INST" "${N}5\nhand.example.com\n127.0.0.1:3000\ny\n\n0\n\n0\n"
check "existing hand-written file for the domain: asks first" contains "$OUT" "NOT created by ezvps"
check "existing hand-written file: backed up before overwrite" cmp -s "$SCN/hand-original" "$(ngx_backup_file hand.example.com)"
check "existing hand-written file: replaced by the ezvps site" file_has "$(CF hand.example.com)" "# ezvps:domain=hand.example.com"
new_ngx add_rb
ngx_up
FAKE_NGX_FAIL_DOMAIN="bad.example.com"
run_ezvps "$NGX_BOX_INST" "${N}5\nbad.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "failing config test is reported" contains "$OUT" "config test FAILED after adding bad.example.com"
check "failing config test: nginx is NOT reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "failing config test: no restart either" equals "$(nlog_count '^systemctl restart')" 0
check "failing config test: new file removed again" test ! -e "$(CF bad.example.com)"
check "failing config test: conf.d is empty again" dir_empty_or_missing "$EZVPS_NGINX_DIR/conf.d"
check "failing config test: says it rolled back" contains "$OUT" "Rolled back"
check "failing config test: the test did run" equals "$(nlog_count '^nginx -t$')" 1
check "failing config test: menu survives" equals "$RC" 0
new_ngx add_rb2
ngx_up
mk_ezvps_site bad.example.com 127.0.0.1:3000
SUM="$(file_sum "$(CF bad.example.com)")"
FAKE_NGX_FAIL_DOMAIN="bad.example.com"
run_ezvps "$NGX_BOX_INST" "${N}5\nbad.example.com\n127.0.0.1:4000\ny\n\n0\n\n0\n"
check "failed overwrite: previous file restored byte for byte" equals "$(file_sum "$(CF bad.example.com)")" "$SUM"
check "failed overwrite: not reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "failed overwrite: backup was taken first" equals "$(ngx_backups bad.example.com)" 1
new_ngx add_none
run_ezvps "$NGX_BOX" "${N}5\n\n0\n\n0\n"
check "add: nginx not installed" contains "$OUT" "Nginx is not installed."
new_ngx add_stopped
ngx_down
run_ezvps "$NGX_BOX_INST" "${N}5\nidle.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "add while nginx is stopped: site is written" test -f "$(CF idle.example.com)"
check "add while nginx is stopped: nothing is reloaded or started" no_mutation
check "add while nginx is stopped: user is told" contains "$OUT" "nginx is not running, so nothing was reloaded"

echo "-- add site: nginx.conf must include conf.d"
new_ngx inc
ngx_up
mk_nginx_conf 0
cp "$EZVPS_NGINX_DIR/nginx.conf" "$SCN/nginx-conf-original"
run_ezvps "$NGX_BOX_INST" "${N}5\ninc.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "missing include: reported" contains "$OUT" "does not include ${EZVPS_NGINX_DIR}/conf.d/*.conf"
check "missing include: nginx.conf backed up first, byte for byte" cmp -s "$SCN/nginx-conf-original" "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -type f -name 'nginx.conf.*' | head -n1)"
check "missing include: exactly one nginx.conf backup" equals "$(bk_count 'nginx.conf.*')" 1
check "missing include: include added" has_include "$EZVPS_NGINX_DIR/nginx.conf"
check "missing include: added inside the http block, once" include_in_http "$EZVPS_NGINX_DIR/nginx.conf"
check "missing include: the commented-out include was not mistaken for a real one" equals "$(grep -c 'conf.d/\*.conf;' "$EZVPS_NGINX_DIR/nginx.conf")" 2
check "missing include: the rest of nginx.conf is unchanged" equals "$(grep -vc 'conf.d' "$EZVPS_NGINX_DIR/nginx.conf")" "$(grep -vc 'conf.d' "$SCN/nginx-conf-original")"
check "missing include: config test ran for it and for the site" equals "$(nlog_count '^nginx -t$')" 2
check "missing include: site written after the include" test -f "$(CF inc.example.com)"
check "missing include: reloaded once, after the tests" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "missing include: reload came after both tests" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "missing include: exit 0" equals "$RC" 0
run_ezvps "$NGX_BOX_INST" "${N}5\ninc2.example.com\n127.0.0.1:3001\n\n0\n\n0\n"
check "include already present: not added a second time" include_in_http "$EZVPS_NGINX_DIR/nginx.conf"
check "include already present: no further nginx.conf backup" equals "$(bk_count 'nginx.conf.*')" 1
new_ngx inc_nodir
ngx_up
rm -rf "$EZVPS_NGINX_DIR/conf.d"
mk_nginx_conf 0
run_ezvps "$NGX_BOX_INST" "${N}5\nd.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "missing conf.d directory and include: both fixed, site added" test -f "$(CF d.example.com)"
new_ngx inc_fail
ngx_up
mk_nginx_conf 0
cp "$EZVPS_NGINX_DIR/nginx.conf" "$SCN/nginx-conf-original"
FAKE_NGX_TEST_FAIL=1
run_ezvps "$NGX_BOX_INST" "${N}5\ninc.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "include fix with a failing config test: reported" contains "$OUT" "config test FAILED after adding the conf.d include"
check "include fix with a failing config test: nginx.conf restored byte for byte" cmp -s "$SCN/nginx-conf-original" "$EZVPS_NGINX_DIR/nginx.conf"
check "include fix with a failing config test: nginx NOT reloaded" no_mutation
check "include fix with a failing config test: no site written" test ! -e "$(CF inc.example.com)"
check "include fix with a failing config test: backup kept" equals "$(bk_count 'nginx.conf.*')" 1
check "include fix with a failing config test: menu survives" equals "$RC" 0
new_ngx inc_nohttp
ngx_up
printf '%s\n' "events {" "}" >"$EZVPS_NGINX_DIR/nginx.conf"
run_ezvps "$NGX_BOX_INST" "${N}5\nh.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "nginx.conf without an http block: explained, nothing guessed" contains "$OUT" "Found no http block"
check "nginx.conf without an http block: no site written" test ! -e "$(CF h.example.com)"
check "nginx.conf without an http block: nothing reloaded" no_mutation
new_ngx inc_noconf
ngx_up
rm -f "$EZVPS_NGINX_DIR/nginx.conf"
run_ezvps "$NGX_BOX_INST" "${N}5\nh.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "missing nginx.conf: reported, no site written" contains "$OUT" "nginx.conf not found"

echo "-- add site: nginx.org default site (conf.d/default.conf)"
new_ngx def
ngx_up
mk_foreign_site default localhost
cp "$(CF default)" "$SCN/default-original"
mk_legacy_foreign other.example.com other.example.com 1
run_ezvps "$NGX_BOX_INST" "${N}5\ndef.example.com\n127.0.0.1:3000\nn\n\n0\n\n0\n"
check "default site: conflict is warned about" contains "$OUT" "default site (${EZVPS_NGINX_DIR}/conf.d/default.conf) may conflict with def.example.com: it listens on port 80 too"
check "default site: declined, still in place" cmp -s "$SCN/default-original" "$(CF default)"
check "default site: declined, not renamed" test ! -e "$(CF default).disabled"
check "default site: declined, no backup" equals "$(bk_count 'nginx-default-conf.*')" 0
check "default site: declined, the site is still added" test -f "$(CF def.example.com)"
new_ngx def2
ngx_up
mk_foreign_site default localhost
cp "$(CF default)" "$SCN/default-original"
mk_legacy_foreign other.example.com other.example.com 1
run_ezvps "$NGX_BOX_INST" "${N}5\ndef.example.com\n127.0.0.1:3000\ny\n\n0\n\n0\n"
check "default site: confirmed, default.conf is no longer loaded" test ! -e "$(CF default)"
check "default site: ...it is renamed, not deleted" cmp -s "$SCN/default-original" "$(CF default).disabled"
check "default site: backup taken, identical to the original" cmp -s "$SCN/default-original" "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name 'nginx-default-conf.*' | head -n1)"
check "default site: other files in sites-enabled are untouched" test -L "$(EN other.example.com)"
check "default site: the site is added" test -f "$(CF def.example.com)"
check "default site: one config test, then one reload" equals "$(nlog_count '^nginx -t$')" 1
check "default site: reloaded after the test" runs_before '^nginx -t$' '^systemctl reload nginx$'
new_ngx def3
ngx_up
mk_foreign_site default localhost
cp "$(CF default)" "$SCN/default-original"
FAKE_NGX_FAIL_DOMAIN="def.example.com"
run_ezvps "$NGX_BOX_INST" "${N}5\ndef.example.com\n127.0.0.1:3000\ny\n\n0\n\n0\n"
check "default site, failing test: not reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "default site, failing test: default.conf restored byte for byte" cmp -s "$SCN/default-original" "$(CF default)"
check "default site, failing test: not left renamed" test ! -e "$(CF default).disabled"
check "default site, failing test: new site removed" test ! -e "$(CF def.example.com)"
new_ngx def4
ngx_up
printf '%s\n' "server {" "    listen 8080;" "    server_name internal.example.com;" "}" >"$(CF default)"
run_ezvps "$NGX_BOX_INST" "${N}5\nquiet.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "a default.conf that does not touch port 80 or the domain: no question" not_contains "$OUT" "default site"
check "...and it is left alone" test -f "$(CF default)"
new_ngx def5
ngx_up
printf '%s\n' "server {" "    listen 8080;" "    server_name quiet.example.com;" "}" >"$(CF default)"
run_ezvps "$NGX_BOX_INST" "${N}5\nquiet.example.com\n127.0.0.1:3000\nn\n\n0\n\n0\n"
check "default.conf listing the domain itself is a conflict (and not a refusal)" contains "$OUT" "it also serves quiet.example.com"
new_ngx def6
ngx_up
mk_foreign_site default localhost
ln -s "$SCN/does-not-matter" "$SCN/link-target" 2>/dev/null
mv "$(CF default)" "$SCN/real-default"
ln -s "$SCN/real-default" "$(CF default)"
run_ezvps "$NGX_BOX_INST" "${N}5\nlink.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "a symlinked default.conf is never touched" contains "$OUT" "It is a symlink, so ezvps will not touch it"
check "...the link is still there" test -L "$(CF default)"
new_ngx def7
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}5\nnodefault.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "no default.conf: no question" not_contains "$OUT" "default site"

echo "-- remove site"
new_ngx rm
ngx_up
mk_ezvps_site gone.example.com 127.0.0.1:3000
mk_ezvps_site keep.example.com 127.0.0.1:3001
mk_legacy_foreign default _ 1 "listen 80 default_server;"
cp "$(CF gone.example.com)" "$SCN/gone-original"
run_ezvps "$NGX_BOX_INST" "${N}6\nnothere.example.com\n\n0\n\n0\n"
check "remove: unknown site" contains "$OUT" "No site named nothere.example.com in ${EZVPS_NGINX_DIR}/conf.d"
check "remove: unknown site changes nothing" no_mutation
run_ezvps "$NGX_BOX_INST" "${N}6\ngone.example.com\nn\n\n0\n\n0\n"
check "remove: shows the site and asks for confirmation" contains "$OUT" "Site gone.example.com:"
check "remove: declining is reported" contains "$OUT" "Cancelled. Nothing was changed."
check "remove: declined, site file kept" test -f "$(CF gone.example.com)"
check "remove: declined, no backup" equals "$(ngx_backups gone.example.com)" 0
check "remove: declined, nothing reloaded" no_mutation
run_ezvps "$NGX_BOX_INST" "${N}6\nGONE.example.com\ny\n\n0\n\n0\n"
check "remove: site file deleted" test ! -e "$(CF gone.example.com)"
check "remove: backup kept and identical to the original" cmp -s "$SCN/gone-original" "$(ngx_backup_file gone.example.com)"
check "remove: exactly one backup" equals "$(ngx_backups gone.example.com)" 1
check "remove: config test ran after the removal" equals "$(nlog_count '^nginx -t$')" 1
check "remove: test before reload" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "remove: reloaded once" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "remove: other sites untouched" test -f "$(CF keep.example.com)"
check "remove: files in sites-enabled are never deleted" test -L "$(EN default)"
check "remove: says so" contains "$OUT" "removed. Config test passes."
new_ngx rm_fail
ngx_up
mk_ezvps_site gone.example.com 127.0.0.1:3000
SUM="$(file_sum "$(CF gone.example.com)")"
FAKE_NGX_TEST_FAIL=1
run_ezvps "$NGX_BOX_INST" "${N}6\ngone.example.com\ny\n\n0\n\n0\n"
check "remove, failing config test: reported" contains "$OUT" "config test FAILED after removing gone.example.com"
check "remove, failing config test: NOT reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "remove, failing config test: site restored byte for byte" equals "$(file_sum "$(CF gone.example.com)")" "$SUM"
check "remove, failing config test: backup still exists" equals "$(ngx_backups gone.example.com)" 1
check "remove, failing config test: menu survives" equals "$RC" 0
new_ngx rm_foreign
ngx_up
mk_foreign_site hand.example.com hand.example.com
run_ezvps "$NGX_BOX_INST" "${N}6\nhand.example.com\nn\n\n0\n\n0\n"
check "remove: warns when the site was not created by ezvps" contains "$OUT" "NOT created by ezvps"
new_ngx rm_bad
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}6\n../etc/passwd\n\n0\n\n0\n"
check "remove: path traversal rejected" contains "$OUT" "contains a path separator"
run_ezvps "$NGX_BOX_INST" "${N}6\nbad_name.com\n\n0\n\n0\n"
check "remove: invalid domain rejected" contains "$OUT" "is not a valid domain name"
new_ngx rm_none
run_ezvps "$NGX_BOX" "${N}6\n\n0\n\n0\n"
check "remove: nginx not installed" contains "$OUT" "Nginx is not installed."

echo "-- migration from sites-available"
# new_mig: two enabled ezvps sites, one disabled ezvps site, one hand-written enabled site
new_mig() {
    new_ngx "$1"
    ngx_up
    mk_legacy_site a.example.com 127.0.0.1:3000 1
    mk_legacy_site b.example.com 127.0.0.1:3001 1
    mk_legacy_site c.example.com 127.0.0.1:3002 0
    mk_legacy_foreign hand.example.com hand.example.com 1
    cp "$(AV a.example.com)" "$SCN/a-original"
    cp "$(AV b.example.com)" "$SCN/b-original"
}
new_mig mig
run_ezvps "$NGX_BOX_INST" "${N}4\ny\n\n0\n\n0\n"
check "migration: the legacy sites are offered" contains "$OUT" "${EZVPS_NGINX_DIR}/sites-available/a.example.com  ->  ${EZVPS_NGINX_DIR}/conf.d/a.example.com.conf"
check "migration: explains what moving does before asking" contains "$OUT" "Moving backs the files up, copies them to conf.d"
check "migration: a.example.com is in conf.d, identical" cmp -s "$SCN/a-original" "$(CF a.example.com)"
check "migration: b.example.com is in conf.d, identical" cmp -s "$SCN/b-original" "$(CF b.example.com)"
check "migration: sites-available file removed" test ! -e "$(AV a.example.com)" -a ! -e "$(AV b.example.com)"
check "migration: sites-enabled symlink removed" test ! -L "$(EN a.example.com)" -a ! -L "$(EN b.example.com)"
check "migration: backup of the sites-available file, identical" cmp -s "$SCN/a-original" "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -type f -name 'nginx-legacy-a.example.com.[0-9]*' | head -n1)"
check "migration: backup of the sites-enabled symlink" test -L "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name 'nginx-legacy-a.example.com.enabled.*' | head -n1)"
check "migration: the files were backed up before they were removed" equals "$(bk_count 'nginx-legacy-*')" 4
check "migration: config test BEFORE the legacy files are removed (they were still there)" has_line "$(log)" "nginx-t-state enabled=3 confd=2"
check "migration: config test again AFTER the removal" has_line "$(log)" "nginx-t-state enabled=1 confd=2"
check "migration: test with both in place came first" runs_before '^nginx-t-state enabled=3 ' '^nginx-t-state enabled=1 '
check "migration: reload only after the final test" runs_before '^nginx-t-state enabled=1 ' '^systemctl reload nginx$'
check "migration: exactly one reload" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "migration: a disabled legacy site is left alone" test -f "$(AV c.example.com)"
check "migration: ...and not switched on in conf.d" test ! -e "$(CF c.example.com)"
check "migration: hand-written sites are not touched" test -L "$(EN hand.example.com)" -a -f "$(AV hand.example.com)"
check "migration: the site that stayed is warned about" contains "$OUT" "c.example.com (not enabled"
check "migration: list now shows the moved sites" has_row "$OUT" '^  a\.example\.com\.conf +a\.example\.com +127\.0\.0\.1:3000 +ezvps$'
check "migration: exit 0" equals "$RC" 0
run_ezvps "$NGX_BOX_INST" "${N}4\n\n0\n\n0\n"
check "migration: re-run has nothing to move and asks nothing" not_contains "$OUT" "ezvps sites from the old layout were found"
check "migration: re-run changes nothing (still one reload)" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "migration: re-run makes no new backups" equals "$(bk_count 'nginx-legacy-*')" 4

new_mig mig_no
SUMS="$(file_sum "$(AV a.example.com)") $(file_sum "$(AV b.example.com)")"
run_ezvps "$NGX_BOX_INST" "${N}4\nn\n\n0\n\n0\n"
check "migration declined: told that files were left alone" contains "$OUT" "Migration declined. Those files were left alone."
check "migration declined: warned about the legacy layout" contains "$OUT" "still in the legacy layout"
check "migration declined: the legacy sites are named" contains "$OUT" "b.example.com"
check "migration declined: files unchanged" equals "$(file_sum "$(AV a.example.com)") $(file_sum "$(AV b.example.com)")" "$SUMS"
check "migration declined: symlinks unchanged" test -L "$(EN a.example.com)" -a -L "$(EN b.example.com)"
check "migration declined: nothing in conf.d" dir_empty_or_missing "$EZVPS_NGINX_DIR/conf.d"
check "migration declined: no backup, no test, no reload" equals "$(bk_count '*')$(nlog_count '^nginx -t$')$(nlog_count '^systemctl')" 000
run_ezvps "$NGX_BOX_INST" "${N}6\nn\na.example.com\n\n0\n\n0\n"
check "migration declined: Remove site does not touch the legacy site" contains "$OUT" "No site named a.example.com in ${EZVPS_NGINX_DIR}/conf.d"
run_ezvps "$NGX_BOX_INST" "${N}5\nn\na.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "migration declined: Add site will not duplicate a legacy site" contains "$OUT" "already served by another nginx site file: sites-enabled/a.example.com"
check "migration declined: Add site wrote nothing" dir_empty_or_missing "$EZVPS_NGINX_DIR/conf.d"

new_mig mig_t1
FAKE_NGX_TEST_FAIL=1
run_ezvps "$NGX_BOX_INST" "${N}4\ny\n\n0\n\n0\n"
check "migration, failing test after the copy: reported" contains "$OUT" "nothing was removed and nginx was NOT reloaded"
check "migration, failing test after the copy: legacy files untouched" cmp -s "$SCN/a-original" "$(AV a.example.com)"
check "migration, failing test after the copy: symlinks untouched" test "$(readlink "$(EN a.example.com)")" = "$(AV a.example.com)"
check "migration, failing test after the copy: copies removed from conf.d" dir_empty_or_missing "$EZVPS_NGINX_DIR/conf.d"
check "migration, failing test after the copy: not reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "migration, failing test after the copy: menu survives" equals "$RC" 0
new_mig mig_t2
FAKE_NGX_FAIL_NTH=2
run_ezvps "$NGX_BOX_INST" "${N}4\ny\n\n0\n\n0\n"
check "migration, failing final test: reported" contains "$OUT" "FAILED after removing the legacy files"
check "migration, failing final test: legacy files restored byte for byte" cmp -s "$SCN/b-original" "$(AV b.example.com)"
check "migration, failing final test: legacy symlinks restored" test "$(readlink "$(EN b.example.com)")" = "$(AV b.example.com)"
check "migration, failing final test: copies removed from conf.d" dir_empty_or_missing "$EZVPS_NGINX_DIR/conf.d"
check "migration, failing final test: not reloaded" equals "$(nlog_count '^systemctl reload')" 0

new_mig mig_inc
mk_nginx_conf 0
run_ezvps "$NGX_BOX_INST" "${N}4\ny\n\n0\n\n0\n"
check "migration with a missing include: nginx.conf fixed first (backup taken)" equals "$(bk_count 'nginx.conf.*')" 1
check "migration with a missing include: include is inside the http block" include_in_http "$EZVPS_NGINX_DIR/nginx.conf"
check "migration with a missing include: sites moved" test -f "$(CF a.example.com)" -a ! -e "$(AV a.example.com)"
check "migration with a missing include: include test, copy test, final test" equals "$(nlog_count '^nginx -t$')" 3
new_mig mig_inc_fail
mk_nginx_conf 0
FAKE_NGX_TEST_FAIL=1
run_ezvps "$NGX_BOX_INST" "${N}4\ny\n\n0\n\n0\n"
check "migration, include cannot be added: nothing moved" contains "$OUT" "Nothing was moved"
check "migration, include cannot be added: legacy files untouched" cmp -s "$SCN/a-original" "$(AV a.example.com)"
check "migration, include cannot be added: nothing in conf.d" dir_empty_or_missing "$EZVPS_NGINX_DIR/conf.d"

new_mig mig_exists
mk_foreign_site a.example.com a.example.com
run_ezvps "$NGX_BOX_INST" "${N}4\ny\n\n0\n\n0\n"
check "migration: an existing conf.d file is never overwritten" contains "$OUT" "a.example.com (conf.d/a.example.com.conf already exists)"
check "migration: the other site is still offered and moved" test -f "$(CF b.example.com)" -a ! -e "$(AV b.example.com)"
check "migration: the site with the conflict stays in the legacy layout" test -f "$(AV a.example.com)"

new_mig mig_add
run_ezvps "$NGX_BOX_INST" "${N}5\ny\nnew.example.com\n127.0.0.1:3005\n\n0\n\n0\n"
check "migration then add: legacy sites moved" test -f "$(CF a.example.com)" -a ! -e "$(AV a.example.com)"
check "migration then add: new site added in conf.d" file_has "$(CF new.example.com)" "# ezvps:upstream=127.0.0.1:3005"
check "migration then add: one reload per change" equals "$(nlog_count '^systemctl reload nginx$')" 2
new_mig mig_rm
run_ezvps "$NGX_BOX_INST" "${N}6\ny\na.example.com\ny\n\n0\n\n0\n"
check "migration then remove: the moved site can be removed" test ! -e "$(CF a.example.com)"
check "migration then remove: ...with a backup" equals "$(ngx_backups a.example.com)" 1
check "migration then remove: the other moved site stays" test -f "$(CF b.example.com)"

echo "== Nginx site template and connection map (fake nginx, no network)"

# new_ngx's default nginx.conf already carries the map; these scenarios use one without it.
cnt() { grep -cF -- "$2" "$1"; }
tree_sum() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 cksum | cksum); }
map_line() { grep -n 'map \$http_upgrade \$connection_upgrade' "$1" | head -n1 | cut -d: -f1; }
inc_line() { grep -nE "$INC_RE" "$1" | head -n1 | cut -d: -f1; }
map_before_include() { local m i; m="$(map_line "$1")"; i="$(inc_line "$1")"; [[ -n "$m" && -n "$i" ]] && ((m < i)); }
nginx_conf_backups() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -type f -name "nginx.conf-map.*" 2>/dev/null | wc -l; }
first_t_state() { grep -m1 '^nginx-t-state' "$FAKE_LOG"; }

echo "-- the site template"
new_ngx tpl
ngx_up
mk_nginx_conf 1 0
cp "$EZVPS_NGINX_DIR/nginx.conf" "$SCN/nginx-conf-original"
run_ezvps "$NGX_BOX_INST" "${N}5\ntpl.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
F="$(CF tpl.example.com)"
check "template: one file per domain in conf.d" test -f "$F"
check "template: markers kept (managed, domain, upstream)" file_has "$F" "# ezvps:upstream=127.0.0.1:3000"
check "template: listens on 80" file_has "$F" "    listen 80;"
check "template: server_name" file_has "$F" "    server_name tpl.example.com;"
check "template: client_max_body_size 64M" file_has "$F" "    client_max_body_size 64M;"
check "template: location / with proxy_pass to the upstream" file_has "$F" "        proxy_pass http://127.0.0.1:3000;"
check "template: location / block" file_has "$F" "    location / {"
check "template: proxy_http_version 1.1" file_has "$F" "        proxy_http_version 1.1;"
{
    check "template: Host" file_has "$F" '        proxy_set_header Host $host;'
    check "template: X-Real-IP" file_has "$F" '        proxy_set_header X-Real-IP $remote_addr;'
    check "template: X-Forwarded-For" file_has "$F" '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;'
    check "template: X-Forwarded-Proto" file_has "$F" '        proxy_set_header X-Forwarded-Proto $scheme;'
    check "template: X-Forwarded-Port" file_has "$F" '        proxy_set_header X-Forwarded-Port $server_port;'
    check "template: Upgrade" file_has "$F" '        proxy_set_header Upgrade $http_upgrade;'
    check "template: Connection comes from the map variable" file_has "$F" '        proxy_set_header Connection $connection_upgrade;'
}
check "template: Connection is NOT hardcoded to upgrade" file_lacks "$F" 'Connection "upgrade"'
check "template: proxy_connect_timeout 60s" file_has "$F" "        proxy_connect_timeout 60s;"
check "template: proxy_read_timeout 120s" file_has "$F" "        proxy_read_timeout 120s;"
check "template: proxy_send_timeout 120s" file_has "$F" "        proxy_send_timeout 120s;"
check "template: plain HTTP form has no TLS and no 443" equals "$(grep -cE 'ssl|443|http2|return 301' "$F")" 0

echo "-- the connection map in nginx.conf"
check "map: added to nginx.conf" contains "$(<"$EZVPS_NGINX_DIR/nginx.conf")" 'map $http_upgrade $connection_upgrade {'
check "map: default upgrade" contains "$(<"$EZVPS_NGINX_DIR/nginx.conf")" "        default upgrade;"
check "map: empty string maps to close" contains "$(<"$EZVPS_NGINX_DIR/nginx.conf")" "        ''      close;"
check "map: exactly once" equals "$(cnt "$EZVPS_NGINX_DIR/nginx.conf" 'map $http_upgrade $connection_upgrade')" 1
check "map: inside the http block, before the conf.d include" map_before_include "$EZVPS_NGINX_DIR/nginx.conf"
check "map: nginx.conf backed up first, byte for byte" cmp -s "$SCN/nginx-conf-original" "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -type f -name 'nginx.conf-map.*' | head -n1)"
check "map: exactly one backup" equals "$(nginx_conf_backups)" 1
check "map: the rest of nginx.conf is unchanged" equals "$(grep -vcE 'upgrade|close;|added by ezvps|^    \}$' "$EZVPS_NGINX_DIR/nginx.conf")" "$(grep -vcE 'upgrade|close;|added by ezvps|^    \}$' "$SCN/nginx-conf-original")"
check "map: config test ran after adding it, before the site existed" contains "$(first_t_state)" "confd=0"
check "map: second config test ran for the site" equals "$(nlog_count '^nginx -t$')" 2
check "map: reload only after both tests" runs_before '^nginx-t-state enabled=0 confd=1' '^systemctl reload nginx$'
check "map: reloaded once" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "map: says it added the map" contains "$OUT" "Added the connection map to"
run_ezvps "$NGX_BOX_INST" "${N}5\ntpl2.example.com\n127.0.0.1:3001\n\n0\n\n0\n"
check "map: a second site does not duplicate the map" equals "$(cnt "$EZVPS_NGINX_DIR/nginx.conf" 'map $http_upgrade $connection_upgrade')" 1
check "map: a second site makes no further nginx.conf backup" equals "$(nginx_conf_backups)" 1
check "map: a second site only needs its own config test" equals "$(nlog_count '^nginx -t$')" 3

new_ngx map_other
ngx_up
mk_nginx_conf 1 0
printf '%s\n' 'map $http_upgrade $connection_upgrade {' "    default upgrade;" "    ''      close;" "}" >"$(CF websocket-map)"
cp "$EZVPS_NGINX_DIR/nginx.conf" "$SCN/nginx-conf-original"
run_ezvps "$NGX_BOX_INST" "${N}5\nm.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "map defined in another conf.d file: not added to nginx.conf" cmp -s "$SCN/nginx-conf-original" "$EZVPS_NGINX_DIR/nginx.conf"
check "map defined in another conf.d file: no nginx.conf backup" equals "$(nginx_conf_backups)" 0
check "map defined in another conf.d file: site still added" test -f "$(CF m.example.com)"
new_ngx map_legacy
ngx_up
mk_nginx_conf 1 0
printf '%s\n' 'map $http_upgrade $connection_upgrade { default upgrade; "" close; }' >"$(AV wsmap)"
ln -s "$(AV wsmap)" "$(EN wsmap)"
run_ezvps "$NGX_BOX_INST" "${N}5\nm.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "map defined in a (legacy) sites-enabled file: not duplicated" equals "$(nginx_conf_backups)" 0
new_ngx map_comment
ngx_up
mk_nginx_conf 1 0
sed -i 's|^    sendfile on;|    #map $http_upgrade $connection_upgrade { default upgrade; }\n    sendfile on;|' "$EZVPS_NGINX_DIR/nginx.conf"
run_ezvps "$NGX_BOX_INST" "${N}5\nm.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "a commented-out map is not mistaken for a real one" equals "$(grep -cE '^[[:space:]]+map ' "$EZVPS_NGINX_DIR/nginx.conf")" 1
new_ngx map_noinc
ngx_up
mk_nginx_conf 0 0
run_ezvps "$NGX_BOX_INST" "${N}5\nm.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "missing include and map: both added, once each" equals "$(cnt "$EZVPS_NGINX_DIR/nginx.conf" 'map $http_upgrade $connection_upgrade')" 1
check "missing include and map: include still added" has_include "$EZVPS_NGINX_DIR/nginx.conf"
check "missing include and map: three config tests (include, map, site)" equals "$(nlog_count '^nginx -t$')" 3
check "missing include and map: two different nginx.conf backups" equals "$(bk_count 'nginx.conf*')" 2
new_ngx map_fail
ngx_up
mk_nginx_conf 1 0
cp "$EZVPS_NGINX_DIR/nginx.conf" "$SCN/nginx-conf-original"
FAKE_NGX_FAIL_NTH=1
run_ezvps "$NGX_BOX_INST" "${N}5\nm.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "failing config test after adding the map: reported" contains "$OUT" "config test FAILED after adding the connection map"
check "failing config test after adding the map: nginx.conf restored byte for byte" cmp -s "$SCN/nginx-conf-original" "$EZVPS_NGINX_DIR/nginx.conf"
check "failing config test after adding the map: no site written" test ! -e "$(CF m.example.com)"
check "failing config test after adding the map: nginx NOT reloaded" no_mutation
check "failing config test after adding the map: menu survives" equals "$RC" 0
new_ngx map_nohttp
ngx_up
printf '%s\n' "events {" "}" >"$EZVPS_NGINX_DIR/nginx.conf"
run_ezvps "$NGX_BOX_INST" "${N}5\nh.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "map without an http block: explained, nothing guessed" contains "$OUT" "Found no http block"

echo "-- List sites shows the proxy_pass upstream of every file"
new_ngx lsp
ngx_up
mk_ezvps_site mine.example.com 127.0.0.1:3000
mk_foreign_proxy() { # mk_foreign_proxy <file> <server_name> <proxy_pass target>
    printf '%s\n' "server {" "    listen 80;" "    server_name $2;" "    location / {" "        proxy_pass $3;" "    }" "}" >"$(CF "$1")"
}
mk_foreign_proxy hand 'hand.example.com' 'http://127.0.0.1:8080'
mk_foreign_proxy api 'api.example.com' 'http://backend.internal:9000/api/;  # trailing comment'
mk_foreign_proxy secure 'secure.example.com' 'https://192.0.2.9:8443'
printf '%s\n' "server {" "    server_name multi.example.com;" "    location /a { proxy_pass http://127.0.0.1:1111; }" "    location /b { proxy_pass http://127.0.0.1:2222; }" "    location /c { proxy_pass http://127.0.0.1:1111; }" "}" >"$(CF multi)"
printf '%s\n' "server {" "    server_name oneline.example.com;" "    location / { proxy_pass http://127.0.0.1:7000; }" "}" >"$(CF oneline)"
printf '%s\n' "server {" "    server_name static.example.com;" "    return 200 'hello';" "}" >"$(CF static)"
printf '%s\n' "server {" "    server_name commented.example.com;" "    # proxy_pass http://127.0.0.1:9999;" "    return 200 'x';" "}" >"$(CF commented)"
printf '%s\n' "# Managed by ezvps (Nginx module). fixture" "# ezvps:domain=nolocation.example.com" "# ezvps:upstream=127.0.0.1:5555" "server {" "    server_name nolocation.example.com;" "    return 200 'x';" "}" >"$(CF nolocation)"
printf '%s\n' "# Managed by ezvps (Nginx module). fixture" "# ezvps:domain=edited.example.com" "# ezvps:upstream=127.0.0.1:5555" "server {" "    server_name edited.example.com;" "    location / { proxy_pass http://127.0.0.1:6666; }" "}" >"$(CF edited)"
SUM_TREE="$(tree_sum "$EZVPS_NGINX_DIR")"
run_ezvps "$NGX_BOX_INST" "${N}4\n\n0\n\n0\n"
check "list: ezvps site shows its upstream" has_row "$OUT" 'mine\.example\.com\.conf +mine\.example\.com +127\.0\.0\.1:3000 +ezvps$'
check "list: a hand-written site shows its proxy_pass" has_row "$OUT" 'hand\.conf +hand\.example\.com +127\.0\.0\.1:8080 +not ezvps$'
check "list: path and trailing comment: upstream without http://" has_row "$OUT" 'api\.conf +api\.example\.com +backend\.internal:9000/api/ +not ezvps$'
check "list: an https upstream keeps its scheme" has_row "$OUT" 'secure\.conf +secure\.example\.com +https://192\.0\.2\.9:8443 +not ezvps$'
check "list: several upstreams: the first plus a count of the other distinct ones" has_row "$OUT" 'multi\.conf +multi\.example\.com +127\.0\.0\.1:1111 \(\+1 more\) +not ezvps$'
check "list: proxy_pass on a one-line location is found" has_row "$OUT" 'oneline\.conf +oneline\.example\.com +127\.0\.0\.1:7000 +not ezvps$'
check "list: no proxy_pass: dash" has_row "$OUT" 'static\.conf +static\.example\.com +- +not ezvps$'
check "list: a commented-out proxy_pass is ignored" has_row "$OUT" 'commented\.conf +commented\.example\.com +- +not ezvps$'
check "list: an ezvps file without proxy_pass falls back to its marker" has_row "$OUT" 'nolocation\.conf +nolocation\.example\.com +127\.0\.0\.1:5555 +ezvps$'
check "list: the real proxy_pass wins over a stale marker" has_row "$OUT" 'edited\.conf +edited\.example\.com +127\.0\.0\.1:6666 +ezvps$'
check "list: CREATED BY is only ezvps or not ezvps" equals "$(printf '%s\n' "$OUT" | grep -E '\.conf ' | grep -cvE ' (ezvps|not ezvps)$')" 0
check "list: read-only (no file in nginx dir changed)" equals "$(tree_sum "$EZVPS_NGINX_DIR")" "$SUM_TREE"
check "list: read-only (no backup, no reload, no config test)" equals "$(bk_count '*')$(nlog_count '^systemctl')$(nlog_count '^nginx -t$')" "000"
check "list: exit 0" equals "$RC" 0
new_ngx lsp_new
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}5\nnew.example.com\n127.0.0.1:3000\n\n4\n\n0\n\n0\n"
check "list: a site made with the new template shows its upstream" has_row "$OUT" 'new\.example\.com\.conf +new\.example\.com +127\.0\.0\.1:3000 +ezvps$'

echo "== Certificates module (fake acme.sh/openssl/crontab/nginx, no network, no real certificates)"

ACME_TAG="$(grep -oE '^ACME_PINNED_TAG="[^"]+"' "$EZVPS" | cut -d'"' -f2)"
ACME_SHA="$(grep -oE '^ACME_SCRIPT_SHA256="[0-9a-f]{64}"' "$EZVPS" | cut -d'"' -f2)"
matches() { [[ "$1" =~ $2 ]]; }
check "pinned acme.sh tag is declared (X.Y.Z)" matches "$ACME_TAG" '^[0-9]+\.[0-9]+\.[0-9]+$'
check "pinned acme.sh sha256 is declared" test "${#ACME_SHA}" -eq 64
ACME_URL="https://raw.githubusercontent.com/acmesh-official/acme.sh/${ACME_TAG}/acme.sh"

# fake acme.sh: also the "downloaded" script. `--install` copies itself to --home. A "certificate" is a
# text file with a notAfter= line, so the fake openssl can read it; the "private key" is a marker that
# must never appear in ezvps' output. Like the real acme.sh, --install-cert writes with the default umask.
mkstub "$WORK/fake-acme.sh" <<'EOF'
home="" cmd="" dom="" fullchain="" keyfile="" reload="" server="" nginxmode=0 nocron=0
args=("$@")
while (($# > 0)); do
    case "$1" in
        --install) cmd=install ;;
        --issue) cmd=issue ;;
        --install-cert) cmd=install-cert ;;
        --renew-all) cmd=renew-all ;;
        --remove) cmd=remove ;;
        --list) cmd=list ;;
        --version) cmd=version ;;
        --home) home="$2"; shift ;;
        -d) dom="$2"; shift ;;
        --nginx) nginxmode=1 ;;
        --server) server="$2"; shift ;;
        --fullchain-file) fullchain="$2"; shift ;;
        --key-file) keyfile="$2"; shift ;;
        --reloadcmd) reload="$2"; shift ;;
        --nocron) nocron=1 ;;
    esac
    shift
done
echo "acme.sh ${args[*]}" >>"$FAKE_LOG"
[[ -n "$home" ]] || home="$HOME/.acme.sh"
serial() { local n=0; [[ -f "$home/serial" ]] && n="$(<"$home/serial")"; n=$((n + 1)); echo "$n" >"$home/serial"; echo "$n"; }
write_cert() { # write_cert <dir> <domain> <label>
    printf 'FAKE-CERTIFICATE %s serial=%s\nnotAfter=%s\n' "$2" "$3" "${FAKE_ACME_NOTAFTER:-Jan  1 00:00:00 2099 GMT}" >"$1/fullchain.cer"
    printf 'FAKE-KEY-DO-NOT-PRINT %s serial=%s\n' "$2" "$3" >"$1/$2.key"
}
case "$cmd" in
    install)
        [[ "${FAKE_ACME_INSTALL_FAIL:-0}" == 1 ]] && { echo "[fake] cannot install" >&2; exit 1; }
        mkdir -p "$home"
        cp "$0" "$home/acme.sh"
        chmod +x "$home/acme.sh"
        echo "[fake] Installed to $home/acme.sh"
        ((nocron == 0)) && echo "13 5 * * * \"$home\"/acme.sh --cron --home \"$home\" > /dev/null" >>"$FAKE_CRONTAB"
        exit 0 ;;
    version)
        [[ "${FAKE_ACME_VERSION_FAIL:-0}" == 1 ]] && { echo "[fake] broken" >&2; exit 1; }
        echo "https://github.com/acmesh-official/acme.sh"
        echo "v${FAKE_ACME_VERSION:-3.1.6}"
        exit 0 ;;
    issue)
        ((nginxmode == 1)) || { echo "[fake] only --nginx mode is supported" >&2; exit 1; }
        [[ "$server" == letsencrypt ]] || { echo "[fake] unexpected CA '$server'" >&2; exit 1; }
        [[ "${FAKE_ACME_ISSUE_FAIL:-0}" == 1 ]] && { echo "[fake] Verify error: DNS problem for $dom"; exit 1; }
        if [[ -f "$home/$dom/fullchain.cer" && "${FAKE_ACME_FORCE:-0}" != 1 ]]; then
            echo "[fake] Domain $dom is not due for renewal, skipping. Add --force to force renewal."
            exit 2
        fi
        mkdir -p "$home/$dom"
        write_cert "$home/$dom" "$dom" "$(serial)"
        if [[ "${FAKE_ACME_LEAK_KEY:-0}" == 1 ]]; then
            printf '%s%s\n' '-----BEGIN ' 'PRIVATE KEY-----'
            echo "FAKE-KEY-DO-NOT-PRINT-LEAKED"
            printf '%s%s\n' '-----END ' 'PRIVATE KEY-----'
        fi
        echo "[fake] Cert success for $dom."
        exit 0 ;;
    install-cert)
        [[ "${FAKE_ACME_INSTALLCERT_FAIL:-0}" == 1 ]] && { echo "[fake] install-cert failed" >&2; exit 1; }
        [[ -f "$home/$dom/fullchain.cer" ]] || { echo "[fake] $dom is not an issued domain" >&2; exit 1; }
        printf '%s\n' "$(<"$home/$dom/fullchain.cer")" >"$fullchain"
        printf '%s\n' "$(<"$home/$dom/$dom.key")" >"$keyfile"
        printf '%s|%s|%s\n' "$dom" "$fullchain" "$keyfile" >>"$home/installed.db"
        echo "[fake] Installing cert to $fullchain (reload: ${reload:+set})"
        exit 0 ;;
    list)
        printf 'Main_Domain\tKeyLength\tSAN_Domains\tProfile\tCA\tCreated\tRenew\n'
        exit 0 ;;
    renew-all)
        [[ "${FAKE_ACME_RENEW_FAIL:-0}" == 1 ]] && { echo "[fake] renew error" >&2; exit 1; }
        for d in ${FAKE_ACME_RENEW:-}; do
            [[ -f "$home/$d/fullchain.cer" ]] || continue
            write_cert "$home/$d" "$d" "renewed-$(serial)"
            if [[ -f "$home/installed.db" ]]; then
                while IFS='|' read -r idom ifull ikey; do
                    [[ "$idom" == "$d" && -d "${ifull%/*}" ]] || continue
                    printf '%s\n' "$(<"$home/$d/fullchain.cer")" >"$ifull"
                    printf '%s\n' "$(<"$home/$d/$d.key")" >"$ikey"
                done <"$home/installed.db"
            fi
            echo "[fake] Renewed: $d"
        done
        echo "[fake] renew-all finished"
        exit 0 ;;
    remove)
        [[ "${FAKE_ACME_REMOVE_FAIL:-0}" == 1 ]] && { echo "[fake] remove failed" >&2; exit 1; }
        [[ -d "$home/$dom" ]] || { echo "[fake] $dom is not an issued domain, skipping."; exit 1; }
        echo "$dom" >>"$home/removed.db"
        echo "[fake] $dom removed from the renewal list."
        exit 0 ;;
    *) echo "acme.sh UNEXPECTED ${args[*]}" >>"$FAKE_LOG"; exit 1 ;;
esac
EOF

# fake openssl: only `x509 -enddate -noout -in <file>`, reading the fake certificate's notAfter= line
mkstub "$STUBS/openssl" <<'EOF'
file="" prev=""
for a in "$@"; do
    [[ "$prev" == "-in" ]] && file="$a"
    prev="$a"
done
[[ "${1:-}" == x509 && -f "$file" ]] || exit 1
while IFS= read -r l; do
    [[ "$l" == notAfter=* ]] && { echo "$l"; exit 0; }
done <"$file"
exit 1
EOF
# fake crontab: only `-l`; the "crontab" is the file $FAKE_CRONTAB
mkstub "$STUBS/crontab" <<'EOF'
if [[ "${1:-}" == "-l" ]]; then
    [[ -s "$FAKE_CRONTAB" ]] || { echo "no crontab for root" >&2; exit 1; }
    while IFS= read -r l; do printf '%s\n' "$l"; done <"$FAKE_CRONTAB"
    exit 0
fi
echo "crontab UNEXPECTED $*" >>"$FAKE_LOG"
exit 1
EOF

# Sandboxes: coreutils plus the named stubs only
mkbox() { # mkbox <dir> <stub names...>
    local dir="$1" c
    shift
    mkdir -p "$dir"
    for c in "$CORE_BIN"/*; do ln -s "$c" "$dir/${c##*/}"; done
    for c in "$@"; do ln -s "$STUBS/$c" "$dir/$c"; done
}
CB="$WORK/cert-box"
CB_NOCRON="$WORK/cert-box-nocron"
CB_NOSSL="$WORK/cert-box-nossl"
CB_NOCURL="$WORK/cert-box-nocurl"
CB_NONGINX="$WORK/cert-box-nonginx"
mkbox "$CB" systemctl ss apt-get apt-cache dpkg-query curl gpg nginx sha256sum openssl crontab
mkbox "$CB_NOCRON" systemctl ss apt-get apt-cache dpkg-query curl gpg nginx sha256sum openssl
mkbox "$CB_NOSSL" systemctl ss apt-get apt-cache dpkg-query curl gpg nginx sha256sum crontab
mkbox "$CB_NOCURL" systemctl ss apt-get apt-cache dpkg-query gpg nginx sha256sum openssl crontab
mkbox "$CB_NONGINX" systemctl ss apt-get apt-cache dpkg-query curl gpg sha256sum openssl crontab

# new_cert <name>: nginx installed and running, acme.sh NOT installed, no certificates
new_cert() {
    new_ngx "cert-$1"
    ngx_up
    export EZVPS_ACME_HOME="$SCN/acme-home" EZVPS_CERT_DIR="$SCN/ssl-ezvps"
    export FAKE_CRONTAB="$SCN/crontab" FAKE_ACME_SCRIPT="$WORK/fake-acme.sh" FAKE_SHA="$ACME_SHA"
    export FAKE_LISTEN="$PORT_UP" SBOX_NOCURL_DIR="$CB_NOCURL"
    export FAKE_ACME_INSTALL_FAIL=0 FAKE_ACME_VERSION_FAIL=0 FAKE_ACME_ISSUE_FAIL=0 FAKE_ACME_INSTALLCERT_FAIL=0
    export FAKE_ACME_RENEW="" FAKE_ACME_RENEW_FAIL=0 FAKE_ACME_REMOVE_FAIL=0 FAKE_ACME_FORCE=0 FAKE_ACME_LEAK_KEY=0
    export FAKE_ACME_NOTAFTER="Jan  1 00:00:00 2099 GMT"
    : >"$FAKE_CRONTAB"
}
# acme_present: acme.sh is installed and has its cron entry, as after a normal install
acme_present() {
    mkdir -p "$EZVPS_ACME_HOME"
    cp "$FAKE_ACME_SCRIPT" "$EZVPS_ACME_HOME/acme.sh"
    chmod +x "$EZVPS_ACME_HOME/acme.sh"
    echo "13 5 * * * \"$EZVPS_ACME_HOME\"/acme.sh --cron --home \"$EZVPS_ACME_HOME\" > /dev/null" >"$FAKE_CRONTAB"
    return 0
}
C6="6\n"
# cert_run <choices after 'Certificates'> [path-dir]: Certificates, the choices, then back and exit
cert_run() { run_ezvps "${2:-$CB}" "${C6}$1\n\n0\n\n0\n"; }
CD() { printf '%s' "$EZVPS_CERT_DIR/$1"; }
KEYF() { printf '%s' "$EZVPS_CERT_DIR/$1/privkey.pem"; }
CRTF() { printf '%s' "$EZVPS_CERT_DIR/$1/fullchain.pem"; }
mode_of() { stat -c %a "$1"; }
acme_calls() { nlog_count "^acme.sh $1"; }
cert_backups() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name "cert-$1.*" 2>/dev/null | wc -l; }
cert_backup() { find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name "cert-$1.*" | head -n1; }
no_acme_run() { [[ "$(nlog_count '^acme.sh ')" -eq 0 ]]; }
no_cert_store() { [[ ! -e "$EZVPS_CERT_DIR" ]] || dir_empty_or_missing "$EZVPS_CERT_DIR"; }
not_installed_acme() { [[ ! -e "$EZVPS_ACME_HOME/acme.sh" ]]; }
never_leaks() { # never_leaks <output>: no key marker, no key file contents
    [[ "$1" != *"FAKE-KEY-DO-NOT-PRINT"* && "$1" != *"PRIVATE KEY-----"* ]]
}

echo "-- submenu"
new_cert menu
run_ezvps "$CB" "${C6}0\n\n0\n"
for line in " 1) Install acme.sh" " 2) Issue certificate" " 3) List certificates" " 4) Renew certificates" " 5) Remove certificate" " 0) Back"; do
    check "certificates submenu line '${line}' is exact (clean label)" has_line "$OUT" "$line"
done
check "Back returns to the main menu" at_least_menus "$OUT" 2
check "submenu exits 0" equals "$RC" 0
run_ezvps "$CB" "${C6}abc\n\n0\n\n0\n"
check "invalid submenu input is reported" contains "$OUT" "Invalid choice: abc"
check "invalid submenu input keeps the menu alive" equals "$RC" 0
run_ezvps "$CB" "$C6"
check "EOF inside the submenu exits 0" equals "$RC" 0
run_ezvps "$CB" "" certs
check "'ezvps certs' opens the submenu" contains "$OUT" " 5) Remove certificate"
check "Certificates is no longer reported as not implemented" not_contains "$OUT" "Certificates is not implemented yet"

echo "-- install acme.sh"
new_cert inst
cert_run "1\ny"
check "plan: names the official project" contains "$OUT" "https://github.com/acmesh-official/acme.sh"
check "plan: shows the pinned tag" contains "$OUT" "version:  ${ACME_TAG} (pinned release tag)"
check "plan: shows the exact source URL" contains "$OUT" "from:     ${ACME_URL}"
check "plan: the URL is a tag, never a branch" not_contains "$OUT" "/master/acme.sh"
check "plan: shows the expected sha256" contains "$OUT" "$ACME_SHA"
check "plan: never piped into a shell" contains "$OUT" "never piped into a shell"
check "plan: only the script, no DNS API plugins" contains "$OUT" "no DNS API"
check "script downloaded exactly once from the pinned URL" has_line "$(log)" "curl ACME ${ACME_URL}"
check "download uses --proto =https --tlsv1.2" equals "$(nlog_count 'ACME-INSECURE')" 0
check "installed with its own --install, our home, no shell-profile change" has_line "$(log)" "acme.sh --install --home ${EZVPS_ACME_HOME} --no-profile"
check "cron is allowed when crontab exists (no --nocron)" equals "$(nlog_count '--nocron')" 0
check "acme.sh is installed at the home" test -x "$EZVPS_ACME_HOME/acme.sh"
check "the command is verified to work afterwards" contains "$OUT" "Verified: the acme.sh command works (v3.1.6, ${EZVPS_ACME_HOME}/acme.sh)"
check "the cron entry was added by acme.sh" contains "$(<"$FAKE_CRONTAB")" "acme.sh --cron"
check "an empty crontab needs no backup" equals "$(bk_count 'crontab-root.*')" 0
check "nothing else is touched (no nginx call, no reload, no certificate store)" no_mutation
check "no certificate store is created by the install" no_cert_store
check "install exits 0" equals "$RC" 0
cert_run "1\ny"
check "re-run: already installed, not reinstalled" contains "$OUT" "acme.sh is already installed (${EZVPS_ACME_HOME}/acme.sh). Not reinstalling."
check "re-run: no second download" equals "$(nlog_count '^curl ACME')" 1
check "re-run: no second install" equals "$(acme_calls '.*--install ')" 1
check "re-run: the command is verified again" contains "$OUT" "Verified: the acme.sh command works"
new_cert inst_broken
acme_present
FAKE_ACME_VERSION_FAIL=1
cert_run "1"
check "an existing acme.sh that does not work is reported" contains "$OUT" "--version' did not work"
check "...and still not reinstalled over" equals "$(nlog_count '^curl ACME')" 0
new_cert inst_other
mkdir -p "$SCN/path-bin"
cp "$FAKE_ACME_SCRIPT" "$SCN/path-bin/acme.sh"
chmod +x "$SCN/path-bin/acme.sh"
ln -s "$SCN/path-bin/acme.sh" "$CB/acme.sh"
cert_run "1"
rm -f "$CB/acme.sh"
check "an acme.sh found on PATH counts as installed" contains "$OUT" "acme.sh is already installed"
check "an acme.sh on PATH: nothing downloaded" equals "$(nlog_count '^curl ACME')" 0
new_cert inst_no
cert_run "1\nn"
check "declined: cancelled" contains "$OUT" "Cancelled. Nothing was changed."
check "declined: nothing downloaded" equals "$(nlog_count '^curl ACME')" 0
check "declined: acme.sh not installed" not_installed_acme
new_cert inst_sha
FAKE_SHA="0000000000000000000000000000000000000000000000000000000000000000"
cert_run "1\ny"
check "sha256 mismatch is refused" contains "$OUT" "SHA-256 mismatch for the downloaded acme.sh"
check "sha256 mismatch: the script never ran" equals "$(acme_calls '')" 0
check "sha256 mismatch: not installed" not_installed_acme
check "sha256 mismatch: menu survives" equals "$RC" 0
new_cert inst_dl
FAKE_DOWNLOAD_FAIL=1
cert_run "1\ny"
check "download failure is reported" contains "$OUT" "Download failed: ${ACME_URL}"
check "download failure: not installed, menu survives" equals "$(not_installed_acme && echo "$RC")" 0
new_cert inst_fail
FAKE_ACME_INSTALL_FAIL=1
cert_run "1\ny"
check "an acme.sh installer failure is reported" contains "$OUT" "The acme.sh installer failed"
check "installer failure: no 'ready' message" not_contains "$OUT" "acme.sh is ready"
check "installer failure: menu survives" equals "$RC" 0
new_cert inst_nocron
cert_run "1\ny" "$CB_NOCRON"
check "no crontab: installed with --nocron" has_line "$(log)" "acme.sh --install --home ${EZVPS_ACME_HOME} --no-profile --nocron"
check "no crontab: the plan warns there is no renewal job" contains "$OUT" "WITHOUT its daily renewal job"
new_cert inst_cronbak
printf '%s\n' "0 3 * * * /usr/local/bin/example-job" >"$FAKE_CRONTAB"
cert_run "1\ny"
check "an existing crontab is backed up first" file_has "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name 'crontab-root.*' | head -n1)" "0 3 * * * /usr/local/bin/example-job"
check "the crontab backup is mode 600" equals "$(mode_of "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -name 'crontab-root.*' | head -n1)")" 600
new_cert inst_nocurl
cert_run "1\nn" "$CB_NOCURL"
check "missing curl is detected" contains "$OUT" "curl is not installed; it is needed to download acme.sh"
check "declining the curl install changes nothing" contains "$OUT" "Cancelled. Nothing was changed."
check "no apt-get call without consent" no_apt
cert_run "1\ny\ny" "$CB_NOCURL"
check "curl is installed only after a yes" contains "$(log)" "apt-get install -y -q curl"
check "the install continues once curl is there" has_line "$(log)" "curl ACME ${ACME_URL}"
new_cert inst_os
OUT="$(printf '%b' "${C6}1\ny\n\n0\n\n0\n" | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/ubuntu2510" PATH="$CB" "$BASH_BIN" "$EZVPS" 2>&1)"
RC=$?
check "unsupported system is refused" contains "$OUT" "acme.sh install needs a supported system: ${OS_LIST_TEXT}; found 'ubuntu 25.10 questing'"
check "unsupported system: nothing downloaded or installed" equals "$(nlog_count '^curl ACME')$(acme_calls '')" "00"

echo "-- issue certificate: preconditions (nothing may change)"
new_cert iss_noacme
mk_foreign_site example.com example.com
cert_run "2"
check "acme.sh missing: told to install it first" contains "$OUT" "acme.sh is not installed. Choose 'Install acme.sh' first."
check "acme.sh missing: nothing stored" no_cert_store
new_cert iss_nonginx
acme_present
rm -f "$FAKE_DPKG"
cert_run "2" "$CB_NONGINX"
check "nginx missing: told so" contains "$OUT" "Nginx is not installed."
check "nginx missing: acme.sh never ran" no_acme_run
new_cert iss_down
acme_present
ngx_down
mk_foreign_site example.com example.com
cert_run "2\nexample.com\ny"
check "nginx not running: refused" contains "$OUT" "nginx is not running"
check "nginx not running: acme.sh never ran" no_acme_run
new_cert iss_port
acme_present
FAKE_LISTEN=""
mk_foreign_site example.com example.com
cert_run "2\nexample.com\ny"
check "port 80 not reachable: refused" contains "$OUT" "Nothing is listening on port ${PORT_UP}"
check "port 80 not reachable: acme.sh never ran" no_acme_run
new_cert iss_inp
acme_present
mk_foreign_site example.com example.com
for bad in "*.example.com" "a.example.com b.example.com" "a.example.com,b.example.com" "not a domain" "../etc" "localhost"; do
    cert_run "2\n${bad}\ny"
    check "input '${bad}' is rejected" equals "$([[ "$OUT" == *"Wildcard certificates need DNS validation"* || "$OUT" == *"Enter exactly one domain"* || "$OUT" == *"is not a valid domain name"* ]] && echo yes)" yes
done
check "rejected input: acme.sh never ran" no_acme_run
cert_run "2\n\ny"
check "empty input cancels" contains "$OUT" "Cancelled. Nothing was changed."
new_cert iss_noserver
acme_present
cert_run "2\nnowhere.example.com\ny"
check "a domain no nginx server block serves is refused" contains "$OUT" "No nginx server block serves nowhere.example.com"
check "...with the next step" contains "$OUT" "Nginx -> Add site"
check "...and acme.sh never ran, nothing stored" equals "$(no_acme_run && no_cert_store && echo ok)" ok
new_cert iss_no
acme_present
mk_foreign_site example.com example.com
cert_run "2\nexample.com\nn"
check "the DNS requirement is printed before asking" contains "$OUT" "The DNS record of example.com must point to THIS server before issuing"
check "port 80 reachability is mentioned" contains "$OUT" "port 80 must be"
check "no DNS provider credentials are requested" contains "$OUT" "No DNS provider credentials are asked for or stored"
check "declined: cancelled" contains "$OUT" "Cancelled. Nothing was changed."
check "declined: acme.sh never ran" no_acme_run
check "declined: nothing stored" no_cert_store
check "nothing mentions a token, API key or secret to enter" equals "$([[ "$OUT" == *[Tt]oken* || "$OUT" == *"API key"* || "$OUT" == *secret* ]] && echo yes)" ""

echo "-- issue certificate: certificate only (no ezvps site)"
new_cert iss_only
acme_present
mk_foreign_site example.com example.com
cp "$(CF example.com)" "$SCN/foreign-original"
cert_run "2\nexample.com\ny"
D="$(CD example.com)"
check "issue: asked acme.sh for one domain, HTTP-01 through nginx, Let's Encrypt" has_line "$(log)" "acme.sh --home ${EZVPS_ACME_HOME} --issue -d example.com --nginx --server letsencrypt"
check "issue: no DNS mode, no wildcard, no extra domain" equals "$(nlog_count '--dns|-d \*|-d [^ ]+ .*-d ')" 0
check "issue: nginx config tested after acme.sh edited it" contains "$(log)" "nginx -t"
check "issue: installed into the store with the documented file names" contains "$(log)" "acme.sh --home ${EZVPS_ACME_HOME} --install-cert -d example.com --fullchain-file ${D}/fullchain.pem --key-file ${D}/privkey.pem --reloadcmd nginx -t && systemctl reload nginx"
check "store: certificate chain exists" test -s "$(CRTF example.com)"
check "store: private key exists" test -s "$(KEYF example.com)"
check "store: private key is mode 600 (root only)" equals "$(mode_of "$(KEYF example.com)")" 600
check "store: certificate is mode 644" equals "$(mode_of "$(CRTF example.com)")" 644
check "store: the domain directory is mode 700" equals "$(mode_of "$D")" 700
check "store: the ezvps store directory is mode 700" equals "$(mode_of "$EZVPS_CERT_DIR")" 700
check "store: keeps the certificate acme.sh issued" file_has "$(CRTF example.com)" "FAKE-CERTIFICATE example.com serial=1"
check "output: the private key is never printed" never_leaks "$OUT"
check "output: says where the key is, without showing it" contains "$OUT" "private key (mode 600, readable only by root; never shown)"
check "output: shows the expiry" contains "$OUT" "expires: 2099-01-01"
check "output: mentions the renewal job" contains "$OUT" "renews it automatically"
check "no ezvps site: stored only, and says so" contains "$OUT" "There is no ezvps nginx site for example.com"
check "no ezvps site: no site was created" equals "$(find "$EZVPS_NGINX_DIR/conf.d" -type f | wc -l)" 1
check "no ezvps site: the hand-written file is untouched" cmp -s "$SCN/foreign-original" "$(CF example.com)"
check "no ezvps site: nothing was asked about HTTPS" not_contains "$OUT" "Enable HTTPS"
check "no ezvps site: nginx.conf untouched (no backup)" equals "$(bk_count 'nginx*')" 0
check "first issue of a domain makes no certificate backup" equals "$(cert_backups example.com)" 0
check "issue exits 0" equals "$RC" 0
echo "-- issue certificate: again (backup of the existing certificate)"
cp "$(CRTF example.com)" "$SCN/chain-1"
cp "$(KEYF example.com)" "$SCN/key-1"
FAKE_ACME_FORCE=1
cert_run "2\nexample.com\ny"
check "re-issue: told the existing certificate is backed up" contains "$OUT" "is already stored in ${D}; it is backed up before it is replaced"
check "re-issue: backup exists" equals "$(cert_backups example.com)" 1
check "re-issue: backup holds the OLD certificate byte for byte" cmp -s "$SCN/chain-1" "$(cert_backup example.com)/fullchain.pem"
check "re-issue: backup holds the OLD key byte for byte" cmp -s "$SCN/key-1" "$(cert_backup example.com)/privkey.pem"
check "re-issue: the backup key is still mode 600" equals "$(mode_of "$(cert_backup example.com)/privkey.pem")" 600
check "re-issue: the store has the NEW certificate" file_has "$(CRTF example.com)" "FAKE-CERTIFICATE example.com serial=2"
check "re-issue: the new key is mode 600" equals "$(mode_of "$(KEYF example.com)")" 600
check "re-issue: backups are in the mode-700 backup dir" equals "$(mode_of "$EZVPS_BACKUP_DIR")" 700
check "re-issue: key never printed" never_leaks "$OUT"
FAKE_ACME_FORCE=0
cert_run "2\nexample.com\ny"
check "not due: acme.sh skips, ezvps says so and still syncs the store" contains "$OUT" "the existing one for example.com is still valid"
check "not due: still exactly one certificate dir" equals "$(find "$EZVPS_CERT_DIR" -mindepth 1 -maxdepth 1 | wc -l)" 1
check "not due: the existing certificate was backed up again (before replacement)" equals "$(cert_backups example.com)" 2

echo "-- issue certificate: failures"
new_cert iss_fail
acme_present
mk_foreign_site example.com example.com
FAKE_ACME_ISSUE_FAIL=1
cert_run "2\nexample.com\ny"
check "acme.sh failure is reported" contains "$OUT" "acme.sh could not issue the certificate for example.com (exit 1)"
check "acme.sh failure: its message is shown" contains "$OUT" "Verify error: DNS problem"
check "acme.sh failure: hints about DNS and port 80" contains "$OUT" "the DNS record points here"
check "acme.sh failure: nothing stored" no_cert_store
check "acme.sh failure: menu survives" equals "$RC" 0
new_cert iss_leak
acme_present
mk_foreign_site example.com example.com
FAKE_ACME_LEAK_KEY=1
cert_run "2\nexample.com\ny"
check "a key block in acme.sh output is hidden" contains "$OUT" "(private key material hidden)"
check "a key block in acme.sh output: nothing leaks" never_leaks "$OUT"
new_cert iss_nginxbad
acme_present
mk_foreign_site example.com example.com
FAKE_NGX_TEST_FAIL=1
cert_run "2\nexample.com\ny"
check "a failing nginx config test after acme.sh is reported" contains "$OUT" "config test FAILS after acme.sh ran"
check "...nothing stored" no_cert_store
check "...nginx not reloaded by ezvps" no_mutation
new_cert iss_instfail
acme_present
mk_foreign_site example.com example.com
FAKE_ACME_INSTALLCERT_FAIL=1
cert_run "2\nexample.com\ny"
check "install-cert failure is reported" contains "$OUT" "could not install the certificate into $(CD example.com)"
check "install-cert failure: the new directory is removed again" no_cert_store
new_cert iss_instfail2
acme_present
mk_foreign_site example.com example.com
cert_run "2\nexample.com\ny"
cp "$(CRTF example.com)" "$SCN/chain-1"
FAKE_ACME_FORCE=1 FAKE_ACME_INSTALLCERT_FAIL=1
cert_run "2\nexample.com\ny"
check "install-cert failure with an existing certificate: it is restored byte for byte" cmp -s "$SCN/chain-1" "$(CRTF example.com)"
check "install-cert failure with an existing certificate: says it rolled back" contains "$OUT" "Rolled back: the certificate directory is as it was"
check "install-cert failure with an existing certificate: the restored key is mode 600" equals "$(mode_of "$(KEYF example.com)")" 600

echo "-- issue certificate: enable HTTPS for an ezvps site"
new_cert https
acme_present
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
F="$(CF example.com)"
cp "$F" "$SCN/site-http"
cert_run "2\nexample.com\ny\ny"
D="$(CD example.com)"
check "https: the offer names the site and what will change" contains "$OUT" "An ezvps nginx site exists for example.com"
check "https: the offer says it edits that file only, with backup and test" contains "$OUT" "backed up first, nginx -t must pass"
check "https: site backed up first, byte for byte" cmp -s "$SCN/site-http" "$(ngx_backup_file example.com)"
check "https: exactly one site backup" equals "$(ngx_backups example.com)" 1
check "https: marker says https is on" file_has "$F" "# ezvps:https=on"
check "https: the markers are kept" file_has "$F" "# ezvps:upstream=127.0.0.1:3000"
check "https: a 443 ssl server block" file_has "$F" "    listen 443 ssl;"
check "https: http2 on" file_has "$F" "    http2 on;"
check "https: ssl_certificate points into the ezvps store" file_has "$F" "    ssl_certificate ${D}/fullchain.pem;"
check "https: ssl_certificate_key points into the ezvps store" file_has "$F" "    ssl_certificate_key ${D}/privkey.pem;"
check "https: 443, not 4443" equals "$(cnt "$F" 4443)" 0
check "https: no stream block" equals "$(grep -cE '^[[:space:]]*stream[[:space:]]*\{' "$F")" 0
check "https: the old (deprecated) 'listen 443 ssl http2' form is not used" equals "$(cnt "$F" 'ssl http2')" 0
check "https: the HTTP block is a 301 redirect to https://\$host\$request_uri" file_has "$F" '        return 301 https://$host$request_uri;'
check "https: the redirect is inside location / (acme.sh renewal can still answer)" equals "$(grep -B1 'return 301' "$F" | head -n1 | tr -d ' ')" "location/{"
check "https: still listens on 80 for the redirect" file_has "$F" "    listen 80;"
check "https: two server blocks, both for the domain" equals "$(cnt "$F" '    server_name example.com;')" 2
check "https: the proxy happens only in the 443 block" equals "$(cnt "$F" '        proxy_pass http://127.0.0.1:3000;')" 1
check "https: proxy_pass sits after the 443 listen" equals "$(awk '/listen 443 ssl/ {a=NR} /proxy_pass/ {b=NR} END {print (b>a)}' "$F")" 1
check "https: same body size as the HTTP template" file_has "$F" "    client_max_body_size 64M;"
check "https: same proxy block as part 1 (headers, timeouts)" equals "$(for l in 'proxy_http_version 1.1;' 'proxy_set_header Host $host;' 'proxy_set_header X-Real-IP $remote_addr;' 'proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' 'proxy_set_header X-Forwarded-Proto $scheme;' 'proxy_set_header X-Forwarded-Port $server_port;' 'proxy_set_header Upgrade $http_upgrade;' 'proxy_set_header Connection $connection_upgrade;' 'proxy_connect_timeout 60s;' 'proxy_read_timeout 120s;' 'proxy_send_timeout 120s;'; do grep -cF -- "        $l" "$F"; done | tr -d '\n')" "11111111111"
check "https: config test ran before the reload" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "https: nginx reloaded after the site test" contains "$OUT" "HTTPS enabled for example.com. Config test passes."
check "https: tells about port 443 and the firewall" contains "$OUT" "port 443 is open (the firewall is not changed here): https://example.com/"
check "https: private key never printed" never_leaks "$OUT"
check "https: only that one site file exists" equals "$(find "$EZVPS_NGINX_DIR/conf.d" -type f | wc -l)" 1
check "https: the listing now knows the site uses the certificate" contains "$(cert_run "3" >/dev/null; printf '%s' "$OUT")" "yes (example.com.conf)"
RELOADS="$(nlog_count '^systemctl reload nginx$')"
cp "$F" "$SCN/site-https"
cert_run "2\nexample.com\ny"
check "again with HTTPS already on: recognised" contains "$OUT" "HTTPS is already enabled for example.com"
check "again with HTTPS already on: site file untouched" cmp -s "$SCN/site-https" "$F"
check "again with HTTPS already on: no extra site backup" equals "$(ngx_backups example.com)" 1
check "again with HTTPS already on: nginx reloaded (new certificate) after a config test" equals "$(nlog_count '^systemctl reload nginx$')" "$((RELOADS + 1))"
# Add site / Remove site on an HTTPS site must say what they do to the HTTPS setup
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:4000\nn\n\n0\n\n0\n"
check "Add site over an HTTPS site: warns that the 443 block would be dropped" contains "$OUT" "HTTPS is enabled on it. Overwriting writes a plain HTTP site"
check "Add site over an HTTPS site, declined: the HTTPS site is untouched" cmp -s "$SCN/site-https" "$F"
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "Add site with the same upstream on an HTTPS site: nothing to do, HTTPS kept" equals "$(contains "$OUT" "Nothing to do" && cmp -s "$SCN/site-https" "$F" && echo yes)" yes
run_ezvps "$NGX_BOX_INST" "${N}6\nexample.com\nn\n\n0\n\n0\n"
check "Remove site on an HTTPS site: says the certificate stays and how to remove it" contains "$OUT" "its certificate stays in $(CD example.com)"
check "Remove site declined: the HTTPS site is untouched" cmp -s "$SCN/site-https" "$F"

new_cert https_no
acme_present
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
cp "$(CF example.com)" "$SCN/site-http"
RELOADS="$(nlog_count '^systemctl reload nginx$')"
cert_run "2\nexample.com\ny\nn"
check "https declined: certificate is stored" test -s "$(CRTF example.com)"
check "https declined: site file untouched" cmp -s "$SCN/site-http" "$(CF example.com)"
check "https declined: no site backup" equals "$(ngx_backups example.com)" 0
check "https declined: says how to be asked again" contains "$OUT" "Run Issue certificate again"
check "https declined: nginx not reloaded for the site" equals "$(nlog_count '^systemctl reload nginx$')" "$RELOADS"

new_cert https_foreign
acme_present
mk_foreign_site example.com example.com
cp "$(CF example.com)" "$SCN/foreign-original"
cert_run "2\nexample.com\ny"
check "a site not made by ezvps is never edited" cmp -s "$SCN/foreign-original" "$(CF example.com)"
check "...and no HTTPS offer is made for it" not_contains "$OUT" "Enable HTTPS"
new_cert https_legacy_named
acme_present
mk_foreign_site other example.com
cert_run "2\nexample.com\ny"
check "a domain served by a differently named file: certificate stored, no ezvps site assumed" contains "$OUT" "There is no ezvps nginx site for example.com"

new_cert https_fail
acme_present
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
cp "$(CF example.com)" "$SCN/site-http"
SUM_CONF="$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")"
RELOADS="$(nlog_count '^systemctl reload nginx$')"
FAKE_NGX_FAIL_NTH=$(($(<"$FAKE_LOG.tcount") + 2))
cert_run "2\nexample.com\ny\ny"
check "https with a failing config test: reported" contains "$OUT" "config test FAILED after rewriting"
check "https with a failing config test: the site is restored byte for byte" cmp -s "$SCN/site-http" "$(CF example.com)"
check "https with a failing config test: says it rolled back" contains "$OUT" "Rolled back"
check "https with a failing config test: nginx is NOT reloaded" equals "$(nlog_count '^systemctl reload nginx$')" "$RELOADS"
check "https with a failing config test: no restart either" equals "$(nlog_count '^systemctl restart')" 0
check "https with a failing config test: backup of the site exists" equals "$(ngx_backups example.com)" 1
check "https with a failing config test: nginx.conf untouched" equals "$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")" "$SUM_CONF"
check "https with a failing config test: the certificate stays stored" test -s "$(CRTF example.com)"
check "https with a failing config test: tells the user HTTPS was not enabled" contains "$OUT" "HTTPS was not enabled; the site is as it was"
check "https with a failing config test: menu survives" equals "$RC" 0

new_cert https_map
acme_present
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
mk_nginx_conf 1 0
cp "$EZVPS_NGINX_DIR/nginx.conf" "$SCN/nginx-conf-original"
cert_run "2\nexample.com\ny\ny"
check "https: the connection map is ensured too (added when missing)" equals "$(cnt "$EZVPS_NGINX_DIR/nginx.conf" 'map $http_upgrade $connection_upgrade')" 1
check "https: ...with a backup of nginx.conf first" cmp -s "$SCN/nginx-conf-original" "$(find "$EZVPS_BACKUP_DIR" -maxdepth 1 -type f -name 'nginx.conf-map.*' | head -n1)"

echo "-- list certificates"
new_cert list0
acme_present
cert_run "3"
check "list: none yet" contains "$OUT" "(none) Use Issue certificate to get one."
check "list: exit 0" equals "$RC" 0
new_cert list1
acme_present
run_ezvps "$NGX_BOX_INST" "${N}5\nsite.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
mk_foreign_site bare.example.com bare.example.com
mk_foreign_site hand.example.com hand.example.com
FAKE_ACME_NOTAFTER="Mar 15 12:00:00 2099 GMT"
cert_run "2\nsite.example.com\ny\ny"
FAKE_ACME_NOTAFTER="Jun  2 08:30:00 2099 GMT"
cert_run "2\nbare.example.com\ny"
FAKE_ACME_NOTAFTER="Jan  1 00:00:00 2001 GMT"
cert_run "2\nhand.example.com\ny"
# hand-written HTTPS site using the ezvps store certificate
printf '%s\n' "server {" "    listen 443 ssl;" "    server_name hand.example.com;" "    ssl_certificate $(CRTF hand.example.com);" "    ssl_certificate_key $(KEYF hand.example.com);" "    return 200 'x';" "}" >"$(CF hand.example.com)"
SUM_TREE="$(tree_sum "$EZVPS_CERT_DIR")$(tree_sum "$EZVPS_NGINX_DIR")"
CALLS_BEFORE="$(wc -l <"$FAKE_LOG")"
cert_run "3"
check "list: header" has_row "$OUT" 'DOMAIN +EXPIRES +NGINX SITE'
check "list: each domain with its expiry date and the site that uses it (enabled by ezvps)" has_row "$OUT" 'site\.example\.com +2099-03-15 \([0-9]+ days left\) +yes \(site\.example\.com\.conf\)$'
check "list: a certificate not installed for any site" has_row "$OUT" 'bare\.example\.com +2099-06-02 \([0-9]+ days left\) +no$'
check "list: an expired certificate is flagged" has_row "$OUT" 'hand\.example\.com +2001-01-01 \(EXPIRED\) +yes \(hand\.example\.com\.conf\)$'
check "list: sorted by domain" equals "$(printf '%s\n' "$OUT" | grep -oE '^  (bare|hand|site)\.example\.com' | tr -d ' ' | tr '\n' ' ')" "bare.example.com hand.example.com site.example.com "
check "list: never prints a key" never_leaks "$OUT"
check "list: read-only (store and nginx dir unchanged)" equals "$(tree_sum "$EZVPS_CERT_DIR")$(tree_sum "$EZVPS_NGINX_DIR")" "$SUM_TREE"
check "list: runs no acme.sh, no nginx test, no reload" equals "$(($(wc -l <"$FAKE_LOG") - CALLS_BEFORE))" 0
cert_run "3" "$CB_NOSSL"
check "list without openssl: expiry unknown, still listed" has_row "$OUT" 'bare\.example\.com +unknown \(openssl not installed\) +no$'
mkdir -p "$(CD broken.example.com)"
cert_run "3"
check "list: a directory without a certificate file is flagged" has_row "$OUT" 'broken\.example\.com +no certificate file +no$'
printf 'not a certificate\n' >"$(CRTF broken.example.com)"
cert_run "3"
check "list: an unreadable certificate is flagged" has_row "$OUT" 'broken\.example\.com +unreadable certificate +no$'

echo "-- renew certificates"
new_cert ren0
cert_run "4"
check "renew without acme.sh: told to install it" contains "$OUT" "acme.sh is not installed. Choose 'Install acme.sh' first."
new_cert ren1
acme_present
run_ezvps "$NGX_BOX_INST" "${N}5\nsite.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
cert_run "2\nsite.example.com\ny\ny"
mk_foreign_site other.example.com other.example.com
cert_run "2\nother.example.com\ny"
RELOADS="$(nlog_count '^systemctl reload nginx$')"
TESTS="$(nlog_count '^nginx -t$')"
cp "$(CRTF site.example.com)" "$SCN/site-chain-1"
cert_run "4"
check "renew: runs acme.sh --renew-all" has_line "$(log)" "acme.sh --home ${EZVPS_ACME_HOME} --renew-all"
check "renew: nothing due: says so" contains "$OUT" "No certificate was renewed (none is due yet). nginx was not reloaded."
check "renew: nothing due: nginx NOT reloaded" equals "$(nlog_count '^systemctl reload nginx$')" "$RELOADS"
check "renew: nothing due: no config test either" equals "$(nlog_count '^nginx -t$')" "$TESTS"
check "renew: nothing due: store unchanged" cmp -s "$SCN/site-chain-1" "$(CRTF site.example.com)"
FAKE_ACME_RENEW="site.example.com"
cert_run "4"
check "renew: acme.sh's own output is shown" contains "$OUT" "Renewed: site.example.com"
check "renew: a changed certificate is detected" contains "$OUT" "At least one certificate was renewed."
check "renew: the stored certificate is the new one" file_has "$(CRTF site.example.com)" "FAKE-CERTIFICATE site.example.com serial=renewed-3"
check "renew: config test ran, then nginx was reloaded once" equals "$(nlog_count '^nginx -t$')$(nlog_count '^systemctl reload nginx$')" "$((TESTS + 1))$((RELOADS + 1))"
check "renew: config test before the reload" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "renew: private key never printed" never_leaks "$OUT"
check "renew: exit 0" equals "$RC" 0
RELOADS="$(nlog_count '^systemctl reload nginx$')"
FAKE_ACME_RENEW="other.example.com" FAKE_NGX_TEST_FAIL=1
cert_run "4"
check "renew with a failing config test: reported" contains "$OUT" "The nginx config test FAILED; nginx was NOT reloaded."
check "renew with a failing config test: nginx not reloaded" equals "$(nlog_count '^systemctl reload nginx$')" "$RELOADS"
check "renew with a failing config test: no restart" equals "$(nlog_count '^systemctl restart')" 0
check "renew with a failing config test: menu survives" equals "$RC" 0
FAKE_NGX_TEST_FAIL=0
RELOADS="$(nlog_count '^systemctl reload nginx$')"
FAKE_ACME_RENEW="" FAKE_ACME_RENEW_FAIL=1
cert_run "4"
check "renew: an acme.sh failure is reported" contains "$OUT" "acme.sh reported errors (exit 1)"
check "renew: a failure that changed nothing does not reload" equals "$(nlog_count '^systemctl reload nginx$')" "$RELOADS"
new_cert ren_only_acme
acme_present
mkdir -p "$EZVPS_ACME_HOME/lonely.example.com"
printf 'FAKE-CERTIFICATE lonely serial=1\nnotAfter=Jan  1 00:00:00 2099 GMT\n' >"$EZVPS_ACME_HOME/lonely.example.com/fullchain.cer"
printf 'FAKE-KEY-DO-NOT-PRINT lonely\n' >"$EZVPS_ACME_HOME/lonely.example.com/lonely.example.com.key"
FAKE_ACME_RENEW="lonely.example.com"
cert_run "4"
check "renew: an acme.sh certificate outside the ezvps store is detected too" equals "$(nlog_count '^systemctl reload nginx$')" 1
new_cert ren_nonginx
acme_present
mkdir -p "$EZVPS_ACME_HOME/lonely.example.com"
printf 'FAKE-CERTIFICATE lonely serial=1\nnotAfter=Jan  1 00:00:00 2099 GMT\n' >"$EZVPS_ACME_HOME/lonely.example.com/fullchain.cer"
printf 'FAKE-KEY-DO-NOT-PRINT lonely\n' >"$EZVPS_ACME_HOME/lonely.example.com/lonely.example.com.key"
FAKE_ACME_RENEW="lonely.example.com"
rm -f "$FAKE_DPKG"
cert_run "4" "$CB_NONGINX"
check "renew without nginx: renewed, nothing to reload, no failure" contains "$OUT" "nginx is not installed here, so there is nothing to reload."

echo "-- remove certificate"
new_cert rm0
acme_present
cert_run "5\nexample.com"
check "remove: unknown domain changes nothing" contains "$OUT" "No certificate for example.com in ${EZVPS_CERT_DIR}."
check "remove: unknown domain: acme.sh never ran" no_acme_run
cert_run "5\n*.example.com"
check "remove: wildcard input is rejected" contains "$OUT" "Wildcard certificates need DNS validation"
cert_run "5\n../x"
check "remove: path traversal is rejected" contains "$OUT" "contains a path separator"

# rm_setup <name>: an ezvps site with HTTPS enabled from a real issue, plus a second one left alone
rm_setup() {
    new_cert "$1"
    acme_present
    run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
    run_ezvps "$NGX_BOX_INST" "${N}5\nkeep.example.com\n127.0.0.1:4000\n\n0\n\n0\n"
    cp "$(CF example.com)" "$SCN/site-http"
    cp "$(CF keep.example.com)" "$SCN/keep-site"
    cert_run "2\nexample.com\ny\ny"
    cp "$(CF example.com)" "$SCN/site-https"
    cp "$(CRTF example.com)" "$SCN/chain-orig"
    cp "$(KEYF example.com)" "$SCN/key-orig"
}
rm_setup rm1
RELOADS="$(nlog_count '^systemctl reload nginx$')"
cert_run "5\nexample.com\nn"
check "remove: shows what will happen" contains "$OUT" "rewrite $(CF example.com) back to its plain HTTP proxy to 127.0.0.1:3000"
check "remove declined: cancelled" contains "$OUT" "Cancelled. Nothing was changed."
check "remove declined: certificate still stored" test -s "$(CRTF example.com)"
check "remove declined: site still HTTPS" cmp -s "$SCN/site-https" "$(CF example.com)"
check "remove declined: no certificate backup" equals "$(cert_backups example.com)" 0
check "remove declined: acme.sh --remove not run" equals "$(acme_calls '--home .* --remove')" 0
BK_SITES="$(ngx_backups example.com)"
cert_run "5\nexample.com\ny"
check "remove: the certificate is backed up first" equals "$(cert_backups example.com)" 1
check "remove: the backup holds the certificate byte for byte" cmp -s "$SCN/chain-orig" "$(cert_backup example.com)/fullchain.pem"
check "remove: the backup holds the private key byte for byte" cmp -s "$SCN/key-orig" "$(cert_backup example.com)/privkey.pem"
check "remove: the backup key is mode 600" equals "$(mode_of "$(cert_backup example.com)/privkey.pem")" 600
check "remove: removed from the ezvps store" test ! -e "$(CD example.com)"
check "remove: the store directory itself stays" test -d "$EZVPS_CERT_DIR"
check "remove: the HTTPS site was backed up (with HTTPS in it) first" equals "$(ngx_backups example.com)" "$((BK_SITES + 1))"
check "remove: one of the site backups is the HTTPS file" equals "$(grep -lF 'ssl_certificate ' "$EZVPS_BACKUP_DIR"/nginx-site-example.com.* | wc -l)" 1
check "remove: the plain HTTP proxy block is restored" cmp -s "$SCN/site-http" "$(CF example.com)"
check "remove: no TLS left in the site" equals "$(grep -cE 'ssl|443|http2|return 301|https=on' "$(CF example.com)")" 0
check "remove: the other site is untouched" cmp -s "$SCN/keep-site" "$(CF keep.example.com)"
check "remove: config test ran before the reload" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "remove: tells that the site is plain HTTP again" contains "$OUT" "is a plain HTTP proxy to 127.0.0.1:3000 again. Config test passes."
check "remove: nginx reloaded once, after the test" equals "$(nlog_count '^systemctl reload nginx$')" "$((RELOADS + 1))"
check "remove: acme.sh told to stop renewing" has_line "$(log)" "acme.sh --home ${EZVPS_ACME_HOME} --remove -d example.com"
check "remove: says acme.sh keeps its own copy" contains "$OUT" "acme.sh keeps its own copy of the files in ${EZVPS_ACME_HOME}/example.com"
check "remove: key never printed" never_leaks "$OUT"
check "remove: exit 0" equals "$RC" 0
cert_run "3"
check "list after remove: the certificate is gone" contains "$OUT" "(none)"
rm_setup rm2
SUM_CONF="$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")"
RELOADS="$(nlog_count '^systemctl reload nginx$')"
CALLS="$(nlog_count '^acme.sh .*--remove')"
FAKE_NGX_FAIL_NTH=$(($(<"$FAKE_LOG.tcount") + 1))
cert_run "5\nexample.com\ny"
check "remove with a failing config test: reported" contains "$OUT" "config test FAILED after rewriting"
check "remove with a failing config test: the HTTPS site is restored byte for byte" cmp -s "$SCN/site-https" "$(CF example.com)"
check "remove with a failing config test: the certificate is NOT removed" cmp -s "$SCN/chain-orig" "$(CRTF example.com)"
check "remove with a failing config test: the key is NOT removed" cmp -s "$SCN/key-orig" "$(KEYF example.com)"
check "remove with a failing config test: nginx NOT reloaded" equals "$(nlog_count '^systemctl reload nginx$')" "$RELOADS"
check "remove with a failing config test: acme.sh --remove not run" equals "$(nlog_count '^acme.sh .*--remove')" "$CALLS"
check "remove with a failing config test: says the certificate was kept" contains "$OUT" "The certificate was kept"
check "remove with a failing config test: menu survives" equals "$RC" 0
rm_setup rm3
printf '%s\n' "server {" "    listen 443 ssl;" "    server_name second.example.com;" "    ssl_certificate $(CRTF example.com);" "    ssl_certificate_key $(KEYF example.com);" "}" >"$(CF second)"
cp "$(CF second)" "$SCN/second-original"
cert_run "5\nexample.com\ny"
check "remove while another file uses the certificate: refused" contains "$OUT" "conf.d/second.conf uses this certificate but is not an ezvps-made HTTPS site for example.com"
check "...nothing changed: certificate still stored" cmp -s "$SCN/chain-orig" "$(CRTF example.com)"
check "...nothing changed: both sites as they were" equals "$(cmp -s "$SCN/second-original" "$(CF second)" && cmp -s "$SCN/site-https" "$(CF example.com)" && echo same)" same
check "...no backup, acme.sh not run" equals "$(cert_backups example.com)$(acme_calls '--home .* --remove')" "00"
rm_setup rm4
printf '%s\n' "# hand written" "server {" "    listen 443 ssl;" "    server_name example.com;" "    ssl_certificate $(CRTF example.com);" "    ssl_certificate_key $(KEYF example.com);" "}" >"$(CF example.com)"
cp "$(CF example.com)" "$SCN/hand-original"
cert_run "5\nexample.com\ny"
check "remove with a non-ezvps site using it: never edited" cmp -s "$SCN/hand-original" "$(CF example.com)"
check "remove with a non-ezvps site using it: certificate kept" test -s "$(CRTF example.com)"
new_cert rm5
acme_present
mk_foreign_site example.com example.com
cert_run "2\nexample.com\ny"
cp "$(CRTF example.com)" "$SCN/chain-orig"
cert_run "5\nexample.com\ny"
check "remove with no ezvps site: certificate removed" test ! -e "$(CD example.com)"
check "remove with no ezvps site: the hand-written site is untouched" equals "$(file_has "$(CF example.com)" "    server_name example.com;" && echo same)" same
check "remove with no ezvps site: no nginx change, no reload for it" equals "$(nlog_count '^systemctl reload nginx$')" 0
check "remove with no ezvps site: backup of the certificate" cmp -s "$SCN/chain-orig" "$(cert_backup example.com)/fullchain.pem"
new_cert rm6
acme_present
mk_foreign_site example.com example.com
cert_run "2\nexample.com\ny"
FAKE_ACME_REMOVE_FAIL=1
cert_run "5\nexample.com\ny"
check "remove: an acme.sh --remove failure is only a warning, the store entry is gone" equals "$(test ! -e "$(CD example.com)" && echo gone)" gone
check "remove: ...and it says so" contains "$OUT" "acme.sh did not remove example.com from its renewal list"
new_cert rm7
acme_present
mk_foreign_site example.com example.com
cert_run "2\nexample.com\ny"
cert_run "5\nexample.com\ny" "$CB_NONGINX"
check "remove without nginx installed: the store entry is removed" equals "$(test ! -e "$(CD example.com)" && echo gone)" gone
check "remove without nginx installed: no nginx command was needed" not_contains "$OUT" "FAILED"

echo "-- certificates: nothing leaks and nothing else changes"
check "no certificate test ever prints key material" never_leaks "$(cat "$WORK"/scn-ngx-cert-*/calls.log 2>/dev/null)"
check "the backup dir of a certificate run is never world-readable" equals "$(stat -c %a "$EZVPS_BACKUP_DIR")" 700

echo "== operating systems (fake os-release files, EZVPS_SKIP_OS_CHECK off)"
# run_os <os-release file> <path-dir> <stdin-text> [args...]  -> OUT and RC, with the OS check ON
run_os() {
    local osf="$1" pathdir="$2" input="$3"
    shift 3
    OUT="$(printf '%b' "$input" | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$osf" PATH="$pathdir" "$BASH_BIN" "$EZVPS" "$@" 2>&1)"
    RC=$?
}
printf '%s\n' 'NAME="Linux Mint"' 'VERSION_ID="22"' 'VERSION_CODENAME=wilma' 'ID=linuxmint' 'ID_LIKE="ubuntu debian"' 'UBUNTU_CODENAME=noble' >"$OSD/mint"
printf '%s\n' 'NAME="Ubuntu"' 'VERSION_ID="24.04"' 'VERSION_CODENAME=noble' 'ID="ubuntu"' >"$OSD/ubuntu2404-quoted"
printf '%s\n' 'PRETTY_NAME="Debian GNU/Linux trixie/sid"' 'ID=debian' 'VERSION_CODENAME=trixie' >"$OSD/debian-sid" # no VERSION_ID
# The five supported systems (SPEC 1.1) as "fixture:id:Label:version:codename".
SUPPORTED_OS=(
    "debian12:debian:Debian:12:bookworm"
    "debian13:debian:Debian:13:trixie"
    "ubuntu2204:ubuntu:Ubuntu:22.04:jammy"
    "ubuntu2404:ubuntu:Ubuntu:24.04:noble"
    "ubuntu2604:ubuntu:Ubuntu:26.04:resolute"
)
# Accepted: the five systems, plus Ubuntu 24.04 with a quoted ID.
# Rejected, with what the refusal message must say it found:
#   fixture:found[:yes if the message must also say the codename does not match]
OS_CASES=(
    "debian12:yes:"
    "debian13:yes:"
    "ubuntu2204:yes:"
    "ubuntu2404:yes:"
    "ubuntu2404-quoted:yes:"
    "ubuntu2604:yes:"
    "ubuntu2510:no:ubuntu 25.10 questing"
    "ubuntu2504:no:ubuntu 25.04 plucky"
    "ubuntu2310:no:ubuntu 23.10 mantic"
    "ubuntu2610:no:ubuntu 26.10 nextrelease"
    "ubuntu2404-jammy:no:ubuntu 24.04 jammy:mismatch"
    "ubuntu2204-noble:no:ubuntu 22.04 noble:mismatch"
    "debian13-bookworm:no:debian 13 bookworm:mismatch"
    "debian12-noble:no:debian 12 noble:mismatch"
    "ubuntu2204-nocodename:no:ubuntu 22.04 unknown:mismatch"
    "debian11:no:debian 11 bullseye"
    "debian-sid:no:debian unknown trixie"
    "debian-testing:no:debian unknown forky"
    "unknown:no:fedora 40 unknown"
    "mint:no:linuxmint 22 wilma"
    "missing-file:no:unknown unknown unknown"
)
for c in "${OS_CASES[@]}"; do
    IFS=: read -r f ok found mism <<<"$c"
    osf="$OSD/$f"
    echo "-- os-release: ${f}"
    new_scn "os-xui-$f"
    run_os "$osf" "$SBOX" "2\n1\nn\n\n0\n\n0\n"
    if [[ "$ok" == yes ]]; then
        check "${f}: 3x-ui is accepted" contains "$OUT" "will download the official 3x-ui installer"
        check "${f}: 3x-ui shows no OS refusal" not_contains "$OUT" "needs a supported system"
    else
        check "${f}: 3x-ui is rejected with the shared message" contains "$OUT" "3x-ui install needs a supported system: ${OS_LIST_TEXT}; found '${found}'"
        check "${f}: 3x-ui rejection says nothing was changed" contains "$OUT" "Nothing was changed."
        [[ -n "$mism" ]] && check "${f}: 3x-ui rejection names the codename mismatch" contains "$OUT" "the codename does not match the version"
        check "${f}: 3x-ui rejected: nothing downloaded or installed" no_download
        check "${f}: 3x-ui rejected: no panel" no_panel_installed
        check "${f}: 3x-ui rejected: menu survives" equals "$RC" 0
    fi
    new_ngx "os-$f"
    run_os "$osf" "$NGX_BOX" "${N}1\nn\n\n0\n\n0\n"
    if [[ "$ok" == yes ]]; then
        check "${f}: Nginx is accepted" contains "$OUT" "ONLY from the official nginx.org STABLE repository"
        check "${f}: Nginx accepted, declined at the prompt: apt untouched" no_apt
    else
        check "${f}: Nginx is rejected with the shared message" contains "$OUT" "Nginx install needs a supported system: ${OS_LIST_TEXT}; found '${found}'"
        check "${f}: Nginx rejected: apt never called, no repository files" no_apt
        check "${f}: Nginx rejected: no key download" no_key_download
        check "${f}: Nginx rejected: no repository files" repo_absent
        check "${f}: Nginx rejected: menu survives" equals "$RC" 0
    fi
done

echo "-- the switch that skips the check still never picks a repository for an unknown or inconsistent system"
new_ngx os_skip_unknown
EZVPS_OS_RELEASE="$OSD/unknown" run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "skip + unknown distro: no nginx.org repository is chosen" contains "$OUT" "nginx.org packages are only set up for Debian and Ubuntu; found 'fedora'"
check "skip + unknown distro: apt never called, nothing written" no_apt
check "skip + unknown distro: repository files absent" repo_absent
for f in ubuntu2404-jammy ubuntu2510 debian13-bookworm debian11 ubuntu2204-noble; do
    new_ngx "os_skip_$f"
    EZVPS_OS_RELEASE="$OSD/$f" run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
    check "skip + ${f}: no repository is guessed" contains "$OUT" "Nginx install needs a supported system"
    check "skip + ${f}: apt never called, nothing written" no_apt
    check "skip + ${f}: repository files absent" repo_absent
done

echo "-- L2TP stays gated by ezl2tp: Debian 13 only"
run_os "$OSD/debian13" "$STUB_BIN" "1\n\n0\n"
check "L2TP on Debian 13: ezl2tp is launched" contains "$OUT" "FAKE-EZL2TP-RAN"
check "L2TP on Debian 13: no Debian-only message" not_contains "$OUT" "Debian 13 only"
run_os "$OSD/debian13" "$EMPTY_BIN" "1\n\n0\n"
check "L2TP on Debian 13 without ezl2tp: git clone help as before" contains "$OUT" "git clone"
# Every other supported system: a message, nothing launched, nothing installed, back to the menu.
for c in "debian12:Debian 12:bookworm" "ubuntu2204:Ubuntu 22.04:jammy" "ubuntu2404:Ubuntu 24.04:noble" "ubuntu2604:Ubuntu 26.04:resolute"; do
    IFS=: read -r f pretty cn <<<"$c"
    for stub in "$STUB_BIN" "$EMPTY_BIN"; do
        kind="ezl2tp present"
        [[ "$stub" == "$EMPTY_BIN" ]] && kind="ezl2tp absent"
        run_os "$OSD/$f" "$stub" "1\n\n0\n"
        check "L2TP on ${pretty} (${kind}): says Debian 13 only for now" contains "$OUT" "L2TP via ezl2tp is Debian 13 only for now (found ${pretty}, ${cn})"
        check "L2TP on ${pretty} (${kind}): ezl2tp is not launched" not_contains "$OUT" "FAKE-EZL2TP-RAN"
        check "L2TP on ${pretty} (${kind}): no install instructions" not_contains "$OUT" "git clone"
        check "L2TP on ${pretty} (${kind}): nothing changed, said so" contains "$OUT" "Nothing was changed."
        check "L2TP on ${pretty} (${kind}): back to the menu" at_least_menus "$OUT" 2
        check "L2TP on ${pretty} (${kind}): exit 0" equals "$RC" 0
    done
    run_os "$OSD/$f" "$STUB_BIN" "" l2tp
    check "'ezvps l2tp' on ${pretty}: message, nothing launched" contains "$OUT" "Debian 13 only for now"
    check "'ezvps l2tp' on ${pretty}: ezl2tp not launched" not_contains "$OUT" "FAKE-EZL2TP-RAN"
    check "'ezvps l2tp' on ${pretty}: exit 0" equals "$RC" 0
    EZVPS_OS_RELEASE="$OSD/$f" run_ezvps "$STUB_BIN" "" l2tp
    check "L2TP stays gated even with the OS-check switch on (${pretty}, tests)" not_contains "$OUT" "FAKE-EZL2TP-RAN"
done
for f in ubuntu2510 debian11 unknown ubuntu2404-jammy; do
    run_os "$OSD/$f" "$STUB_BIN" "1\n\n0\n"
    check "L2TP on ${f}: rejected as an unsupported system" contains "$OUT" "L2TP needs a supported system: ${OS_LIST_TEXT}"
    check "L2TP on ${f}: ezl2tp is not launched" not_contains "$OUT" "FAKE-EZL2TP-RAN"
    check "L2TP on ${f}: menu survives" equals "$RC" 0
done

echo "-- nginx.org repository per system, fake install flow"
# ngx_flow <tag> <os file> <Label> <distro> <codename> <the distribution's own nginx version> <other distro>
ngx_flow() {
    local tag="$1" osf="$2" label="$3" distro="$4" cn="$5" dver="$6" other="$7"
    local url="https://nginx.org/packages/${distro}" org="1.30.2-1~${5}"
    new_ngx "flow-$tag"
    FAKE_DISTRO="$distro" FAKE_CODENAME="$cn" FAKE_DISTRO_NGX_VERSION="$dver" FAKE_ORG_VERSION="$org"
    run_os "$osf" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
    check "${label}: plan shows the ${distro} repository for ${cn}" contains "$OUT" "deb [signed-by=$(KR)] ${url} ${cn} nginx"
    check "${label}: plan says it is not the ${label} package" contains "$OUT" "not ${label}'s package, not the mainline branch"
    check "${label}: apt source is exactly the ${distro}/${cn} stable line" file_has "$(LST)" "deb [signed-by=$(KR)] ${url} ${cn} nginx"
    check "${label}: apt source has no ${other} repository" file_lacks "$(LST)" "packages/${other}"
    check "${label}: apt source is never mainline" file_lacks "$(LST)" "mainline"
    check "${label}: key downloaded over https/TLS1.2 from nginx.org" has_line "$(log)" "curl KEY https://nginx.org/keys/nginx_signing.key"
    check "${label}: key download is secure" equals "$(nlog_count 'KEY-INSECURE')" 0
    check "${label}: all three pinned fingerprints verified" equals "$(count_lines "$OUT" "matches the pinned nginx.org key")" 3
    check "${label}: keyring stored" file_has "$(KR)" "fpr=${FPR_B}"
    check "${label}: pin is origin nginx.org, priority 900" file_has "$(PRF)" "Pin-Priority: 900"
    check "${label}: pin names origin nginx.org" file_has "$(PRF)" "Pin: origin nginx.org"
    check "${label}: key -> update -> install order" runs_before '^curl KEY ' '^apt-get update'
    check "${label}: update before install" runs_before '^apt-get update' '^apt-get install .*nginx$'
    check "${label}: candidate is the nginx.org stable package" contains "$OUT" "apt will install nginx ${org} from nginx.org (stable)"
    check "${label}: dpkg ends up with the nginx.org package" file_has "$FAKE_DPKG" "ii nginx ${org}"
    check "${label}: the ${label} package is never installed" file_lacks "$FAKE_DPKG" "$dver"
    check "${label}: nothing purged on a fresh machine" equals "$(nlog_count '^apt-get purge')" 0
    check "${label}: version check passes" contains "$OUT" "Version check passes: nginx/1.30.2 (nginx.org stable)"
    check "${label}: enable --now" has_line "$(log)" "systemctl enable --now nginx"
    check "${label}: config test runs" contains "$(log)" "nginx -t"
    check "${label}: service ends up running" equals "$(<"$FAKE_NGX_SVC")" active
    check "${label}: install exits 0" equals "$RC" 0
    run_os "$osf" "$NGX_BOX_INST" "${N}1\n\n0\n\n0\n"
    check "${label}: re-run is a no-op (already installed)" contains "$OUT" "nginx.org stable package ${org}). Not reinstalling"
    check "${label}: re-run: exactly one install" equals "$(nlog_count '^apt-get install .*nginx$')" 1

    # replacing the distribution's own nginx
    new_ngx "flowrep-$tag"
    FAKE_DISTRO="$distro" FAKE_CODENAME="$cn" FAKE_DISTRO_NGX_VERSION="$dver" FAKE_ORG_VERSION="$org" FAKE_PURGE_WIPES_CONFD=1
    ngx_up
    ngx_dpkg "$dver"
    printf 'ii nginx-common %s\nii libnginx-mod-http-geoip2 %s\nii unrelated-pkg 1.0\n' "$dver" "$dver" >>"$FAKE_DPKG"
    mk_ezvps_site example.com 127.0.0.1:3000
    mk_foreign_site handmade hand.example.com
    cp "$(CF example.com)" "$SCN/example-original"
    run_os "$osf" "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
    check "${label} replace: the ${label} package is called out" contains "$OUT" "not from nginx.org is installed (${dver}; for example ${label}'s). It will be REPLACED"
    check "${label} replace: /etc/nginx backed up exactly once" equals "$(etc_backups)" 1
    check "${label} replace: the backup holds the old config and the sites" test -f "$(etc_backup)/nginx.conf" -a -f "$(etc_backup)/conf.d/example.com.conf"
    check "${label} replace: backup was taken BEFORE the purge" has_line "$(log)" "purge-state etc-backup=1"
    check "${label} replace: the old packages are purged" has_line "$(log)" "apt-get purge -y -q nginx nginx-common libnginx-mod-http-geoip2"
    check "${label} replace: unrelated packages untouched" file_has "$FAKE_DPKG" "ii unrelated-pkg 1.0"
    check "${label} replace: repository (${distro}/${cn}) set up before the purge" runs_before '^apt-get update' '^apt-get purge'
    check "${label} replace: purge before the nginx.org install" runs_before '^apt-get purge' '^apt-get install .*nginx$'
    check "${label} replace: only the nginx.org package is left" file_has "$FAKE_DPKG" "ii nginx ${org}"
    check "${label} replace: ${label}'s nginx-common is gone" file_lacks "$FAKE_DPKG" "nginx-common"
    check "${label} replace: apt source is the ${distro}/${cn} line" file_has "$(LST)" "deb [signed-by=$(KR)] ${url} ${cn} nginx"
    check "${label} replace: the purge removed conf.d, the ezvps site is restored from the backup unchanged" cmp -s "$SCN/example-original" "$(CF example.com)"
    check "${label} replace: the hand-written site is not restored automatically, it stays in the backup" test ! -e "$(CF handmade)" -a -f "$(etc_backup)/conf.d/handmade.conf"
    check "${label} replace: config test before any reload" runs_before '^nginx-t-state' '^systemctl reload nginx$'
    check "${label} replace: exit 0" equals "$RC" 0
}
# The distribution's own nginx versions below are fake; only their shape (not "~<codename>") matters.
ngx_flow debian12 "$OSD/debian12" Debian debian bookworm 1.22.1-9+deb12u3 ubuntu
ngx_flow debian13 "$OSD/debian13" Debian debian trixie 1.26.3-3+deb13u1 ubuntu
ngx_flow ubuntu2204 "$OSD/ubuntu2204" Ubuntu ubuntu jammy 1.18.0-6ubuntu14.6 debian
ngx_flow ubuntu2404 "$OSD/ubuntu2404" Ubuntu ubuntu noble 1.24.0-2ubuntu7.1 debian
ngx_flow ubuntu2404_quoted "$OSD/ubuntu2404-quoted" Ubuntu ubuntu noble 1.24.0-2ubuntu7.1 debian
ngx_flow ubuntu2604 "$OSD/ubuntu2604" Ubuntu ubuntu resolute 1.28.0-1ubuntu1 debian

echo "-- every supported system: repository path and suite come from the detected codename"
for c in "${SUPPORTED_OS[@]}"; do
    IFS=: read -r f distro label ver cn <<<"$c"
    new_ngx "repo-$f"
    FAKE_DISTRO="$distro" FAKE_CODENAME="$cn" FAKE_ORG_VERSION="1.30.2-1~${cn}"
    run_os "$OSD/$f" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
    check "${label} ${ver}: apt source is exactly one line, packages/${distro} + suite ${cn}" equals "$(<"$(LST)")" "deb [signed-by=$(KR)] https://nginx.org/packages/${distro} ${cn} nginx"
    check "${label} ${ver}: installed package ends in ~${cn}" file_has "$FAKE_DPKG" "ii nginx 1.30.2-1~${cn}"
    check "${label} ${ver}: same signing key URL" has_line "$(log)" "curl KEY https://nginx.org/keys/nginx_signing.key"
    check "${label} ${ver}: same pin" file_has "$(PRF)" "Pin: origin nginx.org"
    check "${label} ${ver}: same pin priority" file_has "$(PRF)" "Pin-Priority: 900"
    # a candidate built for a different suite is refused (the codename is not hardcoded per distro)
    new_ngx "repo-other-$f"
    FAKE_DISTRO="$distro" FAKE_CODENAME="$cn" FAKE_ORG_VERSION="1.30.2-1~elsewhere"
    run_os "$OSD/$f" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
    check "${label} ${ver}: a candidate for another suite is refused" contains "$OUT" "expected a version ending in ~${cn}"
    check "${label} ${ver}: other-suite candidate: nothing installed" no_apt_install_or_purge
    # a mainline source anywhere in apt's config is refused on every system
    new_ngx "repo-main-$f"
    mkdir -p "$EZVPS_APT_DIR/sources.list.d"
    printf 'Types: deb\nURIs: https://nginx.org/packages/mainline/%s\nSuites: %s\nComponents: nginx\n' "$distro" "$cn" >"$EZVPS_APT_DIR/sources.list.d/other.sources"
    run_os "$OSD/$f" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
    check "${label} ${ver}: a mainline deb822 source is refused" contains "$OUT" "MAINLINE source is configured in"
    check "${label} ${ver}: mainline source: apt never called" no_apt
done

echo "-- Ubuntu 24.04: refusals keep the system untouched"
UB="$OSD/ubuntu2404"
new_ngx ub_nopin
FAKE_DISTRO=ubuntu FAKE_CODENAME=noble FAKE_DISTRO_NGX_VERSION=1.24.0-2ubuntu7.1 FAKE_ORG_VERSION="1.30.2-1~noble" FAKE_APT_IGNORE_PIN=1
ngx_up
ngx_dpkg 1.24.0-2ubuntu7.1
SUM_ETC="$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")"
run_os "$UB" "$NGX_BOX_INST" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu, pin not working: refused" contains "$OUT" "pin is not taking effect"
check "Ubuntu, pin not working: Ubuntu's nginx is not purged or replaced" no_apt_install_or_purge
check "Ubuntu, pin not working: dpkg still has Ubuntu's nginx" file_has "$FAKE_DPKG" "ii nginx 1.24.0-2ubuntu7.1"
check "Ubuntu, pin not working: /etc/nginx untouched" equals "$(file_sum "$EZVPS_NGINX_DIR/nginx.conf")" "$SUM_ETC"
check "Ubuntu, pin not working: repository files rolled back" repo_absent
new_ngx ub_wrongrepo
FAKE_DISTRO=debian FAKE_CODENAME=noble FAKE_ORG_VERSION="1.30.2-1~noble" # apt would only trust the Debian repository path
run_os "$UB" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu uses the ubuntu repository path, not debian (apt would reject it)" contains "$OUT" "pin is not taking effect"
check "Ubuntu wrong repository path: nothing installed" no_apt_install_or_purge
new_ngx ub_mainline_src
mkdir -p "$EZVPS_APT_DIR/sources.list.d"
echo "deb https://nginx.org/packages/mainline/ubuntu noble nginx" >"$EZVPS_APT_DIR/sources.list.d/other.list"
run_os "$UB" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu: a configured mainline source is refused" contains "$OUT" "MAINLINE source is configured in ${EZVPS_APT_DIR}/sources.list.d/other.list"
check "Ubuntu mainline source: apt never called, no key download" no_apt
check "Ubuntu mainline source: no key download" no_key_download
new_ngx ub_cand_main
FAKE_DISTRO=ubuntu FAKE_CODENAME=noble FAKE_ORG_VERSION="1.31.0-1~noble"
run_os "$UB" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu: a mainline 1.31 candidate is refused" contains "$OUT" "a MAINLINE build"
check "Ubuntu mainline candidate: nothing installed, files rolled back" nothing_installed
new_ngx ub_cand_old
FAKE_DISTRO=ubuntu FAKE_CODENAME=noble FAKE_ORG_VERSION="1.28.3-1~noble"
run_os "$UB" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu: a candidate below 1.30 is refused" contains "$OUT" "older than 1.30"
check "Ubuntu old candidate: nothing installed" no_apt_install_or_purge
new_ngx ub_cand_trixie
FAKE_DISTRO=ubuntu FAKE_CODENAME=noble FAKE_ORG_VERSION="1.30.2-1~trixie"
run_os "$UB" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu: a candidate built for another codename is refused" contains "$OUT" "expected a version ending in ~noble"
check "Ubuntu other-codename candidate: nothing installed" no_apt_install_or_purge
new_ngx ub_v_ubuntu
FAKE_DISTRO=ubuntu FAKE_CODENAME=noble FAKE_ORG_VERSION="1.30.2-1~noble" FAKE_APT_INSTALL_VERSION="1.24.0-2ubuntu7.1"
run_os "$UB" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu: an Ubuntu package version after install aborts" contains "$OUT" "still the Ubuntu package version (1.24.0-2ubuntu7.1)"
check "Ubuntu Ubuntu-version abort: nginx not started" no_mutation
new_ngx ub_v_main
FAKE_DISTRO=ubuntu FAKE_CODENAME=noble FAKE_ORG_VERSION="1.30.2-1~noble" FAKE_APT_INSTALL_VERSION="1.31.0-1~noble"
run_os "$UB" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu: a mainline build after install aborts" contains "$OUT" "VERSION CHECK FAILED: nginx/1.31.0 is a mainline build"
check "Ubuntu mainline build: nginx not started" no_mutation
new_ngx ub_badcodename
run_os "$OSD/ubuntu2404-jammy" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu 24.04 with codename jammy is refused as a mismatch, not accepted as Ubuntu" contains "$OUT" "Nginx install needs a supported system: ${OS_LIST_TEXT}; found 'ubuntu 24.04 jammy' (the codename does not match the version; ubuntu 24.04 is 'noble')"
check "Ubuntu wrong codename: nothing changed" nothing_installed
new_ngx ub_nocodename
run_os "$OSD/ubuntu2204-nocodename" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Ubuntu without a codename is refused" contains "$OUT" "found 'ubuntu 22.04 unknown'"
check "Ubuntu without a codename: nothing changed" nothing_installed
new_ngx deb_badcodename
run_os "$OSD/debian12-noble" "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "Debian 12 with the Ubuntu codename is refused" contains "$OUT" "found 'debian 12 noble' (the codename does not match the version; debian 12 is 'bookworm')"
check "Debian 12 wrong codename: nothing changed" nothing_installed

echo "-- 3x-ui default install on every supported system (check on)"
# The pinned upstream installer branches on ID (debian | ubuntu) only, so the
# flow is the same on all five releases.
for c in "${SUPPORTED_OS[@]}"; do
    IFS=: read -r f distro label ver cn <<<"$c"
    new_scn "xui_$f"
    run_os "$OSD/$f" "$SBOX" "2\n1\ny\n\n0\n\n0\n"
    check "${label} ${ver}: 3x-ui installer ran with the pinned tag" contains "$(log)" "FAKE-INSTALLER-RAN args=${PINNED_TAG} noninteractive=1 ssl=none port=3389"
    check "${label} ${ver}: panel settings applied" db_has "port=3389"
    check "${label} ${ver}: panel verified" contains "$OUT" "Verified: the panel answers on http://127.0.0.1:3389/xuipanel/"
    check "${label} ${ver}: change-password warning shown" contains "$OUT" "WARNING: CHANGE THE PANEL PASSWORD NOW"
    check "${label} ${ver}: exit 0" equals "$RC" 0
done

echo "-- Nginx stays HTTP only"
# The Certificates module validates with HTTP-01 through nginx only: no DNS API,
# no wildcard issuance and nothing that asks for provider credentials. certbot is not used.
no_dns_validation_code() { ! grep -vE '^[[:space:]]*#' "$1" | grep -qiE -- '--dns|dns_[a-z]+|CF_Token|api_?key|--accountemail|certbot'; }
check "ezvps contains no DNS-validation, DNS-credential or certbot code" no_dns_validation_code "$EZVPS"

echo "== Backpack, ctunnel and Lazyports lifecycle modules (fake binaries/installers/git/make, no network)"

# Pins as declared in ezvps.
LC_BP_TAG="$(grep -oE '^LC_BACKPACK_TAG="[^"]+"' "$EZVPS" | cut -d'"' -f2)"
LC_BP_SHA="$(grep -oE '^LC_BACKPACK_SHA256="[0-9a-f]{64}"' "$EZVPS" | cut -d'"' -f2)"
LC_CT_COMMIT="$(grep -oE '^LC_CTUNNEL_COMMIT="[0-9a-f]{40}"' "$EZVPS" | cut -d'"' -f2)"
LC_LZ_COMMIT="$(grep -oE '^LC_LAZYPORTS_COMMIT="[0-9a-f]{40}"' "$EZVPS" | cut -d'"' -f2)"
LC_LZ_SHA="$(grep -oE '^LC_LAZYPORTS_SHA256="[0-9a-f]{64}"' "$EZVPS" | cut -d'"' -f2)"
check "Backpack pin is declared (tag vX.Y.Z, sha256)" matches "$LC_BP_TAG-${#LC_BP_SHA}" '^v[0-9]+\.[0-9]+\.[0-9]+-64$'
check "ctunnel pin is a full 40-hex commit" test "${#LC_CT_COMMIT}" -eq 40
check "Lazyports pin is a full 40-hex commit and a sha256" test "${#LC_LZ_COMMIT}-${#LC_LZ_SHA}" = "40-64"
LC_BP_URL="https://raw.githubusercontent.com/AminMGMT/BackPack/${LC_BP_TAG}/install.sh"
LC_LZ_URL="https://raw.githubusercontent.com/v9mirza/lazyports/${LC_LZ_COMMIT}/install.sh"
LC_CT_GIT="https://github.com/alienrobotarmy/ctunnel.git"

LC_SAVED_HOME="$HOME"
LC_SAVED_BACKUP="${EZVPS_BACKUP_DIR-}"
LCW="$WORK/lc"
LC_STUBS="$LCW/stubs"
mkdir -p "$LC_STUBS"

# fake `uname` (architecture comes from FAKE_ARCH)
mkstub "$LC_STUBS/uname" <<'EOF'
echo "${FAKE_ARCH:-x86_64}"
EOF
# fake sha256sum: prints FAKE_SHA, so a test decides whether the "download" matches the pin
mkstub "$LC_STUBS/sha256sum" <<'EOF'
printf '%s  %s\n' "$FAKE_SHA" "$1"
EOF
# fake curl: serves the installer for the tool named in FAKE_INSTALLER (a path)
mkstub "$LC_STUBS/curl" <<'EOF'
out="" url="" prev=""
for a in "$@"; do
    [[ "$prev" == "-o" ]] && out="$a"
    [[ "$a" == http* ]] && url="$a"
    prev="$a"
done
echo "curl $url" >>"$FAKE_LOG"
[[ "$*" == *"--proto =https"* && "$*" == *"--tlsv1.2"* ]] || echo "curl INSECURE-FLAGS" >>"$FAKE_LOG"
[[ "${FAKE_DOWNLOAD_FAIL:-0}" == 1 ]] && exit 22
case "$url" in
    */install.sh) cp "$FAKE_INSTALLER" "$out"; exit 0 ;;
esac
echo "curl UNEXPECTED $*" >>"$FAKE_LOG"
exit 1
EOF
# fake go
mkstub "$LC_STUBS/go" <<'EOF'
[[ "${1:-}" == version ]] && echo "go version go${FAKE_GO_VERSION:-1.24.12} linux/amd64"
exit 0
EOF
mkstub "$LC_STUBS/gcc" <<'EOF'
exit 0
EOF
# fake systemctl: only `list-units`, answered from the FAKE_UNITS file
mkstub "$LC_STUBS/systemctl" <<'EOF'
echo "systemctl $*" >>"$FAKE_LOG"
if [[ "${1:-}" == list-units ]]; then
    if [[ -f "${FAKE_UNITS:-/nonexistent}" ]]; then
        while IFS= read -r l; do echo "$l"; done <"$FAKE_UNITS"
    fi
    exit 0
fi
echo "systemctl UNEXPECTED $*" >>"$FAKE_LOG"
exit 0
EOF
# fake git: records the calls; `fetch` makes the "source", rev-parse reports FAKE_GIT_HEAD
mkstub "$LC_STUBS/git" <<'EOF'
echo "git $*" >>"$FAKE_LOG"
dir="" args=("$@")
i=0
while ((i < ${#args[@]})); do
    case "${args[$i]}" in
        -c) i=$((i + 1)) ;;
        -C) dir="${args[$((i + 1))]}"; i=$((i + 1)) ;;
        init) mkdir -p "${args[$((${#args[@]} - 1))]}"; exit 0 ;;
        fetch) [[ "${FAKE_GIT_FAIL:-0}" == 1 ]] && { echo "fatal: unable to access" >&2; exit 128; }
               : >"$dir/FAKE-SOURCE"; exit 0 ;;
        checkout) exit 0 ;;
        rev-parse) echo "${FAKE_GIT_HEAD:-$FAKE_PIN_COMMIT}"; exit 0 ;;
    esac
    i=$((i + 1))
done
exit 0
EOF
# fake make: `make -C dir PREFIX=p` builds, `... install` installs the fake ctunnel
mkstub "$LC_STUBS/make" <<'EOF'
echo "make $*" >>"$FAKE_LOG"
dir="" prefix="" verb=""
while (($#)); do
    case "$1" in
        -C) dir="$2"; shift ;;
        PREFIX=*) prefix="${1#PREFIX=}" ;;
        install) verb=install ;;
    esac
    shift
done
[[ -f "$dir/FAKE-SOURCE" ]] || { echo "make: no source" >&2; exit 2; }
if [[ -z "$verb" ]]; then
    [[ "${FAKE_MAKE_FAIL:-0}" == 1 ]] && { echo "ctunnel.c: fatal error: openssl/evp.h: No such file or directory"; exit 2; }
    : >"$dir/FAKE-BUILT"
    exit 0
fi
[[ -f "$dir/FAKE-BUILT" ]] || { echo "make: nothing built" >&2; exit 2; }
mkdir -p "$prefix/bin" "$prefix/share/man/man1"
{
    printf '#!%s\n' "$BASH_BIN_PATH"
    printf 'echo "ctunnel %s Copyright (C) 2008-2020 Jess Mahan"\n' "${FAKE_CT_VERSION:-0.8}"
    printf 'case "$*" in -v) ;; *) echo CTUNNEL-WAS-RUN-AS-TUNNEL >>"$FAKE_LOG" ;; esac\n'
    echo 'echo "usage: ctunnel -c|-s -l ip:port -f ip:port -C cipher"; exit 0'
} >"$prefix/bin/ctunnel"
chmod +x "$prefix/bin/ctunnel"
: >"$prefix/share/man/man1/ctunnel.1"
echo "make-installed" >>"$FAKE_LOG"
exit 0
EOF
# fake apt-get: logs; installing curl / git / make / gcc adds the stub to the sandbox PATH dir
mkstub "$LC_STUBS/apt-get" <<'EOF'
echo "apt-get $*" >>"$FAKE_LOG"
[[ "${1:-}" == update ]] && exit 0
for a in "$@"; do
    case "$a" in
        curl | git | make | gcc) cp "$LC_STUBS_DIR/$a" "$FAKE_TOOLS_DIR/$a" ;;
    esac
done
exit 0
EOF

# --- fake tool binaries and installers ---------------------------------------------------------
# fake backpack: `version` prints the version file; with no argument it is a tiny menu that reads
# choices from stdin (8 = Update, 9 = Uninstall, 10 = Exit), standing in for Backpack's own CLI.
mkstub "$LCW/fake-backpack" <<'EOF'
if [[ "${1:-}" == version ]]; then
    echo "$(<"$FAKE_BP_VERSION_FILE")"
    echo "https://github.com/AminMGMT/BackPack"
    exit 0
fi
echo "BACKPACK-MENU-OPENED" >>"$FAKE_LOG"
while IFS= read -r choice; do
    case "$choice" in
        8) echo "$FAKE_BP_NEWVER" >"$FAKE_BP_VERSION_FILE"; echo "FAKE-BACKPACK: updated to $FAKE_BP_NEWVER" ;;
        9) echo "FAKE-BACKPACK: uninstalling" ; rm -f "$0"; rm -rf "$EZVPS_BACKPACK_CONF_DIR"; exit 0 ;;
        10) exit 0 ;;
        *) echo "FAKE-BACKPACK: ? $choice" ;;
    esac
done
exit 0
EOF
# fake official Backpack installer: records whether it got terminal input, installs the fake binary.
mkstub "$LCW/fake-installer-backpack.sh" <<'EOF'
n=0
while IFS= read -r -t 0.3 _; do n=$((n + 1)); done
echo "INSTALLER backpack args=$* stdin-lines=$n BP_HELPERS=${BP_HELPERS:-} BP_BUILD=${BP_BUILD_FROM_SOURCE:-}" >>"$FAKE_LOG"
[[ "${FAKE_INSTALLER_FAIL:-0}" == 1 ]] && { echo "[fake] installer failed" >&2; exit 1; }
mkdir -p "$EZVPS_TOOL_PREFIX/bin" "$EZVPS_BACKPACK_CONF_DIR"
if [[ "${FAKE_INSTALLER_NOBIN:-0}" != 1 ]]; then
    cp "$FAKE_BP_TEMPLATE" "$EZVPS_TOOL_PREFIX/bin/backpack"
    chmod +x "$EZVPS_TOOL_PREFIX/bin/backpack"
    echo "${FAKE_BP_INSTALLVER:-v1.9.0}" >"$FAKE_BP_VERSION_FILE"
fi
echo "[fake] Installed. Open the menu with: sudo backpack"
exit 0
EOF
# fake official Lazyports installer: needs `go`, puts the binary in the prefix, appends a PATH line to ~/.bashrc
mkstub "$LCW/fake-installer-lazyports.sh" <<'EOF'
echo "INSTALLER lazyports args=$* go=$(command -v go || echo none)" >>"$FAKE_LOG"
[[ "${FAKE_INSTALLER_FAIL:-0}" == 1 ]] && { echo "[fake] go install failed" >&2; exit 1; }
mkdir -p "$EZVPS_TOOL_PREFIX/bin"
printf '#!%s\necho LAZYPORTS-TUI\n' "$BASH_BIN_PATH" >"$EZVPS_TOOL_PREFIX/bin/lazyports"
chmod +x "$EZVPS_TOOL_PREFIX/bin/lazyports"
[[ "${FAKE_APPEND_RC:-1}" == 1 ]] && printf '\n# Added by Lazyports installer\nexport PATH=$PATH:/fake/go/bin\n' >>"$HOME/.bashrc"
echo "[fake] Lazyports installed"
exit 0
EOF

# --- sandboxes and scenarios -------------------------------------------------------------------
LC_CORE=(bash cp mkdir mv rm rmdir mktemp date chmod ln readlink)
# lc_box <dir> [omitted stub names...]: a PATH dir with coreutils + all stubs except the omitted ones
lc_box() {
    local d="$1" c s skip o
    shift
    rm -rf "$d"
    mkdir -p "$d"
    for c in "${LC_CORE[@]}"; do ln -s "$(command -v "$c")" "$d/$c"; done
    for s in "$LC_STUBS"/*; do
        skip=0
        for o in "$@"; do [[ "${s##*/}" == "$o" ]] && skip=1; done
        ((skip == 0)) && cp "$s" "$d/${s##*/}"
    done
}
LC_BOX="$LCW/box"
lc_box "$LC_BOX"

# lc_scene <name>: a fresh temp tree + environment for one scenario (exported; the log starts empty)
lc_scene() {
    LC_DIR="$LCW/scene-$1"
    rm -rf "$LC_DIR"
    mkdir -p "$LC_DIR/prefix" "$LC_DIR/home" "$LC_DIR/backups" "$LC_DIR/etc"
    export EZVPS_TOOL_PREFIX="$LC_DIR/prefix" EZVPS_BACKPACK_CONF_DIR="$LC_DIR/etc/backpack"
    export EZVPS_BACKUP_DIR="$LC_DIR/backups" HOME="$LC_DIR/home"
    export FAKE_LOG="$LC_DIR/log" FAKE_BP_VERSION_FILE="$LC_DIR/bp-version"
    export FAKE_BP_TEMPLATE="$LCW/fake-backpack" BASH_BIN_PATH="$BASH_BIN" LC_STUBS_DIR="$LC_STUBS"
    export FAKE_PIN_COMMIT="$LC_CT_COMMIT" FAKE_TOOLS_DIR="$LC_BOX"
    export FAKE_SHA="$LC_BP_SHA" FAKE_INSTALLER="$LCW/fake-installer-backpack.sh" FAKE_ARCH=x86_64
    export FAKE_BP_NEWVER="v1.9.1" FAKE_UNITS="$LC_DIR/units"
    unset FAKE_DOWNLOAD_FAIL FAKE_INSTALLER_FAIL FAKE_INSTALLER_NOBIN FAKE_GIT_FAIL FAKE_GIT_HEAD FAKE_MAKE_FAIL \
        FAKE_CT_VERSION FAKE_GO_VERSION FAKE_APPEND_RC FAKE_BP_INSTALLVER
    : >"$FAKE_LOG"
    lc_box "$LC_BOX"
}
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
log_lacks() { ! grep -qF -- "$1" "$FAKE_LOG"; }
log_count() { grep -cF -- "$1" "$FAKE_LOG"; }
backup_count() { # backup_count <name prefix>
    local n=0 f
    for f in "$LC_DIR/backups/$1"*; do [[ -e "$f" ]] && n=$((n + 1)); done
    echo "$n"
}
first_backup() { local f; for f in "$LC_DIR/backups/$1"*; do [[ -e "$f" ]] && { echo "$f"; return; }; done; }
# put an "installed" fake Backpack in place (binary, version file, a config with a fake secret marker)
lc_seed_backpack() {
    mkdir -p "$LC_DIR/prefix/bin" "$EZVPS_BACKPACK_CONF_DIR"
    cp "$LCW/fake-backpack" "$LC_DIR/prefix/bin/backpack"
    echo "${1:-v1.9.0}" >"$FAKE_BP_VERSION_FILE"
    printf 'name = "t1"\ntoken = "FAKE-TOKEN-DO-NOT-PRINT"\n' >"$EZVPS_BACKPACK_CONF_DIR/t1.toml"
}
lc_seed_ctunnel() {
    mkdir -p "$LC_DIR/prefix/bin" "$LC_DIR/prefix/share/man/man1"
    printf '#!%s\necho "ctunnel %s Copyright (C) 2008-2020 Jess Mahan"\n' "$BASH_BIN" "${1:-0.7}" >"$LC_DIR/prefix/bin/ctunnel"
    chmod +x "$LC_DIR/prefix/bin/ctunnel"
    : >"$LC_DIR/prefix/share/man/man1/ctunnel.1"
    printf 'FAKE-PASSKEY-DO-NOT-PRINT\n' >"$HOME/.passkey"
    chmod 600 "$HOME/.passkey"
}
lc_seed_lazyports() { # lc_seed_lazyports [system|home|both]
    local where="${1:-system}"
    printf '#!%s\necho LAZYPORTS-TUI\n' "$BASH_BIN" >"$LC_DIR/lp-template"
    if [[ "$where" != home ]]; then
        mkdir -p "$LC_DIR/prefix/bin"
        cp "$LC_DIR/lp-template" "$LC_DIR/prefix/bin/lazyports"
        chmod +x "$LC_DIR/prefix/bin/lazyports"
    fi
    if [[ "$where" != system ]]; then
        mkdir -p "$HOME/go/bin"
        cp "$LC_DIR/lp-template" "$HOME/go/bin/lazyports"
        chmod +x "$HOME/go/bin/lazyports"
    fi
    printf '# my bashrc\nalias ll="ls -l"\n' >"$HOME/.bashrc"
}
# run on the sandbox PATH: lc_run <input> <module-or-args...> -> OUT / RC
lc_run() {
    local input="$1"
    shift
    run_ezvps "$LC_BOX" "$input" "$@"
}
secrets_hidden() { [[ "$OUT" != *FAKE-TOKEN-DO-NOT-PRINT* && "$OUT" != *FAKE-PASSKEY-DO-NOT-PRINT* ]]; }

echo "-- submenus (shared by the three tools)"
lc_scene menus
for t in "backpack:Backpack:3" "ctunnel:ctunnel:4" "lazyports:Lazyports:7"; do
    IFS=: read -r key label num <<<"$t"
    lc_run "0\n" "$key"
    check "${label}: cli submenu exits 0" equals "$RC" 0
    check "${label}: submenu title" has_line "$OUT" "$label"
    check "${label}: ' 1) Install' is exact" has_line "$OUT" " 1) Install"
    check "${label}: ' 2) Status' is exact" has_line "$OUT" " 2) Status"
    check "${label}: ' 3) Update' is exact" has_line "$OUT" " 3) Update"
    check "${label}: ' 4) Uninstall' is exact" has_line "$OUT" " 4) Uninstall"
    check "${label}: ' 0) Back' is exact" has_line "$OUT" " 0) Back"
    check "${label}: exactly 5 numbered entries (clean labels)" equals "$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+\) ')" 5
    check "${label}: not reported as unimplemented" not_contains "$OUT" "not implemented yet"
    lc_run "${num}\n0\n\n0\n"
    check "${label}: reachable from main menu item ${num}, back returns to the menu" at_least_menus "$OUT" 2
    lc_run "9\n\n0\n" "$key"
    check "${label}: invalid choice is reported" contains "$OUT" "Invalid choice: 9"
    lc_run "" "$key"
    check "${label}: EOF returns cleanly" equals "$RC" 0
done

echo "-- Backpack: status when not installed / installed"
lc_scene bp-status
lc_run "2\n\n0\n" backpack
check "Backpack status: not installed" contains "$OUT" "Installed:  no"
check "Backpack status: says to install" contains "$OUT" "Backpack is not installed."
lc_seed_backpack v1.9.0
printf '%s\n' "backpack-t1.service loaded active running Backpack tunnel t1" "backpack-monitor.service loaded inactive dead Backpack monitor" >"$FAKE_UNITS"
lc_run "2\n\n0\n" backpack
check "Backpack status: installed" contains "$OUT" "Installed:  yes"
check "Backpack status: binary path" contains "$OUT" "Binary:     $LC_DIR/prefix/bin/backpack"
check "Backpack status: version from 'backpack version'" contains "$OUT" "Version:    v1.9.0"
check "Backpack status: documented tunnel service, running" contains "$OUT" "backpack-t1.service: active (running)"
check "Backpack status: documented monitor service, stopped" contains "$OUT" "backpack-monitor.service: inactive (dead)"
check "Backpack status: queries only backpack-*.service units" log_has "systemctl list-units --type=service --all --no-legend --plain backpack-*.service"
check "Backpack status: does not open Backpack" log_lacks "BACKPACK-MENU-OPENED"
check "Backpack status: makes no backup" equals "$(backup_count '')" 0
check "Backpack status: never prints the config's token" secrets_hidden
: >"$FAKE_UNITS"
lc_run "2\n\n0\n" backpack
check "Backpack status: installed but no tunnel services yet" contains "$OUT" "no backpack-*.service units found"
lc_box "$LC_BOX" systemctl
lc_run "2\n\n0\n" backpack
check "Backpack status without systemctl degrades with a message" contains "$OUT" "systemctl not found"

echo "-- Backpack: install"
lc_scene bp-install
lc_run "1\nn\n\n0\n" backpack
check "Backpack install declined: nothing downloaded" log_lacks "curl "
check "Backpack install declined: says nothing was changed" contains "$OUT" "Cancelled. Nothing was changed."
check "Backpack install declined: no binary" test ! -e "$LC_DIR/prefix/bin/backpack"
check "Backpack install plan shows the project" contains "$OUT" "https://github.com/AminMGMT/BackPack"
check "Backpack install plan shows the pinned installer URL" contains "$OUT" "installer: ${LC_BP_URL}"
check "Backpack install plan shows the pin and expected sha256" contains "$OUT" "sha256:    ${LC_BP_SHA} (expected)"
check "Backpack install plan says the tool is not started and nothing is asked" contains "$OUT" "asks for no tunnel settings, tokens or ports"
check "Backpack install plan promises a backup first" contains "$OUT" "backed up to $LC_DIR/backups/ first"
check "Backpack install plan names the supported system as accepted" contains "$OUT" "ezvps will install Backpack (this system and architecture are supported):"
lc_run "1\ny\n\n2\n\n0\n" backpack
check "Backpack install: exit 0" equals "$RC" 0
check "Backpack install: pinned URL downloaded once" equals "$(log_count "curl ${LC_BP_URL}")" 1
check "Backpack install: nothing else downloaded" equals "$(log_count 'curl ')" 1
check "Backpack install: download uses --proto =https --tlsv1.2" log_lacks "INSECURE-FLAGS"
check "Backpack install: hash check reported" contains "$OUT" "Downloaded installer matches the pinned sha256."
check "Backpack install: installer ran exactly once" equals "$(log_count 'INSTALLER backpack')" 1
check "Backpack install: installer got no arguments and no environment switches" log_has "INSTALLER backpack args= stdin-lines=0 BP_HELPERS= BP_BUILD="
check "Backpack install: installer saw /dev/null as input, so the menu input survived (status ran next)" contains "$OUT" "Installed:  yes"
check "Backpack install: installed binary is verified" contains "$OUT" "Installed: $LC_DIR/prefix/bin/backpack"
check "Backpack install: version reported" contains "$OUT" "Version:   v1.9.0"
check "Backpack install: only tells how to open it" contains "$OUT" "To open Backpack: run: backpack"
check "Backpack install: does not launch Backpack" log_lacks "BACKPACK-MENU-OPENED"
check "Backpack install: nothing to back up on a fresh system" contains "$OUT" "Nothing to back up yet."
check "Backpack install: no backups created" equals "$(backup_count '')" 0
check "Backpack install: asks for no token/link/password" not_contains "$OUT" "Token:"

echo "-- Backpack: already installed"
lc_scene bp-again
lc_seed_backpack v1.9.0
lc_run "1\nn\n\n0\n" backpack
check "already installed: says so with the version" contains "$OUT" "Backpack is already installed ($LC_DIR/prefix/bin/backpack, version v1.9.0)."
check "already installed: does not reinstall unless asked" contains "$OUT" "It will not be reinstalled unless you say so."
check "already installed, declined: nothing downloaded" log_lacks "curl "
check "already installed, declined: installer not run" log_lacks "INSTALLER"
check "already installed, declined: no backup" equals "$(backup_count '')" 0
lc_run "1\ny\nn\n\n0\n" backpack
check "reinstall: second question (the plan) can still stop it" log_lacks "INSTALLER"
check "reinstall declined at the plan: no backup" equals "$(backup_count '')" 0
lc_run "1\ny\ny\n\n0\n" backpack
check "reinstall: config backed up before the installer ran" test -f "$(first_backup backpack-1-backpack)/t1.toml"
check "reinstall: config backup is byte for byte" equals "$(cksum <"$(first_backup backpack-1-backpack)/t1.toml")" "$(cksum <"$EZVPS_BACKPACK_CONF_DIR/t1.toml")"
check "reinstall: binary backed up too" test -x "$(first_backup backpack-2-backpack)"
check "reinstall: backup dir is root-only (700)" equals "$(stat -c %a "$LC_DIR/backups")" 700
check "reinstall: installer ran once" equals "$(log_count 'INSTALLER backpack')" 1
check "reinstall: config left in place" test -f "$EZVPS_BACKPACK_CONF_DIR/t1.toml"
check "reinstall: still one binary" test -x "$LC_DIR/prefix/bin/backpack"
check "reinstall: secrets never printed" secrets_hidden
lc_run "1\ny\ny\n\n0\n" backpack
check "reinstall twice: no duplicate state, installer ran again once" equals "$(log_count 'INSTALLER backpack')" 2

echo "-- Backpack: failure paths"
lc_scene bp-fail
export FAKE_SHA="0000000000000000000000000000000000000000000000000000000000000000"
lc_run "1\ny\n\n0\n" backpack
check "hash mismatch: refused" contains "$OUT" "SHA-256 mismatch for the downloaded installer; refusing to run it."
check "hash mismatch: installer not run" log_lacks "INSTALLER"
check "hash mismatch: nothing installed" test ! -e "$LC_DIR/prefix/bin/backpack"
check "hash mismatch: menu continues, exit 0" equals "$RC" 0
export FAKE_SHA="$LC_BP_SHA"
export FAKE_DOWNLOAD_FAIL=1
lc_run "1\ny\n\n0\n" backpack
check "download failure: reported with the URL" contains "$OUT" "Download failed: ${LC_BP_URL}"
check "download failure: installer not run" log_lacks "INSTALLER"
check "download failure: exit 0" equals "$RC" 0
unset FAKE_DOWNLOAD_FAIL
export FAKE_INSTALLER_FAIL=1
lc_run "1\ny\n\n0\n" backpack
check "installer failure: status reported" contains "$OUT" "The Backpack installer exited with status 1."
check "installer failure: no success message" not_contains "$OUT" "Installed: "
unset FAKE_INSTALLER_FAIL
export FAKE_INSTALLER_NOBIN=1
lc_run "1\ny\n\n0\n" backpack
check "installer without a binary: reported as NOT installed" contains "$OUT" "Backpack is NOT installed."
unset FAKE_INSTALLER_NOBIN
lc_box "$LC_BOX" curl
lc_run "1\nn\n\n0\n" backpack
check "missing curl: explained before anything is installed" contains "$OUT" "curl is not installed; it is needed to download the Backpack installer."
check "missing curl, declined: nothing changed" log_lacks "apt-get"
check "missing curl, declined: said so" contains "$OUT" "Cancelled. Nothing was changed."
lc_box "$LC_BOX" curl
lc_run "1\ny\ny\n\n0\n" backpack
check "missing curl, accepted: apt-get installs curl" log_has "apt-get install -y -q curl"
check "missing curl, accepted: install then proceeds" log_has "INSTALLER backpack"

echo "-- Backpack: update through its own menu"
lc_scene bp-update
lc_run "3\n\n0\n" backpack
check "update when not installed: says so" contains "$OUT" "Backpack is not installed; there is nothing to update."
lc_seed_backpack v1.9.0
lc_run "3\nn\n\n0\n" backpack
check "update declined: Backpack not opened" log_lacks "BACKPACK-MENU-OPENED"
check "update declined: no backup" equals "$(backup_count '')" 0
check "update explains the documented method" contains "$OUT" "updates itself through its own Update menu"
lc_run "3\ny\n8\n10\n\n0\n" backpack
check "update: config backed up first" test -f "$(first_backup backpack-1-backpack)/t1.toml"
check "update: config backup is byte for byte" equals "$(cksum <"$(first_backup backpack-1-backpack)/t1.toml")" "$(cksum <"$EZVPS_BACKPACK_CONF_DIR/t1.toml")"
check "update: Backpack's own menu was opened" log_has "BACKPACK-MENU-OPENED"
check "update: the hint names the documented menu item" contains "$OUT" "choose 8 (Update)"
check "update: the update ran inside Backpack, not in ezvps" contains "$OUT" "FAKE-BACKPACK: updated to v1.9.1"
check "update: old and new version reported" contains "$OUT" "Updated: v1.9.0  ->  v1.9.1"
check "update: returns to ezvps" contains "$OUT" "Returned to ezvps."
check "update: secrets never printed" secrets_hidden
echo "v1.9.0" >"$FAKE_BP_VERSION_FILE"
lc_run "3\ny\n10\n\n0\n" backpack
check "update with no update applied: version unchanged reported" contains "$OUT" "Version is unchanged (v1.9.0)"

echo "-- Backpack: uninstall through its own menu"
lc_scene bp-uninstall
lc_run "4\n\n0\n" backpack
check "uninstall when not installed: says so" contains "$OUT" "Backpack is not installed; there is nothing to uninstall."
lc_seed_backpack v1.9.0
lc_run "4\nn\n\n0\n" backpack
check "uninstall declined: says nothing was changed" contains "$OUT" "Nothing was changed."
check "uninstall declined: Backpack not opened" log_lacks "BACKPACK-MENU-OPENED"
check "uninstall declined: binary still there" test -x "$LC_DIR/prefix/bin/backpack"
check "uninstall declined: no backup" equals "$(backup_count '')" 0
check "uninstall warns what upstream deletes" contains "$OUT" "deletes its tunnels, services"
lc_run "4\ny\n10\n\n0\n" backpack
check "uninstall without choosing Uninstall in Backpack: reported as still present" contains "$OUT" "Backpack is still present at"
check "uninstall without choosing Uninstall: not claimed as verified gone" not_contains "$OUT" "Verified: the backpack binary is gone."
rm -rf "$LC_DIR/backups"
mkdir -p "$LC_DIR/backups"
lc_run "4\ny\n9\n\n0\n" backpack
check "uninstall: config backed up before Backpack removed it" test -f "$(first_backup backpack-1-backpack)/t1.toml"
check "uninstall: config backup is byte for byte (token kept for the user, never printed)" equals "$(<"$(first_backup backpack-1-backpack)/t1.toml")" $'name = "t1"\ntoken = "FAKE-TOKEN-DO-NOT-PRINT"'
check "uninstall: Backpack's own uninstall ran" contains "$OUT" "FAKE-BACKPACK: uninstalling"
check "uninstall: binary is gone and ezvps verifies it" contains "$OUT" "Verified: the backpack binary is gone."
check "uninstall: binary really gone" test ! -e "$LC_DIR/prefix/bin/backpack"
check "uninstall: backups are kept" contains "$OUT" "The backups under $LC_DIR/backups/ are kept."
check "uninstall: backup still on disk after the tool removed its config" test -f "$(first_backup backpack-1-backpack)/t1.toml"
check "uninstall: secrets never printed" secrets_hidden
lc_run "2\n\n0\n" backpack
check "status after uninstall: not installed" contains "$OUT" "Installed:  no"

echo "-- Backpack: unsupported systems and architectures change nothing"
lc_scene bp-unsupported
for osf in ubuntu2510 ubuntu2504 ubuntu2310 ubuntu2610 debian11 debian-testing unknown ubuntu2404-jammy ubuntu2204-noble debian13-bookworm debian12-noble ubuntu2204-nocodename; do
    run_os "$OSD/$osf" "$LC_BOX" "1\ny\n\n0\n" backpack
    check "Backpack install refused on ${osf}" contains "$OUT" "Backpack install needs a supported system: ${OS_LIST_TEXT}; found '"
    check "Backpack install on ${osf}: nothing downloaded, nothing installed" equals "$(log_count 'curl ')$(test -e "$LC_DIR/prefix/bin/backpack" && echo present)" 0
done
run_os "$OSD/missing-file" "$LC_BOX" "1\ny\n\n0\n" backpack
check "Backpack install refused when os-release is missing" contains "$OUT" "found 'unknown unknown unknown'"
for osf in debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604; do
    run_os "$OSD/$osf" "$LC_BOX" "1\nn\n\n0\n" backpack
    check "Backpack install accepted on ${osf} (reaches the plan)" contains "$OUT" "ezvps will install Backpack (this system and architecture are supported):"
done
for a in armv7l armv6l i686 i386 s390x ppc64le riscv64 mips; do
    export FAKE_ARCH="$a"
    lc_run "1\ny\n\n0\n" backpack
    check "Backpack install refused on architecture ${a}" contains "$OUT" "Backpack install does not support architecture '${a}' (supported: x86_64, aarch64). Nothing was changed."
    check "Backpack install on ${a}: nothing downloaded" log_lacks "curl "
done
export FAKE_ARCH=aarch64
lc_run "1\nn\n\n0\n" backpack
check "Backpack install accepted on aarch64" contains "$OUT" "ezvps will install Backpack (this system and architecture are supported):"
export FAKE_ARCH=x86_64

echo "-- ctunnel: install from the pinned source commit"
lc_scene ct-install
lc_run "2\n\n0\n" ctunnel
check "ctunnel status: not installed" contains "$OUT" "Installed:  no"
lc_run "1\nn\n\n0\n" ctunnel
check "ctunnel plan: shows the project, git URL and the pinned commit" contains "$OUT" "source:    ${LC_CT_GIT}"
check "ctunnel plan: pinned commit" contains "$OUT" "pinned to: commit ${LC_CT_COMMIT}"
check "ctunnel plan: says there is no installer script or release" contains "$OUT" "ctunnel has no installer script or release"
check "ctunnel plan: names upstream's documented 'make; make install'" contains "$OUT" "'make; make install'"
check "ctunnel declined: nothing fetched or built" equals "$(log_count git)$(log_count make)" 00
lc_run "1\ny\n\n2\n\n0\n" ctunnel
check "ctunnel install: fetched exactly the pinned commit over https only" log_has "git -c protocol.allow=never -c protocol.https.allow=always -C "
check "ctunnel install: git fetch of the pinned commit, depth 1" log_has "fetch -q --depth 1 ${LC_CT_GIT} ${LC_CT_COMMIT}"
check "ctunnel install: commit verified with rev-parse" log_has "rev-parse HEAD"
check "ctunnel install: no curl and no installer script" equals "$(log_count 'curl ')$(log_count 'INSTALLER')" 00
check "ctunnel install: built with make" log_has "make -C "
check "ctunnel install: make install with the prefix" log_has " install PREFIX=$LC_DIR/prefix"
check "ctunnel install: binary installed" test -x "$LC_DIR/prefix/bin/ctunnel"
check "ctunnel install: man page installed" test -f "$LC_DIR/prefix/share/man/man1/ctunnel.1"
check "ctunnel install: version reported from 'ctunnel -v'" contains "$OUT" "Version:   ctunnel 0.8 Copyright (C) 2008-2020 Jess Mahan"
check "ctunnel install: only says how to open it" contains "$OUT" "To open ctunnel: run: ctunnel -h"
check "ctunnel install: never runs ctunnel as a tunnel" log_lacks "CTUNNEL-WAS-RUN-AS-TUNNEL"
check "ctunnel install: no panel, no unit" log_lacks "systemctl"
check "ctunnel install: status afterwards: installed" contains "$OUT" "Installed:  yes"
check "ctunnel status: no service is invented" contains "$OUT" "none documented upstream (ctunnel is a command-line program started by hand)"
check "ctunnel status: no running/stopped claim" not_contains "$OUT" "Service:    ctunnel: "
lc_scene ct-fail
export FAKE_GIT_HEAD="0000000000000000000000000000000000000000"
lc_run "1\ny\n\n0\n" ctunnel
check "ctunnel: a commit that does not verify is refused" contains "$OUT" "Could not fetch commit ${LC_CT_COMMIT}"
check "ctunnel: refused commit is not built" log_lacks "make -C"
unset FAKE_GIT_HEAD
export FAKE_GIT_FAIL=1
lc_run "1\ny\n\n0\n" ctunnel
check "ctunnel: git failure reported, nothing built" contains "$OUT" "Could not fetch commit"
unset FAKE_GIT_FAIL
export FAKE_MAKE_FAIL=1
lc_run "1\ny\n\n0\n" ctunnel
check "ctunnel: build failure reported with the log tail" contains "$OUT" "openssl/evp.h: No such file or directory"
check "ctunnel: build failure hints at the dev packages" contains "$OUT" "libssl-dev zlib1g-dev"
check "ctunnel: build failure installs nothing" test ! -e "$LC_DIR/prefix/bin/ctunnel"
check "ctunnel: build failure does not run make install" log_lacks "make-installed"
unset FAKE_MAKE_FAIL
lc_box "$LC_BOX" git make gcc
lc_run "1\nn\n\n0\n" ctunnel
check "ctunnel missing build tools: named and offered via apt-get" contains "$OUT" "Missing build tools: git make gcc"
check "ctunnel missing build tools, declined: nothing changed" log_lacks "apt-get"
lc_box "$LC_BOX" git make gcc
lc_run "1\ny\ny\n\n0\n" ctunnel
check "ctunnel missing build tools, accepted: one apt-get install of the build packages" log_has "apt-get install -y -q git make gcc libssl-dev zlib1g-dev"
check "ctunnel missing build tools, accepted: install then proceeds" test -x "$LC_DIR/prefix/bin/ctunnel"

echo "-- ctunnel: already installed, update (no documented method), uninstall"
lc_scene ct-life
lc_seed_ctunnel 0.7
lc_run "1\nn\n\n0\n" ctunnel
check "ctunnel already installed: says so with the version" contains "$OUT" "ctunnel is already installed ($LC_DIR/prefix/bin/ctunnel, version ctunnel 0.7 Copyright (C) 2008-2020 Jess Mahan)."
check "ctunnel already installed, declined: nothing fetched, nothing backed up" equals "$(log_count git)$(backup_count '')" 00
lc_run "3\nn\n\n0\n" ctunnel
check "ctunnel update: says clearly there is no documented update command" contains "$OUT" "ctunnel has no documented update command upstream, and ezvps does not guess one."
check "ctunnel update: points at the documented reinstall" contains "$OUT" "The documented way to get a newer ctunnel is to install it again from its source."
check "ctunnel update declined: nothing changed" equals "$(log_count git)$(backup_count '')" 00
export FAKE_CT_VERSION=0.9
lc_run "3\ny\ny\n\n0\n" ctunnel
check "ctunnel update: no update command is run" log_lacks "ctunnel update"
check "ctunnel update: binary backed up before the reinstall" test -x "$(first_backup ctunnel-2-ctunnel)"
check "ctunnel update: ~/.passkey backed up byte for byte" equals "$(<"$(first_backup ctunnel-1-passkey)")" "FAKE-PASSKEY-DO-NOT-PRINT"
check "ctunnel update: backup of the old binary is the OLD version" contains "$("$(first_backup ctunnel-2-ctunnel)")" "ctunnel 0.7"
check "ctunnel update: reinstalled from the pinned commit" log_has "${LC_CT_COMMIT}"
check "ctunnel update: old and new version reported" contains "$OUT" "Version:   ctunnel 0.7 Copyright (C) 2008-2020 Jess Mahan  ->  ctunnel 0.9 Copyright (C) 2008-2020 Jess Mahan"
check "ctunnel update: ~/.passkey left in place and never printed" secrets_hidden
check "ctunnel update: ~/.passkey still there" test -f "$HOME/.passkey"
unset FAKE_CT_VERSION
lc_scene ct-uninstall
lc_run "4\n\n0\n" ctunnel
check "ctunnel uninstall when not installed: says so" contains "$OUT" "ctunnel is not installed; there is nothing to uninstall."
lc_seed_ctunnel 0.8
lc_run "4\nn\n\n0\n" ctunnel
check "ctunnel uninstall: lists exactly what 'make uninstall' removes" contains "$OUT" "$LC_DIR/prefix/share/man/man1/ctunnel.1"
check "ctunnel uninstall declined: binary still there, no backup" equals "$(test -x "$LC_DIR/prefix/bin/ctunnel" && echo there)$(backup_count '')" there0
lc_run "4\ny\n\n0\n" ctunnel
check "ctunnel uninstall: binary backed up" test -x "$(first_backup ctunnel-2-ctunnel)"
check "ctunnel uninstall: ~/.passkey backed up byte for byte" equals "$(<"$(first_backup ctunnel-1-passkey)")" "FAKE-PASSKEY-DO-NOT-PRINT"
check "ctunnel uninstall: binary removed" test ! -e "$LC_DIR/prefix/bin/ctunnel"
check "ctunnel uninstall: man page removed" test ! -e "$LC_DIR/prefix/share/man/man1/ctunnel.1"
check "ctunnel uninstall: ezvps verifies the binary is gone" contains "$OUT" "Verified: the ctunnel binary is gone."
check "ctunnel uninstall: ~/.passkey is not deleted" test -f "$HOME/.passkey"
check "ctunnel uninstall: backups kept" test -x "$(first_backup ctunnel-2-ctunnel)"
check "ctunnel uninstall: secret never printed" secrets_hidden
lc_scene ct-elsewhere
mkdir -p "$LC_DIR/elsewhere"
printf '#!%s\necho "ctunnel 0.6 distro build"\n' "$BASH_BIN" >"$LC_DIR/elsewhere/ctunnel"
chmod +x "$LC_DIR/elsewhere/ctunnel"
cp "$LC_DIR/elsewhere/ctunnel" "$LC_BOX/ctunnel"
lc_run "2\n\n4\n\n0\n" ctunnel
check "ctunnel found on PATH outside the documented prefix counts as installed" contains "$OUT" "Binary:     $LC_BOX/ctunnel"
check "ctunnel uninstall of a PATH-only copy: refuses to guess, nothing removed" contains "$OUT" "not an upstream-documented location"
check "ctunnel uninstall of a PATH-only copy: binary untouched" test -x "$LC_BOX/ctunnel"
lc_scene ct-unsupported
run_os "$OSD/ubuntu2510" "$LC_BOX" "1\ny\n\n0\n" ctunnel
check "ctunnel install refused on Ubuntu 25.10" contains "$OUT" "ctunnel install needs a supported system: ${OS_LIST_TEXT}; found 'ubuntu 25.10 questing'. Nothing was changed."
check "ctunnel install refused on Ubuntu 25.10: nothing fetched" equals "$(log_count git)$(log_count make)" 00
export FAKE_ARCH=armv7l
lc_run "1\ny\n\n0\n" ctunnel
check "ctunnel install refused on armv7l" contains "$OUT" "ctunnel install does not support architecture 'armv7l' (supported: x86_64, aarch64). Nothing was changed."
check "ctunnel install on armv7l: nothing fetched" equals "$(log_count git)$(log_count make)" 00
export FAKE_ARCH=x86_64
for osf in debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604; do
    run_os "$OSD/$osf" "$LC_BOX" "1\nn\n\n0\n" ctunnel
    check "ctunnel install accepted on ${osf}" contains "$OUT" "ezvps will install ctunnel (this system and architecture are supported):"
done

echo "-- Lazyports: install (Go build via the pinned official installer)"
lc_scene lz-install
export FAKE_INSTALLER="$LCW/fake-installer-lazyports.sh" FAKE_SHA="$LC_LZ_SHA"
printf '# my bashrc\nalias ll="ls -l"\n' >"$HOME/.bashrc"
lc_run "2\n\n0\n" lazyports
check "Lazyports status: not installed" contains "$OUT" "Installed:  no"
lc_run "1\nn\n\n0\n" lazyports
check "Lazyports plan: pinned installer URL" contains "$OUT" "installer: ${LC_LZ_URL}"
check "Lazyports plan: pinned to a commit, says upstream has no tags" contains "$OUT" "pinned to: commit ${LC_LZ_COMMIT} (upstream publishes no tags or releases)"
check "Lazyports plan: expected sha256" contains "$OUT" "sha256:    ${LC_LZ_SHA} (expected)"
check "Lazyports plan: says the built code (main) is not pinned" contains "$OUT" "the code it builds is upstream's current"
check "Lazyports plan: names go install ...@main" contains "$OUT" "go install github.com/v9mirza/lazyports@main"
check "Lazyports plan: warns about the shell startup file" contains "$OUT" "may append a PATH line to"
check "Lazyports declined: nothing downloaded" log_lacks "curl "
lc_run "1\ny\n\n2\n\n0\n" lazyports
check "Lazyports install: pinned URL downloaded once" equals "$(log_count "curl ${LC_LZ_URL}")" 1
check "Lazyports install: downloaded with --proto =https --tlsv1.2" log_lacks "INSECURE-FLAGS"
check "Lazyports install: installer ran once, no arguments" log_has "INSTALLER lazyports args= go="
check "Lazyports install: binary installed" test -x "$LC_DIR/prefix/bin/lazyports"
check "Lazyports install: shell startup file backed up BEFORE the installer appended to it" equals "$(<"$(first_backup lazyports-1-bashrc)")" $'# my bashrc\nalias ll="ls -l"'
check "Lazyports install: the installer's PATH line is in the real .bashrc, not the backup" contains "$(<"$HOME/.bashrc")" "Added by Lazyports installer"
check "Lazyports install: version honestly not reported" contains "$OUT" "Version:   not reported (Lazyports documents no version command)"
check "Lazyports install: only says how to open it" contains "$OUT" "To open Lazyports: run: lazyports"
check "Lazyports install: status afterwards: installed" contains "$OUT" "Installed:  yes"
check "Lazyports status: no service is invented" contains "$OUT" "Lazyports is an interactive terminal program"
check "Lazyports status: no systemctl call at all" log_lacks "systemctl"
lc_run "1\ny\ny\n\n0\n" lazyports
check "Lazyports reinstall: asks first, backs up the existing binary" test -x "$(first_backup lazyports-2-lazyports)"
lc_scene lz-go
export FAKE_INSTALLER="$LCW/fake-installer-lazyports.sh" FAKE_SHA="$LC_LZ_SHA"
lc_box "$LC_BOX" go
lc_run "1\ny\n\n0\n" lazyports
check "Lazyports without Go: refused with how to get Go" contains "$OUT" "needs Go 1.24 or newer, and 'go' was not found."
check "Lazyports without Go: nothing downloaded or changed" equals "$(log_count 'curl ')$(backup_count '')" 00
export FAKE_GO_VERSION=1.19.8
lc_box "$LC_BOX"
lc_run "1\ny\n\n0\n" lazyports
check "Lazyports with Go 1.19: refused (cannot fetch the newer toolchain)" contains "$OUT" "older than 1.21"
check "Lazyports with Go 1.19: nothing downloaded" log_lacks "curl "
export FAKE_GO_VERSION=1.22.2
lc_run "1\ny\n\n0\n" lazyports
check "Lazyports with Go 1.22: warns, then installs" contains "$OUT" "Go 1.22 will try to download the newer toolchain"
check "Lazyports with Go 1.22: installed" test -x "$LC_DIR/prefix/bin/lazyports"
export FAKE_GO_VERSION=1.24.12
lc_scene lz-hash
export FAKE_INSTALLER="$LCW/fake-installer-lazyports.sh" FAKE_SHA="1111111111111111111111111111111111111111111111111111111111111111"
lc_run "1\ny\n\n0\n" lazyports
check "Lazyports: hash mismatch refused, installer not run" equals "$(log_count INSTALLER)$(contains "$OUT" 'SHA-256 mismatch' && echo mismatch)" 0mismatch
lc_scene lz-unsupported
export FAKE_INSTALLER="$LCW/fake-installer-lazyports.sh" FAKE_SHA="$LC_LZ_SHA"
run_os "$OSD/debian11" "$LC_BOX" "1\ny\n\n0\n" lazyports
check "Lazyports install refused on Debian 11" contains "$OUT" "Lazyports install needs a supported system: ${OS_LIST_TEXT}; found 'debian 11 bullseye'. Nothing was changed."
check "Lazyports install refused on Debian 11: nothing downloaded" log_lacks "curl "
export FAKE_ARCH=i686
lc_run "1\ny\n\n0\n" lazyports
check "Lazyports install refused on i686" contains "$OUT" "Lazyports install does not support architecture 'i686' (supported: x86_64, aarch64). Nothing was changed."
check "Lazyports install on i686: nothing downloaded" log_lacks "curl "
export FAKE_ARCH=x86_64
for osf in debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604; do
    run_os "$OSD/$osf" "$LC_BOX" "1\nn\n\n0\n" lazyports
    check "Lazyports install accepted on ${osf}" contains "$OUT" "ezvps will install Lazyports (this system and architecture are supported):"
done

echo "-- Lazyports: update (no documented method) and uninstall (remove the binary)"
lc_scene lz-life
export FAKE_INSTALLER="$LCW/fake-installer-lazyports.sh" FAKE_SHA="$LC_LZ_SHA"
lc_seed_lazyports system
lc_run "3\nn\n\n0\n" lazyports
check "Lazyports update: says clearly there is no documented update command" contains "$OUT" "Lazyports has no documented update command upstream, and ezvps does not guess one."
check "Lazyports update: points at the documented reinstall" contains "$OUT" "The documented way to get a newer Lazyports is to install it again from its source."
check "Lazyports update declined: nothing changed" equals "$(log_count 'curl ')$(backup_count '')" 00
lc_run "3\ny\ny\n\n0\n" lazyports
check "Lazyports update: reinstalled through the documented installer" log_has "INSTALLER lazyports"
check "Lazyports update: binary and shell file backed up first" equals "$(backup_count lazyports-1-bashrc)$(backup_count lazyports-2-lazyports)" 11
check "Lazyports update: no update command was invented" log_lacks "lazyports update"
lc_scene lz-uninstall
lc_run "4\n\n0\n" lazyports
check "Lazyports uninstall when not installed: says so" contains "$OUT" "Lazyports is not installed; there is nothing to uninstall."
lc_seed_lazyports both
lc_run "4\nn\n\n0\n" lazyports
check "Lazyports uninstall: lists both documented locations" contains "$OUT" "$HOME/go/bin/lazyports"
check "Lazyports uninstall declined: both binaries remain" equals "$(test -x "$LC_DIR/prefix/bin/lazyports" && test -x "$HOME/go/bin/lazyports" && echo both)$(backup_count '')" both0
lc_run "4\ny\n\n0\n" lazyports
check "Lazyports uninstall: system-wide binary removed" test ! -e "$LC_DIR/prefix/bin/lazyports"
check "Lazyports uninstall: user-local binary removed" test ! -e "$HOME/go/bin/lazyports"
check "Lazyports uninstall: backed up first" test -x "$(first_backup lazyports-2-lazyports)"
check "Lazyports uninstall: shell startup file backed up and untouched" equals "$(<"$HOME/.bashrc")" "$(<"$(first_backup lazyports-1-bashrc)")"
check "Lazyports uninstall: ezvps verifies the binary is gone" contains "$OUT" "Verified: the lazyports binary is gone."
check "Lazyports uninstall: says the config files are left alone" contains "$OUT" "your config and shell startup files stay as they are"
lc_scene lz-uninstall-home
lc_seed_lazyports home
lc_run "2\n\n4\ny\n\n0\n" lazyports
check "Lazyports installed only in ~/go/bin counts as installed" contains "$OUT" "Binary:     $HOME/go/bin/lazyports"
check "Lazyports user-local install is removed on uninstall" test ! -e "$HOME/go/bin/lazyports"

echo "-- lifecycle: modules never fail the menu"
lc_scene never-fail
for key in backpack ctunnel lazyports; do
    lc_run "1\n" "$key"
    check "${key}: EOF in the middle of an action still exits 0" equals "$RC" 0
done
lc_run "3\n\n4\n\n2\n\n0\n" backpack
check "Backpack: update/uninstall/status on a machine without it all return to the submenu" equals "$RC" 0

# leave the environment as the later sections expect it
export HOME="$LC_SAVED_HOME"
if [[ -n "$LC_SAVED_BACKUP" ]]; then export EZVPS_BACKUP_DIR="$LC_SAVED_BACKUP"; else unset EZVPS_BACKUP_DIR; fi
unset EZVPS_TOOL_PREFIX EZVPS_BACKPACK_CONF_DIR FAKE_LOG FAKE_ARCH FAKE_SHA FAKE_INSTALLER FAKE_GO_VERSION

echo "== SSH and Users module (fake passwd/group/sshd_config, stub useradd/usermod/userdel/passwd/chown/sshd/systemctl/ss, no real accounts)"

SSHW="$WORK/ssh"
SSH_STUBS="$SSHW/stubs"
mkdir -p "$SSH_STUBS"
SSH_SAVED_PAUSE="${EZVPS_NO_PAUSE-}"
export EZVPS_NO_PAUSE=1

# --- stubs: they edit the FAKE passwd/group/sshd_config files, never the system's ---------------
mkstub "$SSH_STUBS/useradd" <<'EOF'
echo "useradd $*" >>"$FAKE_LOG"
[[ "${FAKE_USERADD_FAIL:-0}" == 1 ]] && { echo "useradd: failure" >&2; exit 1; }
name="${!#}"
max=2000
while IFS=: read -r _ _ u _; do
    [[ "$u" =~ ^[0-9]+$ ]] && ((u < 60000 && u > max)) && max=$u
done <"$EZVPS_PASSWD_FILE"
uid=$((max + 1))
printf '%s:x:%s:%s::%s/%s:/bin/bash\n' "$name" "$uid" "$uid" "$EZVPS_HOME_BASE" "$name" >>"$EZVPS_PASSWD_FILE"
printf '%s:x:%s:\n' "$name" "$uid" >>"$EZVPS_GROUP_FILE"
mkdir -p "$EZVPS_HOME_BASE/$name"
exit 0
EOF
mkstub "$SSH_STUBS/usermod" <<'EOF'
echo "usermod $*" >>"$FAKE_LOG"
[[ "${FAKE_USERMOD_FAIL:-0}" == 1 ]] && { echo "usermod: failure" >&2; exit 1; }
[[ "${FAKE_USERMOD_NOOP:-0}" == 1 ]] && exit 0
args=("$@")
grp="${args[1]}" user="${args[3]}" out=""
while IFS= read -r l; do
    IFS=: read -r gn gp gg gm <<<"$l"
    if [[ "$gn" == "$grp" ]]; then
        if [[ -z "$gm" ]]; then gm="$user"; else gm="$gm,$user"; fi
        l="$gn:$gp:$gg:$gm"
    fi
    out+="$l"$'\n'
done <"$EZVPS_GROUP_FILE"
printf '%s' "$out" >"$EZVPS_GROUP_FILE"
exit 0
EOF
mkstub "$SSH_STUBS/userdel" <<'EOF'
echo "userdel $*" >>"$FAKE_LOG"
[[ "${FAKE_USERDEL_FAIL:-0}" == 1 ]] && { echo "userdel: failure" >&2; exit 1; }
rmhome=0 name=""
for a in "$@"; do
    case "$a" in -r) rmhome=1 ;; --) ;; *) name="$a" ;; esac
done
home="" out=""
while IFS= read -r l; do
    IFS=: read -r n _ _ _ _ h _ <<<"$l"
    if [[ "$n" == "$name" ]]; then home="$h"; continue; fi
    out+="$l"$'\n'
done <"$EZVPS_PASSWD_FILE"
printf '%s' "$out" >"$EZVPS_PASSWD_FILE"
out=""
while IFS= read -r l; do
    IFS=: read -r n _ <<<"$l"
    [[ "$n" == "$name" ]] && continue
    out+="$l"$'\n'
done <"$EZVPS_GROUP_FILE"
printf '%s' "$out" >"$EZVPS_GROUP_FILE"
((rmhome)) && rm -rf "$home"
exit 0
EOF
# fake passwd: records the call and prints a marker; it must not read stdin (ezvps never types a password)
mkstub "$SSH_STUBS/passwd" <<'EOF'
echo "passwd $*" >>"$FAKE_LOG"
echo "FAKE-PASSWD-PROMPT"
exit "${FAKE_PASSWD_RC:-0}"
EOF
mkstub "$SSH_STUBS/chown" <<'EOF'
echo "chown $*" >>"$FAKE_LOG"
exit "${FAKE_CHOWN_RC:-0}"
EOF
mkstub "$SSH_STUBS/apt-get" <<'EOF'
echo "apt-get $*" >>"$FAKE_LOG"
for a in "$@"; do
    [[ "$a" == sudo ]] && printf 'sudo:x:27:\n' >>"$EZVPS_GROUP_FILE"
done
exit 0
EOF
# fake sshd: -t fails on BROKEN_DIRECTIVE (or, with FAKE_SSHD_FAIL_AFTER_MANAGED, once ezvps has written its
# line); -T prints a small effective config (Include, first value wins, Port cumulative, Match skipped).
mkstub "$SSH_STUBS/sshd" <<'EOF'
mode="" cfg=""
while (($#)); do
    case "$1" in -t) mode=t ;; -T) mode=T ;; -f) cfg="$2"; shift ;; esac
    shift
done
echo "sshd -$mode" >>"$FAKE_LOG"
if [[ "$mode" == t ]]; then
    body="$(<"$cfg")"
    if [[ "$body" == *BROKEN_DIRECTIVE* ]] || { [[ "${FAKE_SSHD_FAIL_AFTER_MANAGED:-0}" == 1 ]] && [[ "$body" == *"# ezvps:managed"* ]]; }; then
        echo "$cfg line 3: Bad configuration option: BROKEN_DIRECTIVE" >&2
        exit 255
    fi
    exit 0
fi
declare -A seen
ports=()
parse() {
    local f="$1" line t kw val g inc inmatch=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        t="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$t" || "$t" == \#* ]] && continue
        kw="${t%%[[:space:]=]*}"
        kw="${kw,,}"
        val="${t:${#kw}}"
        val="${val#"${val%%[![:space:]=]*}"}"
        case "$kw" in
            match) inmatch=1 ;;
            include) for g in $val; do for inc in $g; do [[ -f "$inc" ]] && parse "$inc"; done; done ;;
            port) ((inmatch)) || ports+=("$val") ;;
            permitrootlogin | passwordauthentication | kbdinteractiveauthentication)
                ((inmatch)) || [[ -n "${seen[$kw]:-}" ]] || seen[$kw]="$val" ;;
        esac
    done <"$f"
}
parse "$cfg"
((${#ports[@]})) || ports=(22)
for p in "${ports[@]}"; do echo "port $p"; done
echo "permitrootlogin ${seen[permitrootlogin]:-without-password}"
echo "passwordauthentication ${seen[passwordauthentication]:-yes}"
echo "kbdinteractiveauthentication ${seen[kbdinteractiveauthentication]:-no}"
exit 0
EOF
# fake systemctl: restart re-binds the ports the config now names (the "listening" state is a file)
mkstub "$SSH_STUBS/systemctl" <<'EOF'
echo "systemctl $*" >>"$FAKE_LOG"
rebind() {
    [[ "${FAKE_NO_REBIND:-0}" == 1 ]] && return 0
    : >"$FAKE_LISTEN"
    while IFS= read -r l; do
        [[ "$l" == port\ * ]] && echo "${l#port }" >>"$FAKE_LISTEN"
    done < <("$FAKE_SSHD" -T -f "$EZVPS_SSHD_CONFIG")
}
case "${1:-}" in
    is-active)
        for a in "$@"; do
            [[ "$a" == ssh.socket ]] && { [[ "${FAKE_SOCKET:-0}" == 1 ]]; exit $?; }
            [[ "$a" == ssh ]] && { [[ "${FAKE_SSH_DOWN:-0}" != 1 ]]; exit $?; }
        done
        exit 0 ;;
    restart)
        if [[ "${FAKE_RESTART_FAIL:-0}" == 1 ]]; then echo "Job for ssh failed" >&2; exit 1; fi
        if [[ "${FAKE_RESTART_FAIL_ONCE:-0}" == 1 && ! -e "$FAKE_LOG.once" ]]; then : >"$FAKE_LOG.once"; echo "Job for ssh failed" >&2; exit 1; fi
        if [[ "${FAKE_SOCKET:-0}" == 1 ]]; then
            [[ "${2:-}" == ssh.socket ]] && rebind
        else
            rebind
        fi
        exit 0 ;;
esac
exit 0
EOF
# fake ss: a port is "in use" when it is in the listening file or the other-services file
mkstub "$SSH_STUBS/ss" <<'EOF'
port="${!#}"
port="${port##*:}"
port="${port%% *}"
port="${port%)}"
for f in "$FAKE_LISTEN" "$FAKE_BUSY"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r p; do
        [[ "$p" == "$port" ]] && { echo "LISTEN 0 128 0.0.0.0:$port 0.0.0.0:*"; exit 0; }
    done <"$f"
done
exit 0
EOF

# sandbox PATH: coreutils + stubs; some variants lack one command
mk_ssh_bin() { # mk_ssh_bin <dir> [missing...]
    local dir="$1" c s skip
    shift
    mkdir -p "$dir"
    for c in bash cp mkdir mv rm rmdir mktemp date chmod ln readlink; do ln -sf "$(command -v "$c")" "$dir/$c"; done
    for s in useradd usermod userdel passwd chown sshd systemctl ss apt-get; do
        for skip in "$@"; do [[ "$skip" == "$s" ]] && continue 2; done
        ln -sf "$SSH_STUBS/$s" "$dir/$s"
    done
}
SSHBIN="$SSHW/bin"
SSHBIN_NOSSHD="$SSHW/bin-nosshd"
SSHBIN_NOUSERADD="$SSHW/bin-nouseradd"
SSHBIN_NOAPT="$SSHW/bin-noapt"
mk_ssh_bin "$SSHBIN"
mk_ssh_bin "$SSHBIN_NOSSHD" sshd
mk_ssh_bin "$SSHBIN_NOUSERADD" useradd
mk_ssh_bin "$SSHBIN_NOAPT" apt-get

# --- fixtures ------------------------------------------------------------------------------------
SSH_N=0
ssh_new() { # fresh fake system; exports the paths the module and the stubs use
    SSH_N=$((SSH_N + 1))
    FIX="$SSHW/s$SSH_N"
    rm -rf "$FIX"
    mkdir -p "$FIX/home" "$FIX/proc/1" "$FIX/proc/self" "$FIX/backup" "$FIX/root" "$FIX/sshd_config.d" "$FIX/svc"
    local u
    for u in testadmin testuser primsudo legacy sysbash; do mkdir -p "$FIX/home/$u"; done
    cat >"$FIX/passwd" <<PASSWD
root:x:0:0:root:$FIX/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
www-data:x:33:33:www-data:$FIX/svc:/usr/sbin/nologin
svcfalse:x:998:998::$FIX/svc:/bin/false
sysbash:x:110:110::$FIX/home/sysbash:/bin/bash
testadmin:x:2001:2001:Test Admin:$FIX/home/testadmin:/bin/bash
testuser:x:2002:2002::$FIX/home/testuser:/bin/bash
testnohome:x:2003:2003::$FIX/home/testnohome:/bin/bash
primsudo:x:2004:27::$FIX/home/primsudo:/bin/bash
legacy:\$6\$fakesalt\$FAKEHASHFAKEHASHFAKEHASH:2005:2005::$FIX/home/legacy:/bin/zsh
PASSWD
    cat >"$FIX/group" <<'GROUP'
root:x:0:
sudo:x:27:testadmin
testadmin:x:2001:
testuser:x:2002:
GROUP
    printf '%s\n' '# /etc/shells: valid login shells' /bin/sh /bin/bash /usr/bin/bash /bin/zsh >"$FIX/shells"
    printf 'Name:\tinit\nUid:\t0\t0\t0\t0\n' >"$FIX/proc/1/status"
    printf '4294967295' >"$FIX/proc/self/loginuid"
    printf '22\n' >"$FIX/listen"
    : >"$FIX/busy"
    ssh_write_config
    export FAKE_LOG="$FIX/log" FAKE_LISTEN="$FIX/listen" FAKE_BUSY="$FIX/busy" FAKE_SSHD="$SSH_STUBS/sshd"
    export EZVPS_PASSWD_FILE="$FIX/passwd" EZVPS_GROUP_FILE="$FIX/group" EZVPS_SHELLS_FILE="$FIX/shells"
    export EZVPS_PROC_DIR="$FIX/proc" EZVPS_HOME_BASE="$FIX/home" EZVPS_SSHD_CONFIG="$FIX/sshd_config"
    export EZVPS_BACKUP_DIR="$FIX/backup" EZVPS_SSH_WAIT_SECONDS=0
    : >"$FAKE_LOG"
    unset SUDO_USER SUDO_UID SSH_CONNECTION FAKE_USERADD_FAIL FAKE_USERMOD_FAIL FAKE_USERMOD_NOOP FAKE_USERDEL_FAIL \
        FAKE_PASSWD_RC FAKE_CHOWN_RC FAKE_SSHD_FAIL_AFTER_MANAGED FAKE_RESTART_FAIL FAKE_RESTART_FAIL_ONCE FAKE_NO_REBIND \
        FAKE_SOCKET FAKE_SSH_DOWN
}
ssh_write_config() { # a Debian-style sshd_config with a cloud-init style drop-in that sets PasswordAuthentication
    cat >"$FIX/sshd_config" <<CONF
# This is the sshd server system-wide configuration file.
Include $FIX/sshd_config.d/*.conf

#Port 22
#PermitRootLogin prohibit-password
#PasswordAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
CONF
    printf 'PasswordAuthentication yes\n' >"$FIX/sshd_config.d/50-cloud-init.conf"
    chmod 644 "$FIX/sshd_config"
}
ssh_proc_for_uid() { # a fake running process owned by <uid>
    mkdir -p "$FIX/proc/$2"
    printf 'Name:\tbash\nUid:\t%s\t%s\t%s\t%s\n' "$1" "$1" "$1" "$1" >"$FIX/proc/$2/status"
}
run_ssh() { # run_ssh <stdin> [ezvps args]; environment comes from the caller
    local input="$1"
    shift
    OUT="$(printf '%b' "$input" | PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" "${@:-ssh}" 2>&1)"
    RC=$?
}
log_has() { grep -qF -- "$1" "$FAKE_LOG"; }
log_lacks() { ! grep -qF -- "$1" "$FAKE_LOG"; }
log_line() { grep -nF -- "$1" "$FAKE_LOG" | head -1 | cut -d: -f1; }
log_after() { # log_after <first> <second>: both logged, first before second
    local a b
    a="$(log_line "$1")" b="$(log_line "$2")"
    [[ -n "$a" && -n "$b" ]] && ((a < b))
}
nfiles() { # nfiles <dir> <glob>
    local n=0 f
    for f in "$1"/$2; do [[ -e "$f" ]] && n=$((n + 1)); done
    printf '%s' "$n"
}
file_has() { grep -qF -- "$2" "$1"; }
file_lacks() { ! grep -qF -- "$2" "$1"; }
same_file() { cmp -s "$1" "$2"; }
count_in_file() { grep -cF -- "$2" "$1"; }

# fake keys: the right base64 prefix for the type, then filler. Not keys of anyone.
SSH_BLOB_ED="AAAAC3NzaC1lZDI1NTE5$(printf 'FAKE%.0s' {1..12})"
SSH_BLOB_ED2="AAAAC3NzaC1lZDI1NTE5$(printf 'WXYZ%.0s' {1..12})"
SSH_BLOB_RSA="AAAAB3NzaC1y$(printf 'FAKE%.0s' {1..22})"
SSH_KEY_LINE="ssh-ed25519 ${SSH_BLOB_ED} testuser@example.com"
SSH_KEY_LINE2="ssh-ed25519 ${SSH_BLOB_ED2} second@example.com"
# a private key header, assembled at run time so this file holds no key marker
SSH_PRIV_HDR="-----BEGIN OPENSSH PRIVATE"" KEY-----"

# --- submenu and dispatch --------------------------------------------------------------------------
ssh_new
run_ssh "0\n"
for l in " 1) List users" " 2) Add user" " 3) Delete user" " 4) SSH settings" " 5) Add SSH key" " 0) Back"; do
    check "SSH submenu line '${l}' is exact (clean label)" has_line "$OUT" "$l"
done
check "SSH submenu has exactly 5 numbered entries" equals "$(printf '%s\n' "$OUT" | grep -cE '^ *[1-9]\) ')" 5
check "SSH module is no longer 'not implemented'" not_contains "$OUT" "is not implemented yet"
check "SSH submenu exits 0 on 0" equals "$RC" 0
run_ssh "" ssh
check "SSH submenu exits 0 on EOF" equals "$RC" 0
run_ssh "9\nabc\n0\n"
check "SSH submenu reports an invalid choice" contains "$OUT" "Invalid choice: 9"
check "SSH submenu reports a non-numeric choice" contains "$OUT" "Invalid choice: abc"
OUT="$(printf '8\n0\n0\n' | PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" 2>&1)"
check "main menu item 8 (SSH and Users) opens the submenu" contains "$OUT" " 4) SSH settings"

# --- List users ----------------------------------------------------------------------------------
echo "-- SSH and Users: list users"
ssh_new
run_ssh "1\nn\n0\n"
check "list: root is shown with its UID" contains "$OUT" "root"
for u in testadmin testuser primsudo legacy; do
    check "list shows ${u} (login shell and home directory)" contains "$OUT" "$u"
done
check "list: sysbash (login shell and home, system UID) is shown with its UID" contains "$OUT" "sysbash                  110"
check "list: header has USER, UID and SUDO" contains "$OUT" "USER                     UID      SUDO"
check "list: testadmin UID and sudo=yes in one row" contains "$OUT" "testadmin                2001     yes"
check "list: testuser UID and sudo=no in one row" contains "$OUT" "testuser                 2002     no"
check "list: a user whose primary group is sudo has sudo=yes" contains "$OUT" "primsudo                 2004     yes"
check "list: root is n/a for sudo" contains "$OUT" "root                     0        n/a"
for u in daemon www-data svcfalse sync testnohome; do
    check "list hides ${u} (nologin/false shell, pseudo shell or no home directory)" not_contains "$OUT" "$u  "
done
check "list never prints a password hash" not_contains "$OUT" "FAKEHASH"
check "list never prints the hash prefix either" not_contains "$OUT" '$6$'
check "list does not show the full list when declined" not_contains "$OUT" "All accounts:"
run_ssh "1\ny\n0\n"
check "full list on request" contains "$OUT" "All accounts:"
check "full list shows a nologin service account" contains "$OUT" "www-data"
check "full list shows a /bin/false account" contains "$OUT" "svcfalse"
check "full list shows shells" contains "$OUT" "/usr/sbin/nologin"
check "full list still never prints a password hash" not_contains "$OUT" "FAKEHASH"
rm -f "$FIX/shells"
run_ssh "1\nn\n0\n"
check "without a shells file only nologin/false are filtered (testuser listed)" contains "$OUT" "testuser"
check "without a shells file www-data is still hidden" not_contains "$OUT" "www-data"
check "list needs no root/OS check (works on an unsupported system)" contains "$(EZVPS_SKIP_OS_CHECK=0 EZVPS_OS_RELEASE="$OSD/ubuntu2510" PATH="$SSHBIN" bash -c 'printf "1\nn\n0\n" | "$0" "$1" ssh 2>&1' "$BASH_BIN" "$EZVPS")" "testuser"

# --- Add user ------------------------------------------------------------------------------------
echo "-- SSH and Users: add user"
ssh_new
run_ssh "2\nnewuser\nn\ny\nn\n0\n"
check "add (no sudo): exits 0" equals "$RC" 0
check "add (no sudo): useradd creates a home and a bash shell" log_has "useradd --create-home --shell /bin/bash -- newuser"
check "add (no sudo): the user is in passwd" file_has "$FIX/passwd" "newuser:x:2006:"
check "add (no sudo): home directory exists" test -d "$FIX/home/newuser"
check "add (no sudo): usermod is not called" log_lacks "usermod"
check "add (no sudo): not in the sudo group" file_lacks "$FIX/group" "sudo:x:27:testadmin,newuser"
check "add (no sudo): reports the created username" contains "$OUT" "Created user: newuser (UID 2006)"
check "add (no sudo): reports sudo: no" contains "$OUT" "sudo     : no"
check "add (no sudo): password is not set and passwd is not run" log_lacks "passwd"
check "add (no sudo): says password login is locked" contains "$OUT" "not set (password login is locked)"
check "add (no sudo): makes no backup for a new user" equals "$(nfiles "$FIX/backup" '*')" 0
ssh_new
run_ssh "2\nsudoer\ny\ny\nn\n0\n"
check "add (sudo): usermod -aG sudo is the group method used" log_has "usermod -aG sudo -- sudoer"
check "add (sudo): the group file lists the user in sudo" file_has "$FIX/group" "sudo:x:27:testadmin,sudoer"
check "add (sudo): sudo is added to the sudo group only (one usermod call)" equals "$(grep -c '^usermod' "$FAKE_LOG")" 1
check "add (sudo): reports sudo: yes" contains "$OUT" "sudo     : yes"
check "add (sudo): reports the username" contains "$OUT" "Created user: sudoer"
check "add (sudo): useradd ran before usermod" log_after "useradd" "usermod"
ssh_new
run_ssh "2\npwuser\nn\ny\ny\n0\n"
check "add + password: passwd runs through the system prompt for that user" log_has "passwd -- pwuser"
check "add + password: the (fake) system prompt was shown" contains "$OUT" "FAKE-PASSWD-PROMPT"
check "add + password: reports it as set" contains "$OUT" "password : set with passwd"
check "add + password: ezvps handles no password text (nothing but the prompt marker)" not_contains "$OUT" "Password:"
FAKE_PASSWD_RC=10 run_ssh "2\npwfail\nn\ny\ny\n0\n"
check "add: a failing passwd is reported with the manual command" contains "$OUT" "Set the password later with: passwd pwfail"
check "add: a failing passwd still leaves the user created" file_has "$FIX/passwd" "pwfail:x:"
ssh_new
run_ssh "2\nnewuser\nn\nn\n0\n"
check "add: declining the plan creates nothing" log_lacks "useradd"
check "add: declining says nothing was changed" contains "$OUT" "Nothing was changed"
for bad in "Bad Name" "1abc" "UPPER" "a;b" "../x" "-rf" "a.b" "user\$" "abcdefghijklmnopqrstuvwxyzabcdefg"; do
    ssh_new
    run_ssh "2\n${bad}\ny\ny\nn\n0\n"
    check "add refuses invalid username '${bad}'" contains "$OUT" "Invalid username"
    check "add: invalid username '${bad}' runs no useradd" log_lacks "useradd"
done
ssh_new
run_ssh "2\ntestuser\n0\n"
check "add refuses an existing username" contains "$OUT" "User 'testuser' already exists"
check "add: existing username runs no useradd" log_lacks "useradd"
run_ssh "2\nroot\n0\n"
check "add refuses root as an existing username" contains "$OUT" "User 'root' already exists"
printf 'groupy:x:3001:\n' >>"$FIX/group"
run_ssh "2\ngroupy\n0\n"
check "add refuses a name that is already a group" contains "$OUT" "A group named 'groupy' already exists"
run_ssh "2\n\n0\n"
check "add: empty username cancels" contains "$OUT" "Cancelled. Nothing was changed."
FAKE_USERADD_FAIL=1 run_ssh "2\nnewuser\nn\ny\nn\n0\n"
check "add: a failing useradd is reported and nothing else is done" contains "$OUT" "useradd did not create 'newuser'"
check "add: a failing useradd runs no usermod" log_lacks "usermod"
ssh_new
FAKE_USERMOD_NOOP=1 run_ssh "2\nnoopuser\ny\ny\nn\n0\n"
check "add: sudo membership is verified (usermod that did nothing is caught)" contains "$OUT" "Sudo access was NOT granted"
check "add: unverified sudo is reported as sudo: no" contains "$OUT" "sudo     : no"
ssh_new
FAKE_USERMOD_FAIL=1 run_ssh "2\nfailuser\ny\ny\nn\n0\n"
check "add: a failing usermod means sudo: no" contains "$OUT" "sudo     : no"
# no sudo group: offer apt-get; decline, then create without sudo / cancel
ssh_new
printf 'root:x:0:\ntestuser:x:2002:\n' >"$FIX/group"
run_ssh "2\nnosudo1\ny\nn\ny\ny\nn\n0\n"
check "add: missing sudo group is explained" contains "$OUT" "the sudo package is not installed"
check "add: apt-get is not run without a yes" log_lacks "apt-get install"
check "add: user is created without sudo after the second question" file_has "$FIX/passwd" "nosudo1:x:"
check "add: no usermod when sudo is unavailable" log_lacks "usermod"
run_ssh "2\nnosudo2\ny\nn\nn\n0\n"
check "add: declining 'create without sudo' cancels" file_lacks "$FIX/passwd" "nosudo2:x:"
run_ssh "2\nnosudo3\ny\ny\ny\ny\nn\n0\n"
check "add: apt-get installs sudo only after a yes" log_has "apt-get install -y -q sudo"
check "add: after installing sudo the group method is used" log_has "usermod -aG sudo -- nosudo3"
check "add: sudo granted after installing the package" file_has "$FIX/group" "nosudo3"
OUT="$(printf '2\nnoapt\ny\ny\nn\n0\n' | PATH="$SSHBIN_NOAPT" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
check "add: without apt-get the sudo package is not offered (user can still be created without sudo)" not_contains "$OUT" "Install the sudo package"
# system / tool checks
ssh_new
OUT="$(printf '2\nnewuser\n0\n' | PATH="$SSHBIN_NOUSERADD" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
check "add: missing useradd gives a clear message, nothing changed" contains "$OUT" "Required command(s) not found: useradd"
OUT="$(printf '2\nnewuser\ny\ny\nn\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/ubuntu2510" PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
check "add: unsupported system is refused with the shared message" contains "$OUT" "SSH and Users needs a supported system: ${OS_LIST_TEXT}; found 'ubuntu 25.10 questing'"
check "add: unsupported system runs no useradd" log_lacks "useradd"
for f in debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604; do
    ssh_new
    OUT="$(printf '2\nosuser\nn\ny\nn\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/$f" PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
    check "add works on ${f} (same code path)" log_has "useradd --create-home --shell /bin/bash -- osuser"
done
OUT="$(printf '2\nnewuser\n0\n' | env EZVPS_ALLOW_NONROOT=0 PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
if ((EUID != 0)); then
    check "add: a non-root run is refused by ezvps itself" contains "$OUT" "ezvps must be run as root."
fi

# --- Delete user ---------------------------------------------------------------------------------
echo "-- SSH and Users: delete user"
ssh_new
run_ssh "3\nroot\n0\n"
check "delete refuses root" contains "$OUT" "Refusing to delete root"
check "delete root: userdel is never called" log_lacks "userdel"
check "delete root: passwd file unchanged" file_has "$FIX/passwd" "root:x:0:0:"
printf 'toor:x:0:0:toor:%s/root:/bin/bash\n' "$FIX" >>"$FIX/passwd"
run_ssh "3\ntoor\n0\n"
check "delete refuses any UID 0 account" contains "$OUT" "UID 0 is a root account"
check "delete UID 0: userdel not called" log_lacks "userdel"
SUDO_USER=testuser run_ssh "3\ntestuser\ny\n0\n"
check "delete refuses the current user (sudo caller)" contains "$OUT" "that is the account you are logged in with"
check "delete current user: userdel not called" log_lacks "userdel"
printf '2002' >"$FIX/proc/self/loginuid"
run_ssh "3\ntestuser\ny\n0\n"
check "delete refuses the account that logged in (audit login uid)" contains "$OUT" "that is the account you are logged in with"
check "delete login uid: userdel not called" log_lacks "userdel"
printf '4294967295' >"$FIX/proc/self/loginuid"
run_ssh "3\ndaemon\ny\n0\n"
check "delete refuses a system account (UID below 1000)" contains "$OUT" "it is a system account"
run_ssh "3\nsysbash\ny\n0\n"
check "delete refuses a system UID even with a login shell" contains "$OUT" "it is a system account"
check "delete system account: userdel not called" log_lacks "userdel"
run_ssh "3\nnosuchuser\n0\n"
check "delete reports an unknown user" contains "$OUT" "User 'nosuchuser' does not exist"
run_ssh "3\nBad Name\n0\n"
check "delete refuses an invalid username" contains "$OUT" "Invalid username"
run_ssh "3\n\n0\n"
check "delete: empty username cancels" contains "$OUT" "Cancelled. Nothing was changed."
ssh_proc_for_uid 2002 4242
run_ssh "3\ntestuser\ny\ny\n0\n"
check "delete refuses a user with running processes" contains "$OUT" "1 process(es) are running as this user (PIDs: 4242)"
check "delete with processes: does not offer an override or ask again" not_contains "$OUT" "Delete the user"
check "delete with processes: userdel never called" log_lacks "userdel"
check "delete with processes: user still in passwd" file_has "$FIX/passwd" "testuser:x:2002:"
check "delete with processes: nothing was backed up or changed" equals "$(nfiles "$FIX/backup" '*')" 0
ssh_new
printf 'Name:\tbash\nUid:\t0\t2002\t2002\t2002\n' >"$FIX/proc/1/status"
run_ssh "3\ntestuser\ny\n0\n"
check "delete also sees a process whose effective UID matches" contains "$OUT" "process(es) are running as this user"
ssh_new
rm -rf "$FIX/proc"
run_ssh "3\ntestuser\ny\n0\n"
check "delete refuses when running processes cannot be checked" contains "$OUT" "Cannot check running processes"
check "delete (no proc): userdel not called" log_lacks "userdel"
# confirmations
ssh_new
run_ssh "3\ntestuser\nn\n0\n"
check "delete: declining the confirmation changes nothing" log_lacks "userdel"
check "delete: declining keeps the user" file_has "$FIX/passwd" "testuser:x:2002:"
check "delete: declining makes no backup" equals "$(nfiles "$FIX/backup" '*')" 0
run_ssh "3\ntestuser\ny\nn\n0\n"
check "delete without the second confirmation: userdel has no -r" log_has "userdel -- testuser"
check "delete without the second confirmation: no -r anywhere" log_lacks "userdel -r"
check "delete: the account is gone from passwd" file_lacks "$FIX/passwd" "testuser:x:2002:"
check "delete: the home directory is kept by default" test -d "$FIX/home/testuser"
check "delete: reports the kept home directory" contains "$OUT" "home directory: kept"
check "delete: reports the deletion" contains "$OUT" "Deleted user: testuser"
check "delete: passwd and group are backed up first" equals "$(nfiles "$FIX/backup" 'users-*')" 2
check "delete: the passwd backup is a byte-for-byte copy of the original" file_has "$(printf '%s' "$FIX"/backup/users-passwd.*)" "testuser:x:2002:"
ssh_new
run_ssh "3\ntestuser\ny\ny\n0\n"
check "delete + home confirmed separately: userdel -r" log_has "userdel -r -- testuser"
check "delete + home: the home directory is removed" test ! -e "$FIX/home/testuser"
check "delete + home: the second warning names the path" contains "$OUT" "The home directory $FIX/home/testuser and everything in it can be deleted too"
check "delete + home: reports it" contains "$OUT" "home directory: removed"
ssh_new
run_ssh "3\ntestuser\ny\nn\n0\n"
check "the home directory prompt is a separate question (answering n keeps files)" test -d "$FIX/home/testuser"
# home safety
ssh_new
printf 'outside:x:2010:2010::/srv/ezvps-fake-outside:/bin/bash\n' >>"$FIX/passwd"
run_ssh "3\noutside\ny\ny\n0\n"
check "delete: a home outside the home base is not offered for removal" contains "$OUT" "The home directory will be kept"
check "delete: outside home -> userdel without -r" log_has "userdel -- outside"
printf 'twin:x:2011:2011::%s/home/testadmin:/bin/bash\n' "$FIX" >>"$FIX/passwd"
run_ssh "3\ntestadmin\ny\ny\n0\n"
check "delete: a home shared with another account is not removed" contains "$OUT" "is shared with the account 'twin'"
check "delete: shared home stays on disk" test -d "$FIX/home/testadmin"
ssh_new
mkdir -p "$FIX/elsewhere"
rm -rf "$FIX/home/testuser"
ln -s "$FIX/elsewhere" "$FIX/home/testuser"
run_ssh "3\ntestuser\ny\ny\n0\n"
check "delete: a symlinked home is never removed" contains "$OUT" "is a symbolic link"
check "delete: symlink target untouched" test -d "$FIX/elsewhere"
ssh_new
FAKE_USERDEL_FAIL=1 run_ssh "3\ntestuser\ny\nn\n0\n"
check "delete: a failing userdel is reported, user still listed" contains "$OUT" "userdel did not remove 'testuser'"
ssh_new
OUT="$(printf '3\ntestuser\ny\nn\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/debian11" PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
check "delete: unsupported system is refused" contains "$OUT" "SSH and Users needs a supported system"
check "delete: unsupported system runs no userdel" log_lacks "userdel"

# --- SSH settings --------------------------------------------------------------------------------
echo "-- SSH and Users: SSH settings"
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n0\n0\n"
check "settings: submenu labels are clean" has_line "$OUT" " 1) SSH port"
check "settings: PermitRootLogin item" has_line "$OUT" " 2) PermitRootLogin"
check "settings: PasswordAuthentication item" has_line "$OUT" " 3) PasswordAuthentication"
check "settings: offers only the three settings (no 4th item)" not_contains "$OUT" " 4) PermitEmptyPasswords"
check "settings: shows the effective port" contains "$OUT" "Port                   : 22"
check "settings: shows the effective PermitRootLogin" contains "$OUT" "PermitRootLogin        : prohibit-password"
check "settings: shows the effective PasswordAuthentication from the drop-in" contains "$OUT" "PasswordAuthentication : yes"
check "settings: just looking changes nothing (config identical)" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "settings: just looking makes no backup" equals "$(nfiles "$FIX/backup" '*')" 0
# port change
run_ssh "4\n1\n2222\ny\n0\n"
check "port: the change is reported as verified" contains "$OUT" "Verified: sshd listens on port 2222."
check "port: a backup of sshd_config was made first" equals "$(nfiles "$FIX/backup" 'sshd_config.*')" 1
check "port: the backup is a byte-for-byte copy of the original" same_file "$(printf '%s' "$FIX"/backup/sshd_config.*)" "$FIX/sshd_config.orig"
check "port: the new Port line is written" file_has "$FIX/sshd_config" "Port 2222"
check "port: it sits above the Include so a drop-in cannot override it" test "$(grep -n '^Port 2222' "$FIX/sshd_config" | cut -d: -f1)" -lt "$(grep -n '^Include' "$FIX/sshd_config" | cut -d: -f1)"
check "port: other lines are kept (Include, UsePAM, X11Forwarding)" contains "$(<"$FIX/sshd_config")" "UsePAM yes"
check "port: file mode is preserved" equals "$(stat -c %a "$FIX/sshd_config")" 644
check "port: sshd -t ran" log_has "sshd -t"
check "port: sshd was restarted" log_has "systemctl restart ssh"
check "port: sshd -t ran before the restart" log_after "sshd -t" "systemctl restart ssh"
check "port: only sshd was restarted (not reloaded, not the socket)" log_lacks "restart ssh.socket"
check "port: warns about the firewall" contains "$OUT" "allow port 2222 BEFORE you close the old one"
check "port: tells you to test from a second terminal" contains "$OUT" "second terminal"
check "port: no temp file left behind" equals "$(nfiles "$FIX" 'sshd_config.ezvps.*')" 0
ssh_new
printf 'Port 22\nPort 2200\n' >"$FIX/sshd_config.tmp"
cat "$FIX/sshd_config" >>"$FIX/sshd_config.tmp"
mv "$FIX/sshd_config.tmp" "$FIX/sshd_config"
run_ssh "4\n1\n2222\ny\n0\n"
check "port: existing active Port lines are commented out (Port is cumulative)" contains "$(<"$FIX/sshd_config")" "# ezvps disabled: Port 22"
check "port: both old Port lines disabled" contains "$(<"$FIX/sshd_config")" "# ezvps disabled: Port 2200"
check "port: exactly one active Port line remains" equals "$(grep -c '^Port ' "$FIX/sshd_config")" 1
# re-run is idempotent
n_before="$(nfiles "$FIX/backup" '*')"
: >"$FAKE_LOG"
run_ssh "4\n1\n2222\n0\n"
check "port: choosing the current port again is a no-op" contains "$OUT" "already listens only on port 2222"
check "port: the no-op makes no backup" equals "$(nfiles "$FIX/backup" '*')" "$n_before"
check "port: the no-op does not restart sshd" log_lacks "systemctl restart"
run_ssh "4\n1\n3333\ny\n0\n"
check "port: a second change keeps one managed Port block" equals "$(count_in_file "$FIX/sshd_config" '# ezvps:managed Port')" 1
check "port: a second change has one active Port line" equals "$(grep -c '^Port ' "$FIX/sshd_config")" 1
check "port: the second change is the active one" file_has "$FIX/sshd_config" "Port 3333"
# invalid / busy / declined
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
for bad in abc 0 80 1023 65536 99999 -5 "22 22" ""; do
    run_ssh "4\n1\n${bad}\n0\n"
    if [[ -z "$bad" ]]; then
        check "port: an empty answer cancels" contains "$OUT" "Cancelled. Nothing was changed."
    else
        check "port: '${bad}' is refused" contains "$OUT" "Invalid port"
    fi
done
check "port: refused input changes nothing" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "port: refused input makes no backup and restarts nothing" equals "$(nfiles "$FIX/backup" '*')-$(grep -c restart "$FAKE_LOG")" "0-0"
printf '8080\n' >"$FIX/busy"
run_ssh "4\n1\n8080\ny\n0\n"
check "port: a port that another service uses is refused" contains "$OUT" "Something already listens on port 8080"
check "port: busy port changes nothing" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n1\n2222\nn\n0\n"
check "port: declining the confirmation changes nothing" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "port: declining makes no backup" equals "$(nfiles "$FIX/backup" '*')" 0
SSH_CONNECTION="198.51.100.7 51234 192.0.2.10 22" run_ssh "4\n1\n2222\nn\n0\n"
check "port: warns about the current SSH session" contains "$OUT" "connected over SSH right now"
run_ssh "4\n1\n2222\nn\n0\n"
check "port: no session warning when not on SSH" not_contains "$OUT" "connected over SSH right now"
# failing sshd -t -> rollback, no restart
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
FAKE_SSHD_FAIL_AFTER_MANAGED=1 run_ssh "4\n1\n2222\ny\n0\n"
check "sshd -t failure: the error is shown" contains "$OUT" "sshd -t rejected the new configuration"
check "sshd -t failure: config rolled back byte for byte" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "sshd -t failure: says it rolled back" contains "$OUT" "Rolled back"
check "sshd -t failure: sshd is NOT restarted" log_lacks "systemctl restart"
check "sshd -t failure: says sshd was not restarted" contains "$OUT" "sshd was NOT restarted"
check "sshd -t failure: the backup exists" equals "$(nfiles "$FIX/backup" 'sshd_config.*')" 1
FAKE_SSHD_FAIL_AFTER_MANAGED=1 run_ssh "4\n3\n1\ny\ny\n0\n"
check "sshd -t failure (auth setting): rolled back too" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "sshd -t failure (auth setting): never restarted" log_lacks "systemctl restart"
# already broken config
ssh_new
printf 'BROKEN_DIRECTIVE yes\n' >>"$FIX/sshd_config"
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n1\n2222\ny\n0\n"
check "broken config: ezvps refuses before changing anything" contains "$OUT" "sshd -t already fails on the current configuration"
check "broken config: file untouched, no backup, no restart" equals "$(cksum <"$FIX/sshd_config")-$(nfiles "$FIX/backup" '*')-$(grep -c restart "$FAKE_LOG")" "$(cksum <"$FIX/sshd_config.orig")-0-0"
# restart failure / not listening -> rollback
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
FAKE_RESTART_FAIL_ONCE=1 run_ssh "4\n1\n2222\ny\n0\n"
check "restart failure: reported" contains "$OUT" "Restarting sshd failed"
check "restart failure: config restored byte for byte" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "restart failure: sshd restarted again with the old config" contains "$OUT" "sshd was restarted with the previous configuration"
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
FAKE_NO_REBIND=1 run_ssh "4\n1\n2222\ny\n0\n"
check "port not listening after restart: reported" contains "$OUT" "sshd is not listening on port 2222"
check "port not listening after restart: config rolled back" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
FAKE_RESTART_FAIL=1 run_ssh "4\n1\n2222\ny\n0\n"
check "restart that always fails: rolled back and the problem is reported" contains "$OUT" "could not be restarted after the rollback"
check "restart that always fails: config restored" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
ssh_new
FAKE_SOCKET=1 run_ssh "4\n1\n2222\ny\n0\n"
check "socket activation: a port change reloads systemd and restarts ssh.socket" log_after "systemctl daemon-reload" "systemctl restart ssh.socket"
check "socket activation: the port change is verified" contains "$OUT" "Verified: sshd listens on port 2222."
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
FAKE_SOCKET=1 FAKE_NO_REBIND=1 run_ssh "4\n1\n2222\ny\n0\n"
check "socket activation that keeps the old port: rolled back and ssh.socket is named" contains "$OUT" "ssh.socket"
check "socket activation that keeps the old port: config restored" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
ssh_new
FAKE_SOCKET=1 run_ssh "4\n2\n1\ny\n0\n"
check "socket activation: a non-port change leaves the socket alone" log_lacks "restart ssh.socket"
# a drop-in that still adds a port -> the change would not take effect -> rolled back
ssh_new
printf 'Port 2200\n' >"$FIX/sshd_config.d/60-extra.conf"
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n1\n2222\ny\n0\n"
check "effective check: a drop-in that adds another port is caught" contains "$OUT" "The change would not take effect"
check "effective check: config rolled back" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "effective check: sshd not restarted" log_lacks "systemctl restart"
# PermitRootLogin
echo "-- SSH and Users: PermitRootLogin and PasswordAuthentication"
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n2\n1\ny\n0\n"
check "root login no: a clear lock-out warning comes first" contains "$OUT" "Disabling root login over SSH can lock you out"
check "root login no: notes that another sudo account exists" contains "$OUT" "Another account with sudo access exists"
check "root login no: written" file_has "$FIX/sshd_config" "PermitRootLogin no"
check "root login no: backed up byte for byte" same_file "$(printf '%s' "$FIX"/backup/sshd_config.*)" "$FIX/sshd_config.orig"
check "root login no: tested before restart" log_after "sshd -t" "systemctl restart ssh"
check "root login no: verified running" contains "$OUT" "Verified: sshd is running with PermitRootLogin no."
run_ssh "4\n0\n0\n"
check "root login no: the effective value changed" contains "$OUT" "PermitRootLogin        : no"
ssh_new
printf 'root:x:0:\nsudo:x:27:\ntestuser:x:2002:\n' >"$FIX/group"
grep -v '^primsudo:' "$FIX/passwd" >"$FIX/passwd.new" && mv "$FIX/passwd.new" "$FIX/passwd"
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n2\n1\nn\n0\n"
check "root login no without any sudo account: a stronger warning" contains "$OUT" "No other account with sudo access was found"
check "root login no without a sudo account: declining the extra question changes nothing" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "root login no without a sudo account: no backup either" equals "$(nfiles "$FIX/backup" '*')" 0
run_ssh "4\n2\n1\ny\ny\n0\n"
check "root login no without a sudo account: can still be done after both yes" file_has "$FIX/sshd_config" "PermitRootLogin no"
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n2\n1\nn\n0\n"
check "root login: declining the confirmation changes nothing" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n2\n2\n0\n"
check "root login: choosing the current value is a no-op" contains "$OUT" "PermitRootLogin is already prohibit-password"
run_ssh "4\n2\n3\ny\n0\n"
check "root login yes: warns it is not recommended" contains "$OUT" "not recommended"
check "root login yes: written" file_has "$FIX/sshd_config" "PermitRootLogin yes"
run_ssh "4\n2\n9\n0\n"
check "root login: an out-of-range choice cancels" contains "$OUT" "Cancelled. Nothing was changed."
# PasswordAuthentication
ssh_new
mkdir -p "$FIX/home/testadmin/.ssh"
printf '%s\n' "$SSH_KEY_LINE" >"$FIX/home/testadmin/.ssh/authorized_keys"
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n3\n1\ny\n0\n"
check "password auth no: warns that only keys will work" contains "$OUT" "ONLY SSH keys work"
check "password auth no: tells you to test a key login first" contains "$OUT" "Test a key login in a second terminal"
check "password auth no: written above the Include" test "$(grep -n '^PasswordAuthentication no' "$FIX/sshd_config" | cut -d: -f1)" -lt "$(grep -n '^Include' "$FIX/sshd_config" | cut -d: -f1)"
check "password auth no: the cloud-init style drop-in no longer wins (verified effective)" contains "$OUT" "Verified: sshd is running with PasswordAuthentication no."
check "password auth no: the drop-in itself is untouched" equals "$(<"$FIX/sshd_config.d/50-cloud-init.conf")" "PasswordAuthentication yes"
check "password auth no: backed up before the change" equals "$(nfiles "$FIX/backup" 'sshd_config.*')" 1
check "password auth no: sshd -t before restart" log_after "sshd -t" "systemctl restart ssh"
run_ssh "4\n3\n2\ny\n0\n"
check "password auth yes: warns" contains "$OUT" "exposes the server to password guessing"
check "password auth yes then no then yes: one managed block only" equals "$(count_in_file "$FIX/sshd_config" '# ezvps:managed PasswordAuthentication')" 1
check "password auth yes: only one active PasswordAuthentication line" equals "$(grep -c '^PasswordAuthentication' "$FIX/sshd_config")" 1
check "password auth: the commented default lines are kept as comments" file_has "$FIX/sshd_config" "#PasswordAuthentication yes"
ssh_new
cp -p "$FIX/sshd_config" "$FIX/sshd_config.orig"
run_ssh "4\n3\n1\nn\n0\n"
check "password auth no with no keys anywhere: a stronger warning" contains "$OUT" "No account has an authorized_keys file yet"
check "password auth no with no keys: declining the extra question changes nothing" same_file "$FIX/sshd_config" "$FIX/sshd_config.orig"
check "password auth no with no keys: no restart" log_lacks "systemctl restart"
ssh_new
run_ssh "4\n3\n1\ny\nn\n0\n"
check "password auth no with no keys: the final question can still decline" file_lacks "$FIX/sshd_config" "PasswordAuthentication no"
ssh_new
printf 'KbdInteractiveAuthentication yes\n' >"$FIX/sshd_config.d/10-kbd.conf"
mkdir -p "$FIX/home/testadmin/.ssh"
printf '%s\n' "$SSH_KEY_LINE" >"$FIX/home/testadmin/.ssh/authorized_keys"
run_ssh "4\n3\n1\ny\n0\n"
check "password auth no: warns when keyboard-interactive can still ask for a password" contains "$OUT" "KbdInteractiveAuthentication is enabled"
# Match block
ssh_new
printf 'Match User testuser\n    PasswordAuthentication yes\n' >>"$FIX/sshd_config"
mkdir -p "$FIX/home/testadmin/.ssh"
printf '%s\n' "$SSH_KEY_LINE" >"$FIX/home/testadmin/.ssh/authorized_keys"
run_ssh "4\n3\n1\ny\n0\n"
check "Match block that also sets the keyword: warned about" contains "$OUT" "A Match block in"
check "Match block lines are left exactly as they were" file_has "$FIX/sshd_config" "    PasswordAuthentication yes"
check "Match block line is not commented out" file_lacks "$FIX/sshd_config" "ezvps disabled:     PasswordAuthentication yes"
# prerequisites
ssh_new
OUT="$(printf '4\n1\n2222\ny\n0\n' | PATH="$SSHBIN_NOSSHD" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
check "no sshd: a clear message, nothing changed" contains "$OUT" "sshd is not installed"
check "no sshd: ezvps does not install it" log_lacks "apt-get"
check "no sshd: no backup" equals "$(nfiles "$FIX/backup" '*')" 0
ssh_new
rm -f "$FIX/sshd_config"
run_ssh "4\n1\n2222\ny\n0\n"
check "missing sshd_config: a clear message" contains "$OUT" "Cannot read"
ssh_new
OUT="$(printf '4\n1\n2222\ny\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/ubuntu2510" PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
check "settings change: unsupported system is refused before any prompt" contains "$OUT" "SSH and Users needs a supported system"
check "settings change: unsupported system changes nothing" equals "$(nfiles "$FIX/backup" '*')-$(grep -c restart "$FAKE_LOG")" "0-0"
for f in debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604; do
    ssh_new
    OUT="$(printf '4\n2\n1\ny\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/$f" PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
    check "settings change works on ${f}" file_has "$FIX/sshd_config" "PermitRootLogin no"
done

# --- Add SSH key ---------------------------------------------------------------------------------
echo "-- SSH and Users: add SSH key"
ssh_new
run_ssh "5\ntestuser\n${SSH_KEY_LINE}\ny\n0\n"
AK="$FIX/home/testuser/.ssh/authorized_keys"
check "key: a new authorized_keys is created" test -f "$AK"
check "key: the key line is in it exactly once" equals "$(count_in_file "$AK" "$SSH_BLOB_ED")" 1
check "key: authorized_keys is mode 600" equals "$(stat -c %a "$AK")" 600
check "key: .ssh is mode 700" equals "$(stat -c %a "$FIX/home/testuser/.ssh")" 700
check "key: ownership is set to the user's uid:gid on .ssh and authorized_keys" log_has "chown 2002:2002 $FIX/home/testuser/.ssh $AK"
check "key: reports the user and file" contains "$OUT" "Key added for testuser: ${AK}"
check "key: the key data is never printed" not_contains "$OUT" "$SSH_BLOB_ED"
check "key: shows only the type and comment" contains "$OUT" "type    : ssh-ed25519"
check "key: shows the comment" contains "$OUT" "comment : testuser@example.com"
check "key: a new file needs no backup" equals "$(nfiles "$FIX/backup" '*')" 0
check "key: no temp file left in .ssh" equals "$(nfiles "$FIX/home/testuser/.ssh" '.ezvps-ak.*')" 0
check "key: advises testing before disabling passwords" contains "$OUT" "Test a key login in a second terminal"
# append, no trailing newline in the old file, dir with loose modes
ssh_new
mkdir -p "$FIX/home/testuser/.ssh"
chmod 755 "$FIX/home/testuser/.ssh"
printf '%s' "$SSH_KEY_LINE2" >"$FIX/home/testuser/.ssh/authorized_keys"
chmod 644 "$FIX/home/testuser/.ssh/authorized_keys"
cp -p "$FIX/home/testuser/.ssh/authorized_keys" "$FIX/ak.orig"
run_ssh "5\ntestuser\n${SSH_KEY_LINE}\ny\n0\n"
AK="$FIX/home/testuser/.ssh/authorized_keys"
check "append: the old key is still there" file_has "$AK" "$SSH_BLOB_ED2"
check "append: the new key was appended" file_has "$AK" "$SSH_BLOB_ED"
check "append: two lines (a missing final newline did not glue them)" equals "$(grep -c '' "$AK")" 2
check "append: first line is the old key unchanged" equals "$(head -1 "$AK")" "$SSH_KEY_LINE2"
check "append: modes are corrected to 600 / 700" equals "$(stat -c %a "$AK")-$(stat -c %a "$FIX/home/testuser/.ssh")" "600-700"
check "append: the old file was backed up" equals "$(nfiles "$FIX/backup" 'authorized_keys-testuser.*')" 1
check "append: the backup is a byte-for-byte copy" same_file "$(printf '%s' "$FIX"/backup/authorized_keys-testuser.*)" "$FIX/ak.orig"
n_before="$(nfiles "$FIX/backup" '*')"
run_ssh "5\ntestuser\n${SSH_KEY_LINE}\ny\n0\n"
check "duplicate: the same key is not added twice" contains "$OUT" "already in"
check "duplicate: still two lines" equals "$(grep -c '' "$AK")" 2
check "duplicate: no new backup" equals "$(nfiles "$FIX/backup" '*')" "$n_before"
# declined
ssh_new
run_ssh "5\ntestuser\n${SSH_KEY_LINE}\nn\n0\n"
check "key: declining creates nothing" test ! -e "$FIX/home/testuser/.ssh"
# private key refused (the header is assembled at run time; the "body" lines of a paste arrive as later prompts)
ssh_new
run_ssh "5\ntestuser\n${SSH_PRIV_HDR}\n0\n"
check "private key: refused" contains "$OUT" "looks like a PRIVATE key"
check "private key: nothing is written" test ! -e "$FIX/home/testuser/.ssh"
check "private key: the header is never echoed back" not_contains "$OUT" "BEGIN OPENSSH"
check "private key: no chown, no backup" equals "$(grep -c chown "$FAKE_LOG")-$(nfiles "$FIX/backup" '*')" "0-0"
run_ssh "5\ntestuser\nssh-rsa ${SSH_BLOB_RSA} PRIVATE KEY\n0\n"
check "private key: the words PRIVATE KEY in a pasted line are refused too" contains "$OUT" "looks like a PRIVATE key"
run_ssh "5\ntestuser\nPuTTY-User-Key-File-3: ssh-ed25519\n0\n"
check "private key: a PuTTY private key file is refused" contains "$OUT" "looks like a PRIVATE key"
check "private key: nothing created for PuTTY keys either" test ! -e "$FIX/home/testuser/.ssh"
# invalid public keys
for bad in "hello world" "ssh-ed25519" "ssh-ed25519 notbase64!!!! c" "ssh-foo ${SSH_BLOB_ED} c" "ssh-rsa ${SSH_BLOB_ED} c" "ssh-ed25519 ${SSH_BLOB_RSA} c" "command=\"/bin/true\" ssh-ed25519 ${SSH_BLOB_ED} c" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAA c" "-----BEGIN PUBLIC KEY-----" "ssh-ed25519 ${SSH_BLOB_ED}x c"; do
    run_ssh "5\ntestuser\n${bad}\n0\n"
    check "invalid key refused: '${bad:0:40}'" test -n "$(printf '%s\n' "$OUT" | grep -E 'does not look like an OpenSSH public key|not valid for type|PRIVATE key')"
    check "invalid key '${bad:0:40}': authorized_keys not created" test ! -e "$FIX/home/testuser/.ssh"
done
for t in ecdsa-sha2-nistp256 ecdsa-sha2-nistp384 ecdsa-sha2-nistp521; do
    case "$t" in
        ecdsa-sha2-nistp256) pre="AAAAE2VjZHNhLXNoYTItbmlzdHAy" ;;
        ecdsa-sha2-nistp384) pre="AAAAE2VjZHNhLXNoYTItbmlzdHAz" ;;
        *) pre="AAAAE2VjZHNhLXNoYTItbmlzdHA1" ;;
    esac
    ssh_new
    run_ssh "5\ntestuser\n${t} ${pre}$(printf 'FAKE%.0s' {1..10}) c\ny\n0\n"
    check "key type ${t} is accepted" test -s "$FIX/home/testuser/.ssh/authorized_keys"
done
ssh_new
run_ssh "5\ntestuser\nssh-rsa ${SSH_BLOB_RSA}\ny\n0\n"
check "key type ssh-rsa (no comment) is accepted" test -s "$FIX/home/testuser/.ssh/authorized_keys"
run_ssh "5\ntestuser\n-----BEGIN PUBLIC"" KEY-----\n0\n"
check "key: a PEM public key is refused as not an OpenSSH key, not mislabelled as a private key" equals "$(contains "$OUT" "does not look like an OpenSSH public key" && ! contains "$OUT" "PRIVATE key" && echo ok)" ok
run_ssh "5\ntestuser\n\n0\n"
check "key: an empty key cancels" contains "$OUT" "Cancelled. Nothing was changed."
# bad users / paths
ssh_new
run_ssh "5\nnosuchuser\n${SSH_KEY_LINE}\ny\n0\n"
check "key: unknown user is refused" contains "$OUT" "User 'nosuchuser' does not exist"
run_ssh "5\nBad Name\n0\n"
check "key: invalid username is refused" contains "$OUT" "Invalid username"
run_ssh "5\ntestnohome\n${SSH_KEY_LINE}\ny\n0\n"
check "key: a user whose home directory is missing is refused (it is not created)" contains "$OUT" "is not an existing absolute directory"
check "key: missing home is not created" test ! -e "$FIX/home/testnohome"
rm -rf "$FIX/home/testuser/.ssh"
mkdir -p "$FIX/elsewhere"
ln -s "$FIX/elsewhere" "$FIX/home/testuser/.ssh"
run_ssh "5\ntestuser\n${SSH_KEY_LINE}\ny\n0\n"
check "key: a symlinked .ssh is refused" contains "$OUT" "symbolic link"
check "key: nothing written through the symlink" equals "$(nfiles "$FIX/elsewhere" '*')" 0
rm -f "$FIX/home/testuser/.ssh"
mkdir -p "$FIX/home/testuser/.ssh"
ln -s "$FIX/elsewhere/target" "$FIX/home/testuser/.ssh/authorized_keys"
run_ssh "5\ntestuser\n${SSH_KEY_LINE}\ny\n0\n"
check "key: a symlinked authorized_keys is refused" contains "$OUT" "symbolic link"
check "key: nothing written through the authorized_keys symlink" test ! -e "$FIX/elsewhere/target"
ssh_new
FAKE_CHOWN_RC=1 run_ssh "5\ntestuser\n${SSH_KEY_LINE}\ny\n0\n"
check "key: a failing chown is reported, not hidden" contains "$OUT" "Could not set up"
check "key: a failing chown does not claim success" not_contains "$OUT" "Key added for"
ssh_new
run_ssh "5\nroot\n${SSH_KEY_LINE}\ny\n0\n"
check "key: root can receive a key (its own home directory)" test -s "$FIX/root/.ssh/authorized_keys"
check "key: root's authorized_keys is owned by uid 0" log_has "chown 0:0 $FIX/root/.ssh $FIX/root/.ssh/authorized_keys"
ssh_new
OUT="$(printf '5\ntestuser\n%s\ny\n0\n' "$SSH_KEY_LINE" | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/ubuntu2510" PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
check "key: unsupported system is refused before any prompt" contains "$OUT" "SSH and Users needs a supported system"
check "key: unsupported system writes nothing" test ! -e "$FIX/home/testuser/.ssh"
for f in debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604; do
    ssh_new
    OUT="$(printf '5\ntestuser\n%s\ny\n0\n' "$SSH_KEY_LINE" | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$OSD/$f" PATH="$SSHBIN" "$BASH_BIN" "$EZVPS" ssh 2>&1)"
    check "key works on ${f}" test -s "$FIX/home/testuser/.ssh/authorized_keys"
done

# --- source rules for the module -------------------------------------------------------------------
ssh_body() { awk '/^(usr_|ssh_|module_ssh)[a-z_]*\(\) \{/ {on=1} on {print} /^}/ {on=0}' "$EZVPS"; }
ssh_code() { ssh_body | grep -vE '^[[:space:]]*#'; }
check "the module never reads /etc/shadow" not_contains "$(ssh_code)" "shadow"
check "the module has no curl/wget" not_contains "$(ssh_code)" "curl"
check "the module has no wget" not_contains "$(ssh_code)" "wget"
check "the module never removes a home directory itself (only userdel -r does)" not_contains "$(ssh_code | grep -E 'rm[[:space:]]+-[a-z]*r')" "rm"
check "the only password handling is the system's own passwd prompt" equals "$(ssh_code | grep -cE '^[[:space:]]*(if |! )?passwd[[:space:]]')" 1
check "no password is read by the module (no read -s except the public key prompt)" equals "$(ssh_code | grep -cE 'read[^|]* -s')" 2
check "passwd is only ever run as 'passwd -- <name>'" contains "$(ssh_code | grep -E '^[[:space:]]*(if |! )?passwd[[:space:]]')" 'passwd -- "$name"'
check "the module uses no tool outside coreutils, bash and its listed commands" equals "$(ssh_code | grep -cE '(^|[[:space:]|(])(sed|awk|grep|perl|python3?|tee|ssh-keygen)[[:space:]]')" 0
check "the module's functions are prefixed usr_ / ssh_" equals "$(grep -cE '^(usr|ssh)_[a-z_]+\(\) \{' "$EZVPS")" "$(ssh_body | grep -cE '^(usr|ssh)_[a-z_]+\(\) \{')"

export EZVPS_NO_PAUSE="${SSH_SAVED_PAUSE:-0}"
[[ -z "$SSH_SAVED_PAUSE" ]] && unset EZVPS_NO_PAUSE
unset EZVPS_PASSWD_FILE EZVPS_GROUP_FILE EZVPS_SHELLS_FILE EZVPS_PROC_DIR EZVPS_HOME_BASE EZVPS_SSHD_CONFIG EZVPS_SSH_WAIT_SECONDS \
    FAKE_LOG FAKE_LISTEN FAKE_BUSY FAKE_SSHD SUDO_USER SSH_CONNECTION
if [[ -n "${LC_SAVED_BACKUP-}" ]]; then export EZVPS_BACKUP_DIR="$LC_SAVED_BACKUP"; else unset EZVPS_BACKUP_DIR; fi

echo "== Firewall module (fake ufw/firewall-cmd/nft/iptables/ss/sshd with file-backed state, no real firewall)"

FWW="$WORK/fw"
FW_STUBS="$FWW/stubs"
mkdir -p "$FW_STUBS"
FW_SAVED_PAUSE="${EZVPS_NO_PAUSE-}"
export EZVPS_NO_PAUSE=1

# --- fake ufw: rules live in $FW_STATE_DIR/ufw.rules as "TO|ACTION|FROM"; active when ufw.active exists --------------
mkstub "$FW_STUBS/ufw" <<'EOF'
echo "ufw $*" >>"$FW_LOG"
D="$FW_STATE_DIR"
rules=()
[[ -f "$D/ufw.rules" ]] && mapfile -t rules <"$D/ufw.rules"
save() { if ((${#rules[@]})); then printf '%s\n' "${rules[@]}" >"$D/ufw.rules"; else : >"$D/ufw.rules"; fi; }
active=0
[[ -f "$D/ufw.active" ]] && active=1
case "$1 ${2:-}" in
    "status verbose")
        if ((active)); then
            echo "Status: active"
            echo "Logging: on (low)"
            echo "Default: deny (incoming), allow (outgoing), disabled (routed)"
            echo "New profiles: skip"
        else
            echo "Status: inactive"
        fi
        ;;
    "status numbered")
        c=0
        [[ -f "$D/ufw.numbered" ]] && read -r c <"$D/ufw.numbered"
        c=$((c + 1))
        echo "$c" >"$D/ufw.numbered"
        # a concurrent change between the listing and the removal: the first rule disappears
        if [[ "${FAKE_UFW_SHIFT:-0}" == 1 && "$c" == 2 && ${#rules[@]} -gt 0 ]]; then
            rules=("${rules[@]:1}")
            save
        fi
        if ((active)); then
            echo "Status: active"
            echo
            printf '     %-26s  %-10s  %s\n' To Action From
            printf '     %-26s  %-10s  %s\n' -- ------ ----
            n=0
            for r in "${rules[@]}"; do
                n=$((n + 1))
                IFS='|' read -r to act from <<<"$r"
                printf '[%2d] %-26s  %-10s  %s\n' "$n" "$to" "$act" "$from"
            done
        else
            echo "Status: inactive"
        fi
        ;;
    "allow "*)
        if [[ "${FAKE_UFW_ADD_FAIL:-0}" == 1 ]]; then echo "ERROR: Could not update running firewall" >&2; exit 1; fi
        if [[ "${FAKE_UFW_ADD_NOOP:-0}" != 1 ]]; then
            rules+=("$2|ALLOW IN|Anywhere" "$2 (v6)|ALLOW IN|Anywhere (v6)")
            save
        fi
        echo "Rule added"
        echo "Rule added (v6)"
        ;;
    "--force delete")
        n="$3"
        if [[ "${FAKE_UFW_DEL_FAIL:-0}" == 1 ]]; then echo "ERROR: Could not delete rule" >&2; exit 1; fi
        if ! [[ "$n" =~ ^[0-9]+$ ]] || ((n < 1 || n > ${#rules[@]})); then echo "ERROR: Could not find rule '$n'" >&2; exit 1; fi
        if [[ "${FAKE_UFW_DEL_NOOP:-0}" != 1 ]]; then
            unset "rules[$((n - 1))]"
            rules=("${rules[@]}")
            save
        fi
        echo "Rule deleted"
        ;;
    "app list")
        printf 'Available applications:\n  Nginx Full\n  OpenSSH\n'
        ;;
    "app info")
        case "$3" in
            "Nginx Full") printf 'Profile: Nginx Full\nTitle: Web Server (Nginx, HTTP + HTTPS)\nDescription: Small, but very powerful web server\n\nPorts:\n  80,443/tcp\n' ;;
            OpenSSH) [[ "${FAKE_UFW_APPINFO_FAIL:-0}" == 1 ]] && { echo "ERROR: Could not find profile '$3'" >&2; exit 1; }
                printf 'Profile: OpenSSH\nTitle: Secure shell server, an rshd replacement\nDescription: OpenSSH is a free implementation\n\nPort:\n  22/tcp\n' ;;
            *) echo "ERROR: Could not find profile '$3'" >&2; exit 1 ;;
        esac
        ;;
    *)
        echo "ERROR: unexpected arguments: $*" >&2
        exit 1
        ;;
esac
exit 0
EOF

# --- fake firewall-cmd: runtime and permanent config per zone, plain files --------------------------------------------
mkstub "$FW_STUBS/firewall-cmd" <<'EOF'
echo "firewall-cmd $*" >>"$FW_LOG"
D="$FW_STATE_DIR/fwd"
perm=0 zone="" act=""
for a in "$@"; do
    case "$a" in
        --permanent) perm=1 ;;
        --zone=*) zone="${a#--zone=}" ;;
        *) act="$a" ;;
    esac
done
sfx=""
((perm)) && sfx=".perm"
readf() { lines=(); [[ -f "$1" ]] && mapfile -t lines <"$1"; }
writef() { local f="$1"; shift; if (($#)); then printf '%s\n' "$@" >"$f"; else : >"$f"; fi; }
modify() { # modify <file> <add|remove> <value>
    local f="$D/$zone.$1$sfx" v="$3" x out=() found=0
    if [[ "${FAKE_FWD_PERM_FAIL:-0}" == 1 && $perm == 1 ]]; then echo "Error: could not write the permanent configuration" >&2; exit 1; fi
    readf "$f"
    for x in "${lines[@]}"; do
        if [[ "$x" == "$v" ]]; then found=1; [[ "$2" == remove ]] && continue; fi
        out+=("$x")
    done
    if [[ "$2" == add ]]; then
        ((found)) && { echo "Warning: ALREADY_ENABLED: $v"; exit 0; }
        out+=("$v")
    else
        ((found)) || { echo "Warning: NOT_ENABLED: $v"; exit 0; }
    fi
    writef "$f" "${out[@]}"
    echo success
}
case "$act" in
    --state)
        if [[ -f "$D/running" ]]; then echo running; exit 0; fi
        echo "not running" >&2
        exit 252
        ;;
    --get-default-zone) [[ -f "$D/running" ]] || exit 252; cat_zone=""; read -r cat_zone <"$D/default"; echo "$cat_zone" ;;
    --get-active-zones)
        readf "$D/zones"
        for z in "${lines[@]}"; do printf '%s\n  interfaces: eth0\n' "$z"; done
        ;;
    --list-ports) readf "$D/$zone.ports$sfx"; echo "${lines[*]}" ;;
    --list-services) readf "$D/$zone.services$sfx"; echo "${lines[*]}" ;;
    --list-rich-rules) readf "$D/$zone.rich$sfx"; for l in "${lines[@]}"; do echo "$l"; done ;;
    --list-sources) readf "$D/$zone.sources"; echo "${lines[*]}" ;;
    --list-all) printf '%s (default, active)\n  target: default\n  icmp-block-inversion: no\n' "$zone" ;;
    --info-service=*)
        svc="${act#--info-service=}"
        case "$svc" in
            ssh) p="22/tcp" ;;
            http) p="80/tcp" ;;
            https) p="443/tcp" ;;
            dhcpv6-client) p="" ;;
            *) echo "Error: INVALID_SERVICE: $svc" >&2; exit 101 ;;
        esac
        printf '%s\n  ports: %s\n  protocols: \n  source-ports: \n  modules: \n  destination: \n  includes: \n  helpers: \n' "$svc" "$p"
        ;;
    --add-port=*) modify ports add "${act#--add-port=}" ;;
    --remove-port=*) modify ports remove "${act#--remove-port=}" ;;
    --remove-service=*) modify services remove "${act#--remove-service=}" ;;
    --remove-rich-rule=*) modify rich remove "${act#--remove-rich-rule=}" ;;
    *) echo "Error: unexpected arguments: $*" >&2; exit 2 ;;
esac
exit 0
EOF

# --- fake nft: chains and rules in two files; `nft -a list ruleset` renders them like the real tool ------------------
mkstub "$FW_STUBS/nft" <<'EOF'
echo "nft $*" >>"$FW_LOG"
D="$FW_STATE_DIR"
chains=() rules=()
[[ -f "$D/nft.chains" ]] && mapfile -t chains <"$D/nft.chains"
[[ -f "$D/nft.rules" ]] && mapfile -t rules <"$D/nft.rules"
if [[ "${FAKE_NFT_FAIL:-0}" == 1 ]]; then echo "Error: Operation not permitted" >&2; exit 1; fi
saver() { if ((${#rules[@]})); then printf '%s\n' "${rules[@]}" >"$D/nft.rules"; else : >"$D/nft.rules"; fi; }
if [[ "$1 $2 $3" == "-a list ruleset" ]]; then
    seen="" first=1
    for c in "${chains[@]}"; do
        IFS='|' read -r fam tbl chain spec <<<"$c"
        [[ " $seen " == *" $fam/$tbl "* ]] && continue
        seen+=" $fam/$tbl"
        printf 'table %s %s { # handle 1\n' "$fam" "$tbl"
        if ((first)); then
            printf '\tset blocklist { # handle 2\n\t\ttype ipv4_addr\n\t\telements = { 192.0.2.66 }\n\t}\n\n'
            first=0
        fi
        for c2 in "${chains[@]}"; do
            IFS='|' read -r f2 t2 c2n spec2 <<<"$c2"
            [[ "$f2/$t2" == "$fam/$tbl" ]] || continue
            printf '\tchain %s { # handle 3\n' "$c2n"
            [[ -n "$spec2" ]] && printf '\t\t%s\n' "$spec2"
            for r in "${rules[@]}"; do
                IFS='|' read -r rf rt rc rh rtxt <<<"$r"
                [[ "$rf/$rt/$rc" == "$f2/$t2/$c2n" ]] && printf '\t\t%s # handle %s\n' "$rtxt" "$rh"
            done
            printf '\t}\n'
        done
        printf '}\n'
    done
    exit 0
fi
if [[ "$1 $2" == "insert rule" ]]; then
    fam="$3" tbl="$4" chain="$5"
    shift 5
    next=100
    [[ -f "$D/nft.next" ]] && read -r next <"$D/nft.next"
    echo $((next + 1)) >"$D/nft.next"
    [[ "${FAKE_NFT_ADD_NOOP:-0}" == 1 ]] && exit 0
    rules=("$fam|$tbl|$chain|$next|$*" "${rules[@]}")
    saver
    exit 0
fi
if [[ "$1 $2" == "delete rule" && "$6" == handle ]]; then
    fam="$3" tbl="$4" chain="$5" h="$7"
    out=() found=0
    for r in "${rules[@]}"; do
        IFS='|' read -r rf rt rc rh rtxt <<<"$r"
        if [[ "$rf/$rt/$rc" == "$fam/$tbl/$chain" && "$rh" == "$h" ]]; then found=1; continue; fi
        out+=("$r")
    done
    ((found)) || { echo "Error: No such file or directory" >&2; exit 1; }
    rules=("${out[@]}")
    saver
    exit 0
fi
echo "Error: unexpected arguments: $*" >&2
exit 1
EOF

# --- fake iptables: the INPUT chain only; the real tool normalises -p tcp --dport to -p tcp -m tcp --dport -----------
mkstub "$FW_STUBS/iptables" <<'EOF'
echo "iptables $*" >>"$FW_LOG"
D="$FW_STATE_DIR"
rules=()
[[ -f "$D/ipt.rules" ]] && mapfile -t rules <"$D/ipt.rules"
pol=ACCEPT
[[ -f "$D/ipt.policy" ]] && read -r pol <"$D/ipt.policy"
if [[ "${FAKE_IPT_FAIL:-0}" == 1 ]]; then echo "iptables: Permission denied (you must be root)." >&2; exit 4; fi
[[ "${1:-}" == -w ]] && shift
savei() { if ((${#rules[@]})); then printf '%s\n' "${rules[@]}" >"$D/ipt.rules"; else : >"$D/ipt.rules"; fi; }
case "$1 ${2:-}" in
    "-S INPUT")
        echo "-P INPUT $pol"
        for r in "${rules[@]}"; do echo "-A INPUT $r"; done
        ;;
    "-I INPUT")
        shift 3 # -I INPUT 1
        [[ "${FAKE_IPT_ADD_NOOP:-0}" == 1 ]] && exit 0
        spec="$*"
        spec="${spec/-p tcp --dport/-p tcp -m tcp --dport}"
        spec="${spec/-p udp --dport/-p udp -m udp --dport}"
        rules=("$spec" "${rules[@]}")
        savei
        ;;
    "-D INPUT")
        n="$3"
        if [[ "${FAKE_UFW_DEL_FAIL:-0}" == 1 ]]; then echo "ERROR: Could not delete rule" >&2; exit 1; fi
        if ! [[ "$n" =~ ^[0-9]+$ ]] || ((n < 1 || n > ${#rules[@]})); then echo "iptables: Index of deletion too big." >&2; exit 1; fi
        unset "rules[$((n - 1))]"
        rules=("${rules[@]}")
        savei
        ;;
    *)
        echo "iptables: unexpected arguments: $*" >&2
        exit 2
        ;;
esac
exit 0
EOF

# --- fake ss and sshd -------------------------------------------------------------------------------------------------------
mkstub "$FW_STUBS/ss" <<'EOF'
echo "ss $*" >>"$FW_LOG"
port="${!#}"
port="${port##*:}"
port="${port%% *}"
port="${port%)}"
want=tcp
for a in "$@"; do [[ "$a" == -lunp ]] && want=udp; done
[[ -f "$FW_LISTEN" ]] || exit 0
while read -r proto p proc addr; do
    [[ "$proto" == "$want" && "$p" == "$port" ]] || continue
    if [[ "$want" == tcp ]]; then state=LISTEN; else state=UNCONN; fi
    echo "$state 0 128 $addr:$p 0.0.0.0:* users:((\"$proc\",pid=7,fd=3))"
done <"$FW_LISTEN"
exit 0
EOF
mkstub "$FW_STUBS/sshd" <<'EOF'
echo "sshd $*" >>"$FW_LOG"
for p in ${FW_SSHD_PORTS:-22}; do echo "port $p"; done
echo "permitrootlogin prohibit-password"
echo "passwordauthentication yes"
exit 0
EOF

# sandbox PATH: coreutils the module needs + the chosen stubs
mk_fw_bin() { # mk_fw_bin <dir> <stub names...>
    local dir="$1" c s
    shift
    rm -rf "$dir"
    mkdir -p "$dir"
    for c in bash mkdir chmod date; do ln -sf "$(command -v "$c")" "$dir/$c"; done
    for s in "$@"; do ln -sf "$FW_STUBS/$s" "$dir/$s"; done
}
FWBIN_ALL="$FWW/bin-all"
FWBIN_NOUFW="$FWW/bin-noufw"
FWBIN_FWD="$FWW/bin-fwd" # firewalld + nft + iptables
FWBIN_NFT="$FWW/bin-nft" # nft + iptables
FWBIN_IPT="$FWW/bin-ipt"
FWBIN_NONE="$FWW/bin-none"
FWBIN_UFW="$FWW/bin-ufw"
FWBIN_NFT1="$FWW/bin-nft1"
FWBIN_FWD1="$FWW/bin-fwd1"
FWBIN_IPT1="$FWW/bin-ipt1"
FWBIN_UFW_NOSS="$FWW/bin-ufw-noss"
FWBIN_UFW_NOSSHD="$FWW/bin-ufw-nosshd"
mk_fw_bin "$FWBIN_ALL" ufw firewall-cmd nft iptables ss sshd
mk_fw_bin "$FWBIN_NOUFW" firewall-cmd nft iptables ss sshd
mk_fw_bin "$FWBIN_FWD" firewall-cmd nft iptables ss sshd
mk_fw_bin "$FWBIN_NFT" nft iptables ss sshd
mk_fw_bin "$FWBIN_IPT" iptables ss sshd
mk_fw_bin "$FWBIN_NONE" ss sshd
mk_fw_bin "$FWBIN_UFW" ufw ss sshd
mk_fw_bin "$FWBIN_NFT1" nft ss sshd
mk_fw_bin "$FWBIN_FWD1" firewall-cmd ss sshd
mk_fw_bin "$FWBIN_IPT1" iptables ss sshd
mk_fw_bin "$FWBIN_UFW_NOSS" ufw sshd
mk_fw_bin "$FWBIN_UFW_NOSSHD" ufw ss

# --- fixtures ----------------------------------------------------------------------------------------------------------------------
FW_N=0
FW_ENV=()
fw_new() { # a fresh fake system; exports what the stubs and the module read
    FW_N=$((FW_N + 1))
    FWX="$FWW/s$FW_N"
    rm -rf "$FWX"
    mkdir -p "$FWX/state/fwd" "$FWX/backup"
    export FW_STATE_DIR="$FWX/state" FW_LOG="$FWX/log" FW_LISTEN="$FWX/listen" EZVPS_BACKUP_DIR="$FWX/backup"
    export EZVPS_SSHD_CONFIG="$FWX/sshd_config" FW_SSHD_PORTS=22
    : >"$FW_LOG"
    : >"$FW_LISTEN"
    : >"$EZVPS_SSHD_CONFIG"
    FW_ENV=()
    unset SSH_CONNECTION FAKE_UFW_SHIFT FAKE_UFW_DEL_NOOP FAKE_UFW_DEL_FAIL FAKE_UFW_APPINFO_FAIL FAKE_UFW_ADD_FAIL FAKE_UFW_ADD_NOOP FAKE_FWD_PERM_FAIL FAKE_NFT_FAIL FAKE_NFT_ADD_NOOP FAKE_IPT_FAIL FAKE_IPT_ADD_NOOP
}
fw_ufw_fixture() {
    printf '%s\n' '22/tcp|ALLOW IN|Anywhere' '80/tcp|ALLOW IN|Anywhere' '6000:6010/tcp|ALLOW IN|Anywhere' \
        'Nginx Full|ALLOW IN|Anywhere' '7000/tcp|DENY IN|Anywhere' '9090/tcp|ALLOW IN|192.0.2.0/24' \
        '22/tcp (v6)|ALLOW IN|Anywhere (v6)' '53|ALLOW IN|198.51.100.7' >"$FW_STATE_DIR/ufw.rules"
    : >"$FW_STATE_DIR/ufw.active"
}
fw_fwd_fixture() {
    local D="$FW_STATE_DIR/fwd"
    : >"$D/running"
    echo public >"$D/default"
    printf '%s\n' public internal >"$D/zones"
    printf '%s\n' 8080/tcp 5000-5010/udp >"$D/public.ports"
    cp "$D/public.ports" "$D/public.ports.perm"
    printf '%s\n' ssh http >"$D/public.services"
    cp "$D/public.services" "$D/public.services.perm"
    printf '%s\n' 'rule family="ipv4" source address="192.0.2.0/24" port port="9443" protocol="tcp" accept' >"$D/public.rich"
    cp "$D/public.rich" "$D/public.rich.perm"
    printf '%s\n' 3000/tcp >"$D/internal.ports"
    cp "$D/internal.ports" "$D/internal.ports.perm"
    printf '%s\n' 198.51.100.0/24 >"$D/internal.sources"
}
fw_nft_fixture() {
    printf '%s\n' 'inet|filter|input|type filter hook input priority filter; policy drop;' \
        'inet|filter|forward|type filter hook forward priority filter; policy drop;' >"$FW_STATE_DIR/nft.chains"
    printf '%s\n' 'inet|filter|input|4|ct state established,related accept' \
        'inet|filter|input|5|tcp dport 22 accept' \
        'inet|filter|input|6|ip saddr 192.0.2.0/24 tcp dport { 80, 443 } accept' \
        'inet|filter|input|7|udp dport 5000-5010 counter packets 3 bytes 180 accept' \
        'inet|filter|input|8|tcp dport 7000 drop' \
        'inet|filter|input|9|iif "lo" accept' \
        'inet|filter|forward|20|tcp dport 22 accept' >"$FW_STATE_DIR/nft.rules"
}
fw_ipt_fixture() {
    echo DROP >"$FW_STATE_DIR/ipt.policy"
    printf '%s\n' '-i lo -j ACCEPT' \
        '-p tcp -m tcp --dport 22 -j ACCEPT' \
        '-p tcp -m multiport --dports 80,443 -j ACCEPT' \
        '-s 192.0.2.0/24 -p tcp -m tcp --dport 9090 -j ACCEPT' \
        '-p udp -m udp --dport 6000:6010 -j ACCEPT' \
        '-p tcp -m tcp --dport 7000 -j DROP' \
        '-m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT' >"$FW_STATE_DIR/ipt.rules"
}
run_fw() { # run_fw <path-dir> <stdin> [ezvps args]; the environment comes from the caller (FW_ENV adds variables)
    local pathdir="$1" input="$2"
    shift 2
    OUT="$(printf '%b' "$input" | env "${FW_ENV[@]}" PATH="$pathdir" "$BASH_BIN" "$EZVPS" "${@:-firewall}" 2>&1)"
    RC=$?
}
flog_has() { grep -qF -- "$1" "$FW_LOG"; }
flog_lacks() { ! grep -qF -- "$1" "$FW_LOG"; }
flog_count() { grep -cF -- "$1" "$FW_LOG"; }
# rows of the rule table: the five parsed columns (the backend's own text follows)
fw_rowp() { printf '%-6s %-9s %-6s %-22s %-20s ' "$@"; }
# a appears before b in the text
before_in() { local x="${1%%"$2"*}" y="${1%%"$3"*}"; [[ "$1" == *"$2"* && "$1" == *"$3"* ]] && ((${#x} < ${#y})); }
backup_listings() { local f n=0; for f in "$EZVPS_BACKUP_DIR"/firewall-"$1".*; do [[ -f "$f" ]] && n=$((n + 1)); done; printf '%d' "$n"; }
first_backup() { local f; for f in "$EZVPS_BACKUP_DIR"/firewall-"$1".*; do [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }; done; return 1; }
file_mode() { # prints the octal mode of a file (GNU stat), empty if unknown
    stat -c '%a' "$1" 2>/dev/null
}

flog_after() { # flog_after <first> <second>: both logged, the first before the second
    local a b
    a="$(grep -nF -- "$1" "$FW_LOG" | head -1 | cut -d: -f1)" b="$(grep -nF -- "$2" "$FW_LOG" | tail -1 | cut -d: -f1)"
    [[ -n "$a" && -n "$b" ]] && ((a < b))
}
only_reads() { # every logged backend call is a read (status / list / app / ss / sshd)
    local l
    while IFS= read -r l; do
        case "$l" in
            "ufw status"* | "ufw app "* | "ss "* | "sshd "* | "firewall-cmd --state" | "firewall-cmd --get-"* | "firewall-cmd --zone="*" --list-"* | "firewall-cmd --info-service="* | "nft -a list ruleset" | "iptables -w -S INPUT") ;;
            *) echo "write or unexpected call: $l" >&2; return 1 ;;
        esac
    done <"$FW_LOG"
}

echo "-- Firewall: backend detection (ufw, firewalld, nftables, iptables, in this order)"
fw_new
fw_ufw_fixture
fw_fwd_fixture
fw_nft_fixture
fw_ipt_fixture
run_fw "$FWBIN_ALL" "1\n0\n"
check "all four present: ufw is chosen" contains "$OUT" "Firewall backend: ufw (command: ufw)"
check "the submenu names the backend" contains "$OUT" "Backend: ufw"
check "ufw chosen: no firewall-cmd, nft or iptables call" bash -c '! grep -qE "^(firewall-cmd|nft|iptables)" "$1"' _ "$FW_LOG"
fw_new
fw_fwd_fixture
fw_nft_fixture
fw_ipt_fixture
run_fw "$FWBIN_NOUFW" "1\n0\n"
check "no ufw: firewalld is chosen" contains "$OUT" "Firewall backend: firewalld (command: firewall-cmd)"
check "firewalld chosen: no nft or iptables call" bash -c '! grep -qE "^(nft|iptables|ufw)" "$1"' _ "$FW_LOG"
fw_new
fw_nft_fixture
fw_ipt_fixture
run_fw "$FWBIN_NFT" "1\n0\n"
check "no ufw or firewalld: nftables is chosen" contains "$OUT" "Firewall backend: nftables (command: nft)"
check "nftables chosen: no iptables call" bash -c '! grep -qE "^iptables" "$1"' _ "$FW_LOG"
fw_new
fw_ipt_fixture
run_fw "$FWBIN_IPT" "1\n0\n"
check "only iptables: iptables is chosen" contains "$OUT" "Firewall backend: iptables (command: iptables)"
fw_new
run_fw "$FWBIN_NONE" "0\n" firewall
check "no backend: says so clearly" contains "$OUT" "No firewall backend found (looked for, in this order: ufw, firewalld, nftables, iptables)."
check "no backend: nothing was changed" contains "$OUT" "Nothing was changed."
check "no backend: does not offer to install one" contains "$OUT" "does not install a firewall tool"
check "no backend: returns without a submenu" not_contains "$OUT" "Show firewall status"
check "no backend: exits 0" equals "$RC" 0
check "no backend: no backend command ran at all" test ! -s "$FW_LOG"
run_fw "$FWBIN_NONE" "9\n\n0\n" menu
check "no backend via the main menu: back at the main menu" at_least_menus "$OUT" 2
check "no backend via the main menu: message shown" contains "$OUT" "No firewall backend found"
check "no backend via the main menu: exits 0" equals "$RC" 0

echo "-- Firewall: submenu"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "0\n"
for line in " 1) Show firewall status" " 2) List rules" " 3) Allow port" " 4) Remove rule" " 0) Back"; do
    check "submenu line '${line}' is exact (clean label)" has_line "$OUT" "$line"
done
check "submenu has exactly 5 numbered entries" equals "$(printf '%s\n' "$OUT" | grep -cE '^ *[0-9]+\) ')" 5
run_fw "$FWBIN_UFW" "9\n0\n0\n" menu
check "main menu item 9 opens the Firewall submenu" contains "$OUT" "Allow port"
check "Firewall is no longer 'not implemented'" not_contains "$OUT" "is not implemented yet"
run_fw "$FWBIN_UFW" "7\nabc\n0\n"
check "invalid submenu input is reported" contains "$OUT" "Invalid choice: 7"
check "non-numeric submenu input is reported" contains "$OUT" "Invalid choice: abc"
run_fw "$FWBIN_UFW" ""
check "EOF in the submenu exits 0" equals "$RC" 0

echo "-- Firewall: ufw status and list (read-only)"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "1\n0\n"
check "ufw enabled: status line" contains "$OUT" "Status         : enabled"
check "ufw enabled: default policy as ufw reports it" contains "$OUT" "Default policy : deny (incoming), allow (outgoing), disabled (routed)"
check "ufw status is read-only" only_reads
fw_new
fw_ufw_fixture
rm -f "$FW_STATE_DIR/ufw.active"
run_fw "$FWBIN_UFW" "1\n0\n"
check "ufw inactive: reported as disabled" contains "$OUT" "Status         : disabled"
check "ufw inactive: no default policy is claimed" contains "$OUT" "not reported while ufw is inactive"
run_fw "$FWBIN_UFW" "2\n0\n"
check "ufw inactive: list says it reports no rules" contains "$OUT" "does not report any rules"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "2\n0\n"
check "list: header" contains "$OUT" "ID     ACTION    PROTO  PORT/SERVICE           SOURCE               RULE (as ufw reports it)"
check "list: rule 1 (22/tcp allow)" contains "$OUT" "$(fw_rowp 1 'allow in' tcp 22 Anywhere)22/tcp"
check "list: rule 2 (80/tcp allow)" contains "$OUT" "$(fw_rowp 2 'allow in' tcp 80 Anywhere)80/tcp"
check "list: rule 3 (port range)" contains "$OUT" "$(fw_rowp 3 'allow in' tcp 6000:6010 Anywhere)6000:6010/tcp"
check "list: rule 4 (application profile with its ports)" contains "$OUT" "$(fw_rowp 4 'allow in' - 'Nginx Full (80,443/tcp)' Anywhere)Nginx Full"
check "list: rule 5 (deny)" contains "$OUT" "$(fw_rowp 5 'deny in' tcp 7000 Anywhere)7000/tcp"
check "list: rule 6 (source shown)" contains "$OUT" "$(fw_rowp 6 'allow in' tcp 9090 192.0.2.0/24)9090/tcp"
check "list: rule 7 (IPv6 twin keeps its own number)" contains "$OUT" "$(fw_rowp 7 'allow in' tcp 22 'Anywhere (v6)')22/tcp (v6)"
check "list: rule 8 (no protocol given)" contains "$OUT" "$(fw_rowp 8 'allow in' any 53 198.51.100.7)53"
check "list: 1 before 2" before_in "$OUT" "$(fw_rowp 1 'allow in' tcp 22 Anywhere)" "$(fw_rowp 2 'allow in' tcp 80 Anywhere)"
check "list: 6 before 8" before_in "$OUT" "$(fw_rowp 6 'allow in' tcp 9090 192.0.2.0/24)" "$(fw_rowp 8 'allow in' any 53 198.51.100.7)"
check "list: count line" contains "$OUT" "8 rule(s), in the order ufw reports them."
check "list is read-only (only status / app / ss / sshd calls)" only_reads
check "list: no backup is made for a read" equals "$(backup_listings ufw)" 0
run_fw "$FWBIN_UFW" "2\n0\n" 
check "list twice: still no change" only_reads

echo "-- Firewall: allow port, validation"
fw_new
fw_ufw_fixture
for bad in 0 65536 080 8x -1 80:90 80,443 1e3 99999 "80 90" "8080/tcp" "0x50" ":80" "٨٠"; do
    run_fw "$FWBIN_UFW" "3\n${bad}\n0\n"
    check "port '${bad}' is refused" contains "$OUT" "Invalid port"
    check "port '${bad}': ufw was not asked to allow anything" flog_lacks "ufw allow"
done
run_fw "$FWBIN_UFW" "3\n\n0\n"
check "empty port cancels" contains "$OUT" "Cancelled. Nothing was changed."
for badp in icmp both "tcp udp" any "" "tcp/udp" "tc"; do
    run_fw "$FWBIN_UFW" "3\n8080\n${badp}\n0\n"
    check "protocol '${badp}' is refused" contains "$OUT" "it must be tcp or udp"
    check "protocol '${badp}': ufw was not asked to allow anything" flog_lacks "ufw allow"
done
check "nothing was written to the backup dir by refusals" equals "$(backup_listings ufw)" 0
run_fw "$FWBIN_UFW" "3\n65535\ntcp\nn\n0\n"
check "port 65535 is valid" contains "$OUT" "Rule to add: allow 65535/tcp (ufw)"
run_fw "$FWBIN_UFW" "3\n1\nudp\nn\n0\n"
check "port 1 is valid" contains "$OUT" "Rule to add: allow 1/udp (ufw)"
run_fw "$FWBIN_UFW" "3\n  8080  \n  TCP \nn\n0\n"
check "surrounding spaces and upper case are accepted" contains "$OUT" "Rule to add: allow 8080/tcp (ufw)"

echo "-- Firewall: allow port, ufw"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "3\n8080\ntcp\ny\n0\n"
check "allow: shows the rule and the exact command first" contains "$OUT" "Rule to add: allow 8080/tcp (ufw)"
check "allow: only ufw allow <port>/<proto> is run" flog_has "ufw allow 8080/tcp"
check "allow: exactly one allow call" equals "$(flog_count 'ufw allow')" 1
check "allow: the backend's own answer is shown" contains "$OUT" "Rule added"
check "allow: rules are re-read after the change" flog_after "ufw allow 8080/tcp" "ufw status numbered"
check "allow: the new rule is listed (v4)" contains "$OUT" "$(fw_rowp 9 'allow in' tcp 8080 Anywhere)8080/tcp"
check "allow: the new rule is listed (v6)" contains "$OUT" "$(fw_rowp 10 'allow in' tcp 8080 'Anywhere (v6)')8080/tcp (v6)"
check "allow: the rule is shown as ufw reports it" contains "$OUT" "The rule as ufw reports it:"
check "allow: no enable/disable/reset" bash -c '! grep -qE "ufw (enable|disable|reset)|--force (enable|disable|reset)" "$1"' _ "$FW_LOG"
check "allow: a text copy of the previous rules is saved" equals "$(backup_listings ufw)" 1
bk="$(first_backup ufw)"
check "allow: the saved copy is the listing from before the change" bash -c 'grep -q "22/tcp" "$1" && ! grep -q "8080/tcp" "$1"' _ "$bk"
check "allow: the saved copy is private (mode 600)" equals "$(file_mode "$bk")" 600
check "allow: the backup dir is private (mode 700)" equals "$(file_mode "$EZVPS_BACKUP_DIR")" 700
check "allow: a ufw rule needs no persistence warning" not_contains "$OUT" "lost at the next reboot"
check "allow: exits 0" equals "$RC" 0
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "3\n5353\nUDP\ny\n0\n"
check "allow udp (upper case accepted): ufw allow 5353/udp" flog_has "ufw allow 5353/udp"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "3\n8080\ntcp\nn\n0\n"
check "declined: nothing is allowed" flog_lacks "ufw allow"
check "declined: says so" contains "$OUT" "Cancelled. Nothing was changed."
check "declined: no backup is made" equals "$(backup_listings ufw)" 0
run_fw "$FWBIN_UFW" "3\n8080\ntcp\n"
check "EOF at the confirmation counts as no" flog_lacks "ufw allow"

echo "-- Firewall: allow port, duplicates and blocking rules"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "3\n22\ntcp\ny\n0\n"
check "duplicate 22/tcp is refused" contains "$OUT" "Port 22/tcp is already allowed by:"
check "duplicate: names the rules" contains "$OUT" "ID 1: 22/tcp"
check "duplicate: names the IPv6 twin too" contains "$OUT" "ID 7: 22/tcp (v6)"
check "duplicate: nothing is added" flog_lacks "ufw allow"
check "duplicate: nothing was changed" contains "$OUT" "Nothing was changed."
check "duplicate: no backup is made" equals "$(backup_listings ufw)" 0
run_fw "$FWBIN_UFW" "3\n80\ntcp\ny\n0\n"
check "duplicate 80/tcp is refused" contains "$OUT" "Port 80/tcp is already allowed by:"
run_fw "$FWBIN_UFW" "3\n6005\ntcp\ny\n0\n"
check "a port inside an allowed range is refused" contains "$OUT" "Port 6005/tcp is already allowed by:"
run_fw "$FWBIN_UFW" "3\n443\ntcp\ny\n0\n"
check "a port covered by an application profile is refused" contains "$OUT" "ID 4: Nginx Full"
check "none of those added anything" flog_lacks "ufw allow"
run_fw "$FWBIN_UFW" "3\n22\nudp\nn\n0\n"
check "same port, other protocol is not a duplicate" contains "$OUT" "Rule to add: allow 22/udp (ufw)"
run_fw "$FWBIN_UFW" "3\n6011\ntcp\nn\n0\n"
check "a port just outside the range is not a duplicate" contains "$OUT" "Rule to add: allow 6011/tcp (ufw)"
run_fw "$FWBIN_UFW" "3\n9090\ntcp\nn\n0\n"
check "an allow limited to one source does not count as allowed for everyone" contains "$OUT" "Rule to add: allow 9090/tcp (ufw)"
run_fw "$FWBIN_UFW" "3\n53\nudp\nn\n0\n"
check "an allow for one source address does not count either" contains "$OUT" "Rule to add: allow 53/udp (ufw)"
run_fw "$FWBIN_UFW" "3\n7000\ntcp\ny\n0\n"
check "an existing deny rule is warned about" contains "$OUT" "A rule that blocks 7000/tcp already exists"
check "the deny rule is named" contains "$OUT" "ID 5: 7000/tcp"
check "the warning does not stop the user: the rule is added after the yes" flog_has "ufw allow 7000/tcp"
# the same second add of the same port is now a duplicate (idempotent)
run_fw "$FWBIN_UFW" "3\n7000\ntcp\ny\n0\n"
check "adding the same port twice: the second time it is refused" contains "$OUT" "Port 7000/tcp is already allowed by:"
check "adding the same port twice: only one allow call in total" equals "$(flog_count 'ufw allow')" 1

echo "-- Firewall: allow port, a port already in use"
fw_new
fw_ufw_fixture
printf '%s\n' 'tcp 9100 nginx 0.0.0.0' 'udp 5353 avahi-daemon 0.0.0.0' >"$FW_LISTEN"
run_fw "$FWBIN_UFW" "3\n9100\ntcp\nn\n0\n"
check "port in use: warns and names the service and address" contains "$OUT" "9100/tcp is already in use on this server by:"
check "port in use: process and address" contains "$OUT" "nginx on 0.0.0.0:9100"
check "port in use: declining adds nothing" flog_lacks "ufw allow"
run_fw "$FWBIN_UFW" "3\n9100\ntcp\ny\n0\n"
check "port in use: one yes is enough, the rule is added (the user is not blocked)" flog_has "ufw allow 9100/tcp"
check "port in use: the check used ss for tcp" flog_has "ss -H -ltnp"
run_fw "$FWBIN_UFW" "3\n5353\nudp\ny\n0\n"
check "udp in use: warns" contains "$OUT" "avahi-daemon on 0.0.0.0:5353"
check "udp in use: the check used ss for udp" flog_has "ss -H -lunp"
check "udp in use: the rule is added after the yes" flog_has "ufw allow 5353/udp"
run_fw "$FWBIN_UFW" "3\n5353\ntcp\nn\n0\n"
check "a udp listener does not warn about the same tcp port" not_contains "$OUT" "already in use"
run_fw "$FWBIN_UFW" "3\n9200\ntcp\nn\n0\n"
check "a free port: no in-use warning" not_contains "$OUT" "already in use"
run_fw "$FWBIN_UFW_NOSS" "3\n5354\nudp\nn\n0\n"
check "no ss: udp in use cannot be checked, and the user is told" contains "$OUT" "ss is not installed, so ezvps could not check whether something listens on 5354/udp."
run_fw "$FWBIN_UFW_NOSS" "3\n9201\ntcp\nn\n0\n"
check "no ss: tcp falls back to a connect test and still works" contains "$OUT" "Rule to add: allow 9201/tcp (ufw)"

echo "-- Firewall: allow and remove need an enabled firewall, and report failures"
fw_new
fw_ufw_fixture
rm -f "$FW_STATE_DIR/ufw.active"
run_fw "$FWBIN_UFW" "3\n8080\ntcp\ny\n0\n"
check "ufw disabled: allow is refused" contains "$OUT" "ufw is disabled. ezvps does not enable or disable a firewall"
check "ufw disabled: nothing was asked of ufw" flog_lacks "ufw allow"
run_fw "$FWBIN_UFW" "4\n0\n"
check "ufw disabled: remove is refused too" contains "$OUT" "ufw is disabled."
check "ufw disabled: no delete" flog_lacks "delete"
check "ufw is never enabled by ezvps" bash -c '! grep -qE "enable" "$1"' _ "$FW_LOG"
fw_new
fw_ufw_fixture
export FAKE_UFW_ADD_FAIL=1
run_fw "$FWBIN_UFW" "3\n8080\ntcp\ny\n0\n"
check "ufw refuses the rule: the error is shown" contains "$OUT" "ufw could not add the rule: ERROR: Could not update running firewall"
check "ufw refuses the rule: ezvps says nothing else was changed" contains "$OUT" "Nothing else was changed."
check "ufw refuses the rule: ezvps still exits 0 and the menu goes on" equals "$RC" 0
unset FAKE_UFW_ADD_FAIL
export FAKE_UFW_ADD_NOOP=1
run_fw "$FWBIN_UFW" "3\n8080\ntcp\ny\n0\n"
check "a rule that the backend does not report afterwards is not claimed as added" contains "$OUT" "ufw does not list an allow rule for 8080/tcp after the change"
unset FAKE_UFW_ADD_NOOP

echo "-- Firewall: remove rule, ufw"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "4\n2\ny\n0\n"
check "remove: the rules are listed first" before_in "$OUT" "Current rules:" "Rule to remove (only this one):"
check "remove: the listing shows the ids" contains "$OUT" "$(fw_rowp 2 'allow in' tcp 80 Anywhere)80/tcp"
check "remove: shows the exact command" contains "$OUT" "ufw --force delete 2"
check "remove: only that rule is deleted (one delete call)" equals "$(flog_count 'ufw --force delete')" 1
check "remove: ufw --force delete 2" flog_has "ufw --force delete 2"
check "remove: no reset, disable or interactive delete" bash -c '! grep -qE "ufw (reset|disable|enable|delete)|--force (reset|disable|enable)" "$1"' _ "$FW_LOG"
check "remove: the rules are re-read afterwards" flog_after "ufw --force delete 2" "ufw status numbered"
check "remove: the list afterwards has one rule less" contains "$OUT" "7 rule(s), in the order ufw reports them."
check "remove: it says what was removed" contains "$OUT" "Removed: 80/tcp"
check "remove: it says the firewall stays enabled" contains "$OUT" "the firewall was not disabled."
check "remove: the other rules are untouched" equals "$(<"$FW_STATE_DIR/ufw.rules")" "$(printf '%s\n' '22/tcp|ALLOW IN|Anywhere' '6000:6010/tcp|ALLOW IN|Anywhere' 'Nginx Full|ALLOW IN|Anywhere' '7000/tcp|DENY IN|Anywhere' '9090/tcp|ALLOW IN|192.0.2.0/24' '22/tcp (v6)|ALLOW IN|Anywhere (v6)' '53|ALLOW IN|198.51.100.7')"
check "remove: a text copy of the previous rules is saved" equals "$(backup_listings ufw)" 1
check "remove: exits 0" equals "$RC" 0
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "4\n2\nn\n0\n"
check "remove declined: nothing is deleted" flog_lacks "delete"
check "remove declined: says so" contains "$OUT" "Cancelled. Nothing was changed."
run_fw "$FWBIN_UFW" "4\n2\n"
check "remove: EOF at the confirmation counts as no" flog_lacks "delete"
for badid in 99 abc 0 -1 "1 2" "1;2" all "*" 08x; do
    run_fw "$FWBIN_UFW" "4\n${badid}\ny\n0\n"
    check "remove: id '${badid}' is not in the list" contains "$OUT" "There is no rule with ID"
    check "remove: id '${badid}' deletes nothing" flog_lacks "delete"
done
run_fw "$FWBIN_UFW" "4\n\n0\n"
check "remove: an empty id cancels" contains "$OUT" "Cancelled. Nothing was changed."
check "remove: there is no remove-all: the ids are the only way in" flog_lacks "delete"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "4\n5\ny\n0\n"
check "removing a deny rule needs no SSH warning" not_contains "$OUT" "WARNING"
check "removing a deny rule works" flog_has "ufw --force delete 5"
fw_new
export FAKE_UFW_DEL_FAIL=1
fw_ufw_fixture
run_fw "$FWBIN_UFW" "4\n2\ny\n0\n"
check "ufw refuses the removal: the error is shown" contains "$OUT" "ufw could not remove the rule: ERROR: Could not delete rule"
check "ufw refuses the removal: ezvps still exits 0" equals "$RC" 0
unset FAKE_UFW_DEL_FAIL
fw_new
fw_ufw_fixture
export FAKE_UFW_DEL_NOOP=1
run_fw "$FWBIN_UFW" "4\n2\ny\n0\n"
check "a removal that the backend does not carry out is not claimed as done" contains "$OUT" "ufw still lists the rule you removed."
check "a removal that did not happen is not summarised as removed" not_contains "$OUT" "Only that rule was removed"
unset FAKE_UFW_DEL_NOOP
fw_new
fw_ufw_fixture
export FAKE_UFW_SHIFT=1
run_fw "$FWBIN_UFW" "4\n2\ny\n0\n"
check "rules that change between listing and removal: nothing is deleted" flog_lacks "delete"
check "rules that change between listing and removal: the user is told" contains "$OUT" "The rules changed while you were choosing"
unset FAKE_UFW_SHIFT

echo "-- Firewall: removing an SSH rule needs a separate warning and confirmation"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW" "4\n1\ny\nn\n0\n"
check "ssh rule: explicit warning naming the rule and the port" contains "$OUT" "WARNING: rule 1 allows SSH (port 22/tcp)."
check "ssh rule: warns that it can lock the user out" contains "$OUT" "can lock you out of this server, including the session you are using now"
check "ssh rule: declining the second question deletes nothing" flog_lacks "delete"
check "ssh rule: the answers were consumed by the two questions (no stray menu input)" not_contains "$OUT" "Invalid choice"
run_fw "$FWBIN_UFW" "4\n1\ny\n"
check "ssh rule: one yes is not enough (EOF at the second question)" flog_lacks "delete"
run_fw "$FWBIN_UFW" "4\n1\nn\n0\n"
check "ssh rule: declining the first question stops before the warning" not_contains "$OUT" "WARNING"
check "ssh rule: ...and deletes nothing" flog_lacks "delete"
run_fw "$FWBIN_UFW" "4\n7\ny\nn\n0\n"
check "ssh rule: the IPv6 twin is protected too" contains "$OUT" "WARNING: rule 7 allows SSH (port 22/tcp)."
run_fw "$FWBIN_UFW" "4\n1\ny\ny\n0\n"
check "ssh rule: two yes answers remove exactly that rule" flog_has "ufw --force delete 1"
check "ssh rule: one delete call only" equals "$(flog_count 'ufw --force delete')" 1
fw_new
fw_ufw_fixture
printf '%s\n' '2222/tcp|ALLOW IN|Anywhere' >>"$FW_STATE_DIR/ufw.rules"
export FW_SSHD_PORTS=2222
run_fw "$FWBIN_UFW" "4\n9\ny\nn\n0\n"
check "ssh on another port: that port's rule is protected (read from sshd)" contains "$OUT" "WARNING: rule 9 allows SSH (port 2222/tcp)."
run_fw "$FWBIN_UFW" "4\n1\ny\n0\n"
check "ssh on another port: 22/tcp is no longer special, one yes removes it" flog_has "ufw --force delete 1"
check "ssh on another port: ... without a warning" not_contains "$OUT" "WARNING"
export FW_SSHD_PORTS=22
fw_new
fw_ufw_fixture
printf '%s\n' '2200/tcp|ALLOW IN|Anywhere' >>"$FW_STATE_DIR/ufw.rules"
export SSH_CONNECTION="192.0.2.50 51000 192.0.2.10 2200"
run_fw "$FWBIN_UFW" "4\n9\ny\nn\n0\n"
check "the port of the current SSH session is protected" contains "$OUT" "WARNING: rule 9 allows SSH (port 2200/tcp)."
check "connected over SSH: the user is told" contains "$OUT" "You appear to be connected over SSH right now."
check "...and nothing was deleted" flog_lacks "delete"
unset SSH_CONNECTION
fw_new
fw_ufw_fixture
export FW_SSHD_PORTS=6005
run_fw "$FWBIN_UFW" "4\n3\ny\nn\n0\n"
check "a range that covers the ssh port is protected" contains "$OUT" "WARNING: rule 3 allows SSH (port 6005/tcp)."
export FW_SSHD_PORTS=22
fw_new
fw_ufw_fixture
printf '%s\n' 'OpenSSH|ALLOW IN|Anywhere' >>"$FW_STATE_DIR/ufw.rules"
run_fw "$FWBIN_UFW" "4\n9\ny\nn\n0\n"
check "the OpenSSH application profile is protected (via its ports)" contains "$OUT" "WARNING: rule 9 allows SSH (port 22/tcp)."
export FAKE_UFW_APPINFO_FAIL=1
run_fw "$FWBIN_UFW" "4\n9\ny\nn\n0\n"
check "the OpenSSH profile is protected by name when its ports are unknown" contains "$OUT" "WARNING: rule 9 is the SSH rule (SSH port 22)."
unset FAKE_UFW_APPINFO_FAIL
check "...and nothing was deleted" flog_lacks "delete"
fw_new
fw_ufw_fixture
printf '%s\n' 'Anywhere|ALLOW IN|192.0.2.5' >>"$FW_STATE_DIR/ufw.rules"
run_fw "$FWBIN_UFW" "4\n9\ny\nn\n0\n"
check "an allow without a port may be what carries SSH: warned about" contains "$OUT" "has no port or protocol restriction, so it may be what keeps SSH (port 22) or your current connection working"
run_fw "$FWBIN_UFW" "4\n3\ny\n0\n"
check "an unrelated port range is removed with one yes" flog_has "ufw --force delete 3"
fw_new
fw_ufw_fixture
run_fw "$FWBIN_UFW_NOSSHD" "4\n1\ny\nn\n0\n"
check "no sshd command: the default port 22 is still protected" contains "$OUT" "WARNING: rule 1 allows SSH (port 22/tcp)."
fw_new
fw_ufw_fixture
printf 'Include /etc/ssh/sshd_config.d/*.conf\n#Port 22\nPort 2022\n' >"$EZVPS_SSHD_CONFIG"
printf '%s\n' '2022/tcp|ALLOW IN|Anywhere' >>"$FW_STATE_DIR/ufw.rules"
run_fw "$FWBIN_UFW_NOSSHD" "4\n9\ny\nn\n0\n"
check "no sshd command: the Port line of sshd_config is used" contains "$OUT" "WARNING: rule 9 allows SSH (port 2022/tcp)."

echo "-- Firewall: firewalld"
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "1\n0\n"
check "firewalld running: enabled" contains "$OUT" "Status         : enabled"
check "firewalld: default zone and its target as reported" contains "$OUT" "Default policy : default zone public (target: default)"
check "firewalld status is read-only" only_reads
rm -f "$FW_STATE_DIR/fwd/running"
run_fw "$FWBIN_FWD1" "1\n0\n"
check "firewalld not running: disabled" contains "$OUT" "Status         : disabled"
check "firewalld not running: no policy claimed" contains "$OUT" "not reported while firewalld is not running"
run_fw "$FWBIN_FWD1" "2\n0\n"
check "firewalld not running: list says it reports no rules" contains "$OUT" "does not report any rules"
run_fw "$FWBIN_FWD1" "3\n8081\ntcp\ny\n0\n"
check "firewalld not running: allow is refused" contains "$OUT" "firewalld is disabled."
check "firewalld not running: nothing was added" flog_lacks "--add-port"
run_fw "$FWBIN_FWD1" "4\n0\n"
check "firewalld not running: remove is refused" contains "$OUT" "firewalld is disabled."
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "2\n0\n"
check "firewalld list: header names the backend" contains "$OUT" "RULE (as firewalld reports it)"
check "firewalld list: port 8080/tcp" contains "$OUT" "$(fw_rowp 1 allow tcp 8080 -)zone public: port 8080/tcp"
check "firewalld list: port range with udp" contains "$OUT" "$(fw_rowp 2 allow udp 5000-5010 -)zone public: port 5000-5010/udp"
check "firewalld list: service with the ports firewalld reports for it" contains "$OUT" "$(fw_rowp 3 allow - 'ssh (22/tcp)' -)zone public: service ssh"
check "firewalld list: second service" contains "$OUT" "$(fw_rowp 4 allow - 'http (80/tcp)' -)zone public: service http"
check "firewalld list: rich rule with action, protocol, port and source" contains "$OUT" "$(fw_rowp 5 accept tcp 9443 192.0.2.0/24)zone public: rich rule rule family=\"ipv4\" source address=\"192.0.2.0/24\" port port=\"9443\" protocol=\"tcp\" accept"
check "firewalld list: other active zones are shown" contains "$OUT" "$(fw_rowp 6 allow tcp 3000 -)zone internal: port 3000/tcp"
check "firewalld list: zone sources are reported" contains "$OUT" "Zone internal applies only to these sources: 198.51.100.0/24"
check "firewalld list: numbering note" contains "$OUT" "firewalld has no rule numbers"
check "firewalld list: the default zone comes first" before_in "$OUT" "zone public: port 8080/tcp" "zone internal: port 3000/tcp"
check "firewalld list is read-only" only_reads
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "3\n8081\ntcp\ny\n0\n"
check "firewalld allow: shows both commands first" contains "$OUT" "firewall-cmd --permanent --zone=public --add-port=8081/tcp"
check "firewalld allow: runtime rule added in the default zone" flog_has "firewall-cmd --zone=public --add-port=8081/tcp"
check "firewalld allow: permanent rule added too" flog_has "firewall-cmd --permanent --zone=public --add-port=8081/tcp"
check "firewalld allow: no reload (it would drop unsaved runtime changes)" bash -c '! grep -qE "reload|panic|runtime-to-permanent" "$1"' _ "$FW_LOG"
check "firewalld allow: re-read afterwards" flog_after "--add-port=8081/tcp" "--list-ports"
check "firewalld allow: the new rule is listed" contains "$OUT" "zone public: port 8081/tcp"
check "firewalld allow: a text copy of the previous rules is saved" equals "$(backup_listings firewalld)" 1
check "firewalld allow: saved to the permanent configuration too, so no persistence warning" not_contains "$OUT" "lost at the next reboot"
for dup in "8080 tcp" "80 tcp" "22 tcp" "443 tcp" "5003 udp"; do
    read -r dport dproto <<<"$dup"
    run_fw "$FWBIN_FWD1" "3\n${dport}\n${dproto}\nn\n0\n"
    if [[ "$dup" == "443 tcp" ]]; then
        check "firewalld: ${dup} is NOT a duplicate (no service covers it)" contains "$OUT" "Rule to add: allow 443/tcp (firewalld)"
    else
        check "firewalld: ${dup} is already allowed (port, service or range)" contains "$OUT" "Port ${dport}/${dproto} is already allowed by:"
    fi
done
check "firewalld duplicates added nothing (only 8081 from before)" equals "$(flog_count '--add-port')" 2
run_fw "$FWBIN_FWD1" "3\n9443\ntcp\nn\n0\n"
check "firewalld: a source-limited rich rule does not count" contains "$OUT" "Rule to add: allow 9443/tcp (firewalld)"
run_fw "$FWBIN_FWD1" "3\n3000\ntcp\nn\n0\n"
check "firewalld: a port open only in another zone is not a duplicate in the default zone" contains "$OUT" "Rule to add: allow 3000/tcp (firewalld)"
fw_new
fw_fwd_fixture
export FAKE_FWD_PERM_FAIL=1
run_fw "$FWBIN_FWD1" "3\n8082\ntcp\ny\n0\n"
check "firewalld: permanent write fails after the runtime one: said clearly" contains "$OUT" "added to the running firewall, but the permanent configuration could not be changed"
check "firewalld: ...and the menu goes on" equals "$RC" 0
unset FAKE_FWD_PERM_FAIL
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "4\n1\ny\n0\n"
check "firewalld remove port: runtime" flog_has "firewall-cmd --zone=public --remove-port=8080/tcp"
check "firewalld remove port: permanent" flog_has "firewall-cmd --permanent --zone=public --remove-port=8080/tcp"
check "firewalld remove: no reload, no panic" bash -c '! grep -qE "reload|panic" "$1"' _ "$FW_LOG"
check "firewalld remove: the other rules stay (5 left in the list)" contains "$OUT" "5 rule(s), in the order firewalld reports them."
check "firewalld remove: says the firewall was not disabled" contains "$OUT" "the firewall was not disabled."
check "firewalld remove: exactly one remove call per config" equals "$(flog_count '--remove-')" 2
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "4\n6\ny\n0\n"
check "firewalld remove from another zone: uses that zone" flog_has "firewall-cmd --zone=internal --remove-port=3000/tcp"
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "4\n5\ny\n0\n"
check "firewalld remove rich rule: exactly the listed rule" flog_has 'firewall-cmd --zone=public --remove-rich-rule=rule family="ipv4" source address="192.0.2.0/24" port port="9443" protocol="tcp" accept'
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "4\n4\ny\n0\n"
check "firewalld remove service: --remove-service" flog_has "firewall-cmd --zone=public --remove-service=http"
fw_new
fw_fwd_fixture
run_fw "$FWBIN_FWD1" "4\n3\ny\nn\n0\n"
check "firewalld ssh service: warned" contains "$OUT" "WARNING: rule 3 allows SSH (port 22/tcp)."
check "firewalld ssh service: declining the second question deletes nothing" flog_lacks "--remove-"
run_fw "$FWBIN_FWD1" "4\n3\ny\ny\n0\n"
check "firewalld ssh service: two yes answers remove it" flog_has "firewall-cmd --zone=public --remove-service=ssh"
fw_new
fw_fwd_fixture
export FAKE_FWD_PERM_FAIL=1
run_fw "$FWBIN_FWD1" "4\n1\ny\n0\n"
check "firewalld remove: permanent failure after the runtime removal is said clearly" contains "$OUT" "removed from the running firewall, but the permanent configuration could not be changed"
unset FAKE_FWD_PERM_FAIL

echo "-- Firewall: nftables"
fw_new
fw_nft_fixture
run_fw "$FWBIN_NFT1" "1\n0\n"
check "nftables: enabled (the input chain has a drop policy)" contains "$OUT" "Status         : enabled"
check "nftables: default policy of the input chain as nft reports it" contains "$OUT" "Default policy : inet filter input: policy drop"
check "nftables: the forward chain is not the input policy" not_contains "$OUT" "forward: policy"
check "nftables: explains the on/off meaning" contains "$OUT" "nftables has no on/off switch"
check "nftables status is read-only" only_reads
fw_new
printf '%s\n' 'inet|filter|input|type filter hook input priority filter; policy accept;' >"$FW_STATE_DIR/nft.chains"
: >"$FW_STATE_DIR/nft.rules"
run_fw "$FWBIN_NFT1" "1\n0\n"
check "nftables: accept policy and no rules: disabled" contains "$OUT" "Status         : disabled"
fw_new
: >"$FW_STATE_DIR/nft.chains"
run_fw "$FWBIN_NFT1" "1\n0\n"
check "nftables: nothing loaded: disabled, no policy claimed" contains "$OUT" "not reported: no input filter chain is loaded"
run_fw "$FWBIN_NFT1" "3\n8080\ntcp\ny\n0\n"
check "nftables: no input chain: allow is refused, no table or chain is created" contains "$OUT" "No nftables input chain (type filter, hook input) is loaded, and ezvps does not create tables or chains."
check "nftables: ...and nothing was inserted" flog_lacks "nft insert"
fw_new
fw_nft_fixture
run_fw "$FWBIN_NFT1" "2\n0\n"
check "nft list: ct state rule (no port)" contains "$OUT" "$(fw_rowp 4 accept - - -)inet filter input: ct state established,related accept"
check "nft list: plain port rule" contains "$OUT" "$(fw_rowp 5 accept tcp 22 -)inet filter input: tcp dport 22 accept"
check "nft list: set of ports and a source" contains "$OUT" "$(fw_rowp 6 accept tcp 80,443 192.0.2.0/24)inet filter input: ip saddr 192.0.2.0/24 tcp dport { 80, 443 } accept"
check "nft list: udp range with a counter" contains "$OUT" "$(fw_rowp 7 accept udp 5000-5010 -)inet filter input: udp dport 5000-5010 counter packets 3 bytes 180 accept"
check "nft list: drop rule" contains "$OUT" "$(fw_rowp 8 drop tcp 7000 -)inet filter input: tcp dport 7000 drop"
check "nft list: interface rule" contains "$OUT" "$(fw_rowp 9 accept - - -)inet filter input: iif \"lo\" accept"
check "nft list: ids are the handles, in nft's own order" before_in "$OUT" "$(fw_rowp 4 accept - - -)" "$(fw_rowp 9 accept - - -)"
check "nft list: rules of the forward chain are not shown" not_contains "$OUT" "inet filter forward:"
check "nft list: a set definition is not mistaken for a rule" not_contains "$OUT" "192.0.2.66"
check "nft list: count" contains "$OUT" "6 rule(s), in the order nftables reports them."
check "nft list: scope note" contains "$OUT" "ID is the nftables rule handle"
check "nft list is read-only" only_reads
fw_new
fw_nft_fixture
run_fw "$FWBIN_NFT1" "3\n8080\ntcp\ny\n0\n"
check "nft allow: shows the command first" contains "$OUT" "nft insert rule inet filter input tcp dport 8080 accept"
check "nft allow: inserts into the existing input chain" flog_has "nft insert rule inet filter input tcp dport 8080 accept"
check "nft allow: no table or chain is created, nothing is flushed" bash -c '! grep -qE "nft (add|create|flush|delete table|delete chain)" "$1"' _ "$FW_LOG"
check "nft allow: re-read afterwards" flog_after "nft insert rule" "nft -a list ruleset"
check "nft allow: the new rule is listed with its handle" contains "$OUT" "$(fw_rowp 100 accept tcp 8080 -)inet filter input: tcp dport 8080 accept"
check "nft allow: warns that the change is not persistent" contains "$OUT" "nftables changes apply to the running firewall only"
check "nft allow: a text copy of the previous ruleset is saved" equals "$(backup_listings nftables)" 1
check "nft allow: the saved copy is the ruleset from before the change" bash -c 'grep -q "tcp dport 22 accept" "$1" && ! grep -q "dport 8080" "$1"' _ "$(first_backup nftables)"
for dup in "22 tcp" "5003 udp"; do
    read -r dport dproto <<<"$dup"
    run_fw "$FWBIN_NFT1" "3\n${dport}\n${dproto}\ny\n0\n"
    check "nft: ${dup} is already allowed" contains "$OUT" "Port ${dport}/${dproto} is already allowed by:"
done
run_fw "$FWBIN_NFT1" "3\n80\ntcp\nn\n0\n"
check "nft: a port allowed only for one source is not a duplicate" contains "$OUT" "Rule to add: allow 80/tcp (nftables)"
run_fw "$FWBIN_NFT1" "3\n7000\ntcp\nn\n0\n"
check "nft: an existing drop rule is warned about" contains "$OUT" "A rule that blocks 7000/tcp already exists"
fw_new
fw_nft_fixture
printf '%s\n' 'ip|filter|INPUT|type filter hook input priority filter; policy accept;' >>"$FW_STATE_DIR/nft.chains"
run_fw "$FWBIN_NFT1" "3\n8080\ntcp\n2\ny\n0\n"
check "nft: two input chains: the user is asked, never guessed" contains "$OUT" "More than one nftables input chain is loaded:"
check "nft: the chosen chain is used" flog_has "nft insert rule ip filter INPUT tcp dport 8080 accept"
run_fw "$FWBIN_NFT1" "3\n8081\ntcp\n9\n0\n"
check "nft: a bad chain choice changes nothing" contains "$OUT" "No chain chosen. Nothing was changed."
check "nft: ...no second insert" equals "$(flog_count 'nft insert')" 1
fw_new
fw_nft_fixture
export FAKE_NFT_FAIL=1
run_fw "$FWBIN_NFT1" "3\n8080\ntcp\ny\n0\n"
check "nft failing: the error is shown, nothing is inserted" contains "$OUT" "nft list ruleset failed: Error: Operation not permitted"
check "nft failing: the menu goes on" equals "$RC" 0
unset FAKE_NFT_FAIL
export FAKE_NFT_ADD_NOOP=1
run_fw "$FWBIN_NFT1" "3\n8080\ntcp\ny\n0\n"
check "nft: a rule that nft does not report afterwards is not claimed as added" contains "$OUT" "nftables does not list an allow rule for 8080/tcp after the change"
unset FAKE_NFT_ADD_NOOP
fw_new
fw_nft_fixture
run_fw "$FWBIN_NFT1" "4\n8\ny\n0\n"
check "nft remove: by handle, in the rule's own chain" flog_has "nft delete rule inet filter input handle 8"
check "nft remove: one delete call, nothing flushed" equals "$(flog_count 'nft delete')" 1
check "nft remove: the forward chain rule is untouched" bash -c 'grep -q "^inet|filter|forward|20|" "$1"' _ "$FW_STATE_DIR/nft.rules"
check "nft remove: the other input rules are untouched" equals "$(grep -c '|input|' "$FW_STATE_DIR/nft.rules")" 5
check "nft remove: 5 rules listed afterwards" contains "$OUT" "5 rule(s), in the order nftables reports them."
check "nft remove: persistence note" contains "$OUT" "lost at the next reboot or reload"
run_fw "$FWBIN_NFT1" "4\n5\ny\nn\n0\n"
check "nft ssh rule: warned" contains "$OUT" "WARNING: rule 5 allows SSH (port 22/tcp)."
check "nft ssh rule: declining deletes nothing more" equals "$(flog_count 'nft delete')" 1
for gen in 4 9; do
    run_fw "$FWBIN_NFT1" "4\n${gen}\ny\nn\n0\n"
    check "nft rule ${gen} has no port: warned that it may carry SSH" contains "$OUT" "WARNING: rule ${gen} has no port or protocol restriction"
done
check "nft: none of those deleted anything" equals "$(flog_count 'nft delete')" 1

echo "-- Firewall: iptables"
fw_new
fw_ipt_fixture
run_fw "$FWBIN_IPT1" "1\n0\n"
check "iptables: enabled (INPUT policy DROP)" contains "$OUT" "Status         : enabled"
check "iptables: default policy as iptables reports it" contains "$OUT" "Default policy : INPUT policy DROP"
check "iptables: explains the on/off meaning" contains "$OUT" "iptables has no on/off switch"
check "iptables status is read-only" only_reads
fw_new
echo ACCEPT >"$FW_STATE_DIR/ipt.policy"
: >"$FW_STATE_DIR/ipt.rules"
run_fw "$FWBIN_IPT1" "1\n0\n"
check "iptables: accept policy and no rules: disabled" contains "$OUT" "Status         : disabled"
check "iptables: ...with the policy shown" contains "$OUT" "Default policy : INPUT policy ACCEPT"
printf '%s\n' '-p tcp -m tcp --dport 22 -j ACCEPT' >"$FW_STATE_DIR/ipt.rules"
run_fw "$FWBIN_IPT1" "1\n0\n"
check "iptables: accept policy but a rule: enabled" contains "$OUT" "Status         : enabled"
fw_new
fw_ipt_fixture
run_fw "$FWBIN_IPT1" "2\n0\n"
check "iptables list: interface rule" contains "$OUT" "$(fw_rowp 1 accept - - -)-A INPUT -i lo -j ACCEPT"
check "iptables list: ssh rule" contains "$OUT" "$(fw_rowp 2 accept tcp 22 -)-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT"
check "iptables list: multiport rule" contains "$OUT" "$(fw_rowp 3 accept tcp 80,443 -)-A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT"
check "iptables list: source shown" contains "$OUT" "$(fw_rowp 4 accept tcp 9090 192.0.2.0/24)-A INPUT -s 192.0.2.0/24"
check "iptables list: udp range" contains "$OUT" "$(fw_rowp 5 accept udp 6000:6010 -)-A INPUT -p udp"
check "iptables list: drop rule" contains "$OUT" "$(fw_rowp 6 drop tcp 7000 -)-A INPUT -p tcp -m tcp --dport 7000 -j DROP"
check "iptables list: connection tracking rule" contains "$OUT" "$(fw_rowp 7 accept - - -)-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
check "iptables list: the policy line is not a rule" contains "$OUT" "7 rule(s), in the order iptables reports them."
check "iptables list: scope note (INPUT chain, IPv4)" contains "$OUT" "INPUT chain of the iptables filter table (IPv4 only)"
check "iptables list is read-only" only_reads
fw_new
fw_ipt_fixture
run_fw "$FWBIN_IPT1" "3\n8080\ntcp\ny\n0\n"
check "iptables allow: shows the command first" contains "$OUT" "iptables -w -I INPUT 1 -p tcp --dport 8080 -j ACCEPT"
check "iptables allow: the documented insert is run" flog_has "iptables -w -I INPUT 1 -p tcp --dport 8080 -j ACCEPT"
check "iptables allow: no flush, no policy change" bash -c '! grep -qE "iptables( -w)? -(F|X|Z|P)( |$)" "$1"' _ "$FW_LOG"
check "iptables allow: re-read afterwards" flog_after "iptables -w -I INPUT" "iptables -w -S INPUT"
check "iptables allow: the new rule is first in the list" contains "$OUT" "$(fw_rowp 1 accept tcp 8080 -)-A INPUT -p tcp -m tcp --dport 8080 -j ACCEPT"
check "iptables allow: the old first rule moved to number 2" contains "$OUT" "$(fw_rowp 2 accept - - -)-A INPUT -i lo -j ACCEPT"
check "iptables allow: warns that the change is not persistent" contains "$OUT" "iptables changes apply to the running firewall only"
check "iptables allow: a text copy of the previous rules is saved" equals "$(backup_listings iptables)" 1
for dup in "22 tcp" "443 tcp" "6005 udp"; do
    read -r dport dproto <<<"$dup"
    run_fw "$FWBIN_IPT1" "3\n${dport}\n${dproto}\ny\n0\n"
    check "iptables: ${dup} is already allowed" contains "$OUT" "Port ${dport}/${dproto} is already allowed by:"
done
check "iptables duplicates added nothing (only 8080 from before)" equals "$(flog_count 'iptables -w -I')" 1
run_fw "$FWBIN_IPT1" "3\n9090\ntcp\nn\n0\n"
check "iptables: a port allowed only for one source is not a duplicate" contains "$OUT" "Rule to add: allow 9090/tcp (iptables)"
run_fw "$FWBIN_IPT1" "3\n7000\ntcp\nn\n0\n"
check "iptables: an existing DROP rule is warned about" contains "$OUT" "A rule that blocks 7000/tcp already exists"
fw_new
fw_ipt_fixture
run_fw "$FWBIN_IPT1" "4\n3\ny\n0\n"
check "iptables remove: by number" flog_has "iptables -w -D INPUT 3"
check "iptables remove: one delete call, no flush" equals "$(flog_count 'iptables -w -D')" 1
check "iptables remove: 6 rules listed afterwards" contains "$OUT" "6 rule(s), in the order iptables reports them."
check "iptables remove: the policy is untouched" equals "$(<"$FW_STATE_DIR/ipt.policy")" DROP
fw_new
fw_ipt_fixture
run_fw "$FWBIN_IPT1" "4\n2\ny\nn\n0\n"
check "iptables ssh rule: warned" contains "$OUT" "WARNING: rule 2 allows SSH (port 22/tcp)."
for gen in 1 7; do
    run_fw "$FWBIN_IPT1" "4\n${gen}\ny\nn\n0\n"
    check "iptables rule ${gen} has no port: warned that it may carry SSH" contains "$OUT" "WARNING: rule ${gen} has no port or protocol restriction"
done
check "iptables: none of the declined removals deleted anything" equals "$(flog_count 'iptables -w -D')" 0
run_fw "$FWBIN_IPT1" "4\n6\ny\n0\n"
check "iptables: a DROP rule is removed without an SSH warning" flog_has "iptables -w -D INPUT 6"
fw_new
fw_ipt_fixture
export FAKE_IPT_FAIL=1
run_fw "$FWBIN_IPT1" "2\n0\n"
check "iptables failing: the error is shown and the menu goes on" contains "$OUT" "iptables -S INPUT failed: iptables: Permission denied"
check "iptables failing: exits 0" equals "$RC" 0
unset FAKE_IPT_FAIL

echo "-- Firewall: supported systems and root"
fw_new
fw_ufw_fixture
FW_ENV=(EZVPS_SKIP_OS_CHECK=0 "EZVPS_OS_RELEASE=$OSD/ubuntu2510")
run_fw "$FWBIN_UFW" "3\n8080\ntcp\ny\n0\n"
check "unsupported system: allow is refused with the shared message" contains "$OUT" "Firewall needs a supported system: ${OS_LIST_TEXT}; found 'ubuntu 25.10 questing'. Nothing was changed."
check "unsupported system: nothing was asked of ufw" test ! -s "$FW_LOG"
run_fw "$FWBIN_UFW" "4\n2\ny\n0\n"
check "unsupported system: remove is refused" contains "$OUT" "Firewall needs a supported system"
check "unsupported system: no delete" flog_lacks "delete"
run_fw "$FWBIN_UFW" "1\n2\n0\n"
check "unsupported system: status still works (read-only)" contains "$OUT" "Status         : enabled"
check "unsupported system: list still works (read-only)" contains "$OUT" "8 rule(s)"
FW_ENV=(EZVPS_SKIP_OS_CHECK=0 "EZVPS_OS_RELEASE=$OSD/ubuntu2404-jammy")
run_fw "$FWBIN_UFW" "3\n8080\ntcp\ny\n0\n"
check "codename mismatch is refused too" contains "$OUT" "the codename does not match the version"
for osf in debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604; do
    fw_new
    fw_ufw_fixture
    FW_ENV=(EZVPS_SKIP_OS_CHECK=0 "EZVPS_OS_RELEASE=$OSD/$osf")
    run_fw "$FWBIN_UFW" "3\n8080\ntcp\ny\n0\n"
    check "supported system ${osf}: allow works" flog_has "ufw allow 8080/tcp"
done
FW_ENV=()
if [[ "$(id -u)" != 0 ]]; then
    fw_new
    fw_ufw_fixture
    FW_ENV=(-u EZVPS_ALLOW_NONROOT)
    run_fw "$FWBIN_UFW" "" firewall
    check "not root: the module is refused" contains "$OUT" "ezvps must be run as root."
    check "not root: nothing was asked of ufw" test ! -s "$FW_LOG"
    FW_ENV=()
fi

echo "-- Firewall: source rules"
fw_body() { awk '/^(fw_[a-z_]+|module_firewall)\(\) \{/ {on=1} on {print} /^}/ {on=0}' "$EZVPS" | grep -vE '^[[:space:]]*#'; }
fw_fn() { awk -v f="$1" '$0 ~ "^"f"\\(\\) \\{" {on=1} on {print} /^}/ {on=0}' "$EZVPS" | grep -vE '^[[:space:]]*#'; }
FWCODE="$(fw_body)"
check "the Firewall code exists" test -n "$FWCODE"
check "the detection order is fixed: ufw, firewalld, nftables, iptables" equals "$(grep -c '^FW_BACKENDS=(ufw firewalld nftables iptables)' "$EZVPS")" 1
check "no enable, disable, reset or flush of any firewall" bash -c '! grep -qE "(ufw|nft|iptables|firewall-cmd)[^\"]* (enable|disable|reset|flush)|ufw --force (enable|disable|reset)|iptables[^\"]* -[FXZP] |nft (add|create|delete) (table|chain)|--reload|--complete-reload|--panic|--runtime-to-permanent|--set-default-zone" <<<"$1"' _ "$FWCODE"
check "no sed, awk, grep, curl or wget in the Firewall code" bash -c '! grep -qE "(^|[|;&( ])(sed|awk|grep|curl|wget)[ ]" <<<"$1"' _ "$FWCODE"
check "every backend command goes through fw_run (no bare invocation)" bash -c '! grep -qE "^[[:space:]]*(ufw|nft|iptables|firewall-cmd)[[:space:]]+[^|)]" <<<"$1"' _ "$FWCODE"
check "a single rule is removed per call (no loop around fw_do_remove)" equals "$(printf '%s\n' "$FWCODE" | grep -c 'fw_do_remove "\$idx"')" 1
check "list and status code never call the changing functions" bash -c '! grep -qE "fw_do_add|fw_do_remove|fw_backup_rules" <<<"$1"' _ "$(fw_fn fw_list_rules; fw_fn fw_show_status)"
check "the changing flows check root, system and backend first" bash -c 'grep -q "require_root" <<<"$1" && grep -q "require_supported_os \"Firewall\"" <<<"$1" && grep -q "fw_need_backend" <<<"$1"' _ "$(fw_fn fw_change_preflight)"
check "allow and remove both start with the preflight" bash -c 'grep -q "fw_change_preflight || return 1" <<<"$1" && grep -q "fw_change_preflight || return 1" <<<"$2"' _ "$(fw_fn fw_allow_port)" "$(fw_fn fw_remove_rule)"
check "backend output is parsed in the C locale" contains "$(fw_fn fw_run)" "LC_ALL=C"
check "only the documented ufw commands are used" bash -c 'bad="$(grep -oE "fw_run ufw [a-z-]+( [a-z-]+)?" <<<"$1" | LC_ALL=C sort -u | tr "\n" ";")"; [[ "$bad" == "fw_run ufw --force delete;fw_run ufw allow;fw_run ufw app info;fw_run ufw app list;fw_run ufw status numbered;fw_run ufw status verbose;" ]]' _ "$FWCODE"

FW_ENV=()
export EZVPS_NO_PAUSE="${FW_SAVED_PAUSE:-0}"
[[ -z "$FW_SAVED_PAUSE" ]] && unset EZVPS_NO_PAUSE

echo "== source rules"
# curl may appear only in the 3x-ui functions that need it; never in the L2TP
# path, the menu or the main script body.
curl_functions() {
    awk '/^[A-Za-z_0-9]+\(\) \{/ {fn=$1} /^}/ {fn=""} !/^[[:space:]]*#/ && /(^|[[:space:]($`])(curl|wget)[[:space:]]+-/ {print (fn==""?"<top-level>":fn)}' "$1" | sort -u | tr '\n' ' '
}
no_downloads() { ! grep -vE '^[[:space:]]*#' "$1" | grep -qE 'curl|wget'; }
no_ezl2tp_writes() {
    ! grep -vE '^[[:space:]]*#' "$1" | grep 'ezl2tp' | grep -qE '^[[:space:]]*(cp|mv|rm|install|tee|chmod|chown)[[:space:]]|>>?[[:space:]]*[^/&[:space:]]'
}
no_pipe_to_shell() {
    ! grep -vE '^[[:space:]]*#' "$1" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|da)?sh|(ba)?sh[[:space:]]+<\(|source[[:space:]]+<\(|\.[[:space:]]+<\('
}
only_pinned_urls() {
    # every URL in ezvps is the pinned upstream installer, its project page, or documentation
    local u bad=0
    while read -r u; do
        # shellcheck disable=SC2016 # literal text from the script, not expansions
        case "$u" in
            https://github.com/\$\{XUI_UPSTREAM\}* | https://raw.githubusercontent.com/\$\{XUI_UPSTREAM\}/\$\{XUI_PINNED_TAG\}/install.sh | 'http://127.0.0.1'* | 'http://<server-ip>'* | 'https://github.com/<owner>/'* | 'https://www.shellcheck.net'*) ;;
            # Nginx module: the nginx.org stable repositories (Debian, Ubuntu) and the signing key
            'https://nginx.org/packages/debian' | 'https://nginx.org/packages/ubuntu' | 'https://nginx.org/keys/nginx_signing.key') ;;
            # Certificates module: the pinned acme.sh script at a release tag, and its project page
            'https://github.com/${ACME_UPSTREAM}'* | 'https://raw.githubusercontent.com/${ACME_UPSTREAM}/${ACME_PINNED_TAG}/acme.sh') ;;
            # Backpack / ctunnel / Lazyports: the projects, their pinned installers and the pinned ctunnel commit, and Go's install page (text only)
            'https://github.com/${LC_BACKPACK_REPO}' | 'https://github.com/${LC_CTUNNEL_REPO}' | 'https://github.com/${LC_CTUNNEL_REPO}.git' | 'https://github.com/${LC_LAZYPORTS_REPO}') ;;
            'https://raw.githubusercontent.com/${LC_BACKPACK_REPO}/${LC_BACKPACK_TAG}/install.sh' | 'https://raw.githubusercontent.com/${LC_LAZYPORTS_REPO}/${LC_LAZYPORTS_COMMIT}/install.sh') ;;
            'https://go.dev/doc/install') ;;
            # Certificates module: nginx syntax in the site template and text for the user, not network access
            'https://$host$request_uri;'* | 'https://\$host\$request_uri'* | 'https://${domain}/'* | 'http://${1};') ;;
            # Nginx module: upstream parsing/rendering, not network access
            'https://*' | 'http://}' | 'http://${2};') ;;
            *) echo "unexpected URL: $u" >&2; bad=1 ;;
        esac
    done < <(grep -vE '^[[:space:]]*#' "$1" | grep -oE "https?://[^\"' )]+")
    ((bad == 0))
}
check "curl is invoked only by the 3x-ui download/probe functions, the nginx.org key download, the pinned acme.sh download and the pinned Backpack/Lazyports installer download" equals "$(curl_functions "$EZVPS")" "acme_fetch_script() lc_fetch_installer() ngx_fetch_key() xui_fetch_installer() xui_probe() "
check "ezvps never pipes a download into a shell" no_pipe_to_shell "$EZVPS"
check "ezvps only knows the pinned upstream URL" only_pinned_urls "$EZVPS"
check "ezvps has no URL for the private easyl2tp repo" not_contains "$(<"$EZVPS")" "raw.githubusercontent.com/<owner>"
check "install.sh has no curl/wget" no_downloads "$INSTALL"
check "install.sh never writes to an ezl2tp path" no_ezl2tp_writes "$INSTALL"
check "ezvps never writes to an ezl2tp path" no_ezl2tp_writes "$EZVPS"
lc_body() { awk '/^(lc_[a-z_]+|module_(backpack|ctunnel|lazyports))\(\)/ {on=1} on {print} /^}/ {on=0}' "$EZVPS"; }
git_network_functions() {
    awk '/^[A-Za-z_0-9]+\(\) \{/ {fn=$1} /^}/ {fn=""} !/^[[:space:]]*#/ && /[[:space:]](fetch|clone|pull|ls-remote|submodule)[[:space:]]/ && /"\$\{g\[@\]\}"|git[[:space:]]+-/ {print (fn==""?"<top-level>":fn)}' "$1" | sort -u | tr '\n' ' '
}
reads_outside_menu() { # `read` in lc_* other than the submenu choice and the parsers of a tool's own output
    awk '/^[A-Za-z_0-9]+\(\) \{/ {fn=$1} /^}/ {fn=""} !/^[[:space:]]*#/ && /(^|[[:space:];])read[[:space:]]+-/ && fn ~ /^lc_/ && fn != "lc_module()" && fn != "lc_version()" && fn != "lc_print_services()" {print fn": "$0}' "$EZVPS"
}
check "git fetches only inside lc_fetch_source (the pinned ctunnel commit)" equals "$(git_network_functions "$EZVPS")" "lc_fetch_source() "
check "the ctunnel fetch allows https only" contains "$(<"$EZVPS")" "-c protocol.allow=never -c protocol.https.allow=always"
check "the upstream installer runs with /dev/null as input (it must not open the tool)" contains "$(<"$EZVPS")" 'bash "${tmp}/install.sh" </dev/null'
check "the lifecycle code asks for no token, link, password or key (no read outside the submenu and the yes/no helper)" equals "$(reads_outside_menu)" ""
check "the lifecycle code never launches a tool with tunnel arguments" not_contains "$(lc_body | grep -E '"\$LC_BIN_FOUND"|\$1" "\$LC_VERSION_ARG"')" "-s "
check "one shared submenu: the four labels are declared once" equals "$(grep -c '"Install" "Status" "Update" "Uninstall"' "$EZVPS")" 1
check "the three module functions are one-line wrappers around the shared flow" equals "$(grep -cE '^module_(backpack|ctunnel|lazyports)\(\) \{ lc_module (backpack|ctunnel|lazyports); \}$' "$EZVPS")" 3
check "Backpack and Lazyports installers are pinned (no main/master/HEAD in their URLs)" not_contains "$(grep -E '^[[:space:]]*LC_URL=' "$EZVPS")" "/main/"
module_l2tp_body="$(awk '/^module_l2tp\(\)/,/^}/' "$EZVPS")"
check "the L2TP module still has no download code" no_downloads <(printf '%s\n' "$module_l2tp_body")

echo "== install.sh"
IBIN="$WORK/inst/bin"
IBAK="$WORK/inst/backup"
run_install() {
    OUT="$(EZVPS_BIN_DIR="$IBIN" EZVPS_BACKUP_DIR="$IBAK" "$BASH_BIN" "$INSTALL" 2>&1)"
    RC=$?
}
installed_runs() { [[ "$("$IBIN/ezvps" --version)" == "ezvps "* ]]; }
one_backup_has_marker() {
    [[ "$(find "$IBAK" -type f | wc -l)" -eq 1 ]] && grep -q 'locally modified' "$IBAK"/ezvps.*
}
no_temp_files() { [[ -z "$(find "$IBIN" -maxdepth 1 -name '.ezvps.*')" ]]; }
file_sum() { cksum <"$1"; }

# A pre-existing (fake) ezl2tp install must survive every install.
mkdir -p "$IBIN"
printf '#!/bin/sh\necho fake-existing-ezl2tp\n' >"$IBIN/ezl2tp"
chmod 0755 "$IBIN/ezl2tp"
EZL2TP_SUM="$(file_sum "$IBIN/ezl2tp")"
EZL2TP_MODE="$(stat -c %a "$IBIN/ezl2tp")"

run_install
check "fresh install exits 0" equals "$RC" 0
check "fresh install creates executable ezvps" test -x "$IBIN/ezvps"
check "installed copy matches source" cmp -s "$EZVPS" "$IBIN/ezvps"
check "installed ezvps runs" installed_runs
check "reports existing ezl2tp left untouched" contains "$OUT" "ezl2tp found; left untouched"
check "fresh install makes no backup" dir_empty_or_missing "$IBAK"

run_install
check "re-run exits 0" equals "$RC" 0
check "re-run is a no-op (up to date)" contains "$OUT" "already up to date"
check "re-run makes no backup" dir_empty_or_missing "$IBAK"

printf '# locally modified\n' >>"$IBIN/ezvps"
run_install
check "changed install exits 0" equals "$RC" 0
check "changed install is restored from source" cmp -s "$EZVPS" "$IBIN/ezvps"
check "changed install backed up the old file first" one_backup_has_marker

check "ezl2tp content unchanged by installs" equals "$(file_sum "$IBIN/ezl2tp")" "$EZL2TP_SUM"
check "ezl2tp mode unchanged by installs" equals "$(stat -c %a "$IBIN/ezl2tp")" "$EZL2TP_MODE"
check "no temp files left behind" no_temp_files

# Without ezl2tp the installer still succeeds.
rm -f "$IBIN/ezl2tp"
OUT="$(PATH="$EMPTY_BIN:/usr/bin:/bin" EZVPS_BIN_DIR="$IBIN" EZVPS_BACKUP_DIR="$IBAK" "$BASH_BIN" "$INSTALL" 2>&1)"
RC=$?
check "install without ezl2tp exits 0" equals "$RC" 0
check "install without ezl2tp says so" contains "$OUT" "ezl2tp not found"

# A broken source must be refused and must not replace the installed file.
BROKEN="$WORK/broken-ezvps"
printf 'if then\n' >"$BROKEN"
BEFORE="$(file_sum "$IBIN/ezvps")"
OUT="$(EZVPS_SOURCE="$BROKEN" EZVPS_BIN_DIR="$IBIN" EZVPS_BACKUP_DIR="$IBAK" "$BASH_BIN" "$INSTALL" 2>&1)"
RC=$?
check "syntax-broken source is refused" test "$RC" -ne 0
check "installed file untouched after refused install" equals "$(file_sum "$IBIN/ezvps")" "$BEFORE"

# The installer applies the same rule as ezvps: the five supported systems, nothing else.
echo "-- install.sh: operating systems (fake os-release, check on)"
os_install() { # os_install <os-release file> -> OUT / RC; installs into a fresh dir
    OSBIN="$WORK/inst-os/$(basename "$1")/bin"
    rm -rf "$WORK/inst-os/$(basename "$1")"
    OUT="$(env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$1" EZVPS_BIN_DIR="$OSBIN" EZVPS_BACKUP_DIR="$WORK/inst-os/$(basename "$1")/backup" "$BASH_BIN" "$INSTALL" 2>&1)"
    RC=$?
}
for c in "${OS_CASES[@]}"; do
    IFS=: read -r f ok found mism <<<"$c"
    os_install "$OSD/$f"
    if [[ "$ok" == yes ]]; then
        check "install.sh accepts ${f}" equals "$RC" 0
        check "install.sh on ${f}: ezvps is installed" test -x "$OSBIN/ezvps"
    else
        check "install.sh refuses ${f}" test "$RC" -ne 0
        check "install.sh refusal on ${f} is the shared message" contains "$OUT" "ezvps install needs a supported system: ${OS_LIST_TEXT}; found '${found}'"
        [[ -n "$mism" ]] && check "install.sh refusal on ${f} names the codename mismatch" contains "$OUT" "the codename does not match the version"
        check "install.sh on ${f}: nothing installed" test ! -e "$OSBIN/ezvps"
    fi
done

echo
printf '%d passed, %d failed\n' "$PASS" "$FAILS"
exit $((FAILS > 0))
