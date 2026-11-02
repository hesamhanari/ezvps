#!/usr/bin/env bash
# Smoke test for ezvps and install.sh. Safe to run anywhere: it never touches
# /usr/local/bin, /var/backups or a real ezl2tp. All data is fake.
#   bash tests/smoke-test.sh

# Helpers are invoked indirectly through `check`.
# shellcheck disable=SC2329,SC2317

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
    [[ "${KEYS[$i]}" == "l2tp" || "${KEYS[$i]}" == "3x-ui" || "${KEYS[$i]}" == "nginx" ]] && continue
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

# fake nginx: `-t` fails if an enabled site contains BROKEN_DIRECTIVE, if an
# enabled file is named $FAKE_NGX_FAIL_DOMAIN, or always when FAKE_NGX_TEST_FAIL=1
mkstub "$STUBS/nginx" <<'EOF'
case "${1:-}" in
    -v)
        echo "nginx version: nginx/1.26.3" >&2
        exit 0 ;;
    -t)
        echo "nginx -t" >>"$FAKE_LOG"
        bad=""
        [[ "${FAKE_NGX_TEST_FAIL:-0}" == "1" ]] && bad="forced failure"
        if [[ -n "${FAKE_NGX_FAIL_DOMAIN:-}" && -e "$EZVPS_NGINX_DIR/sites-enabled/$FAKE_NGX_FAIL_DOMAIN" ]]; then
            bad="$FAKE_NGX_FAIL_DOMAIN"
        fi
        for f in "$EZVPS_NGINX_DIR"/sites-enabled/*; do
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

mkstub "$STUBS/dpkg-query" <<'EOF'
printf 'ii '
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
if [[ "$*" == *"install"* && "$*" == *"curl"* ]]; then
    cp "$STUBS_DIR/curl" "$SBOX_NOCURL_DIR/curl"
fi
if [[ "$*" == *"install"* && "$*" == *"nginx"* ]]; then
    [[ "${FAKE_APT_FAIL:-0}" == "1" ]] && exit 100
    cp "$STUBS_DIR/nginx" "$NGX_BOX_DIR/nginx"
    mkdir -p "$EZVPS_NGINX_DIR/sites-available" "$EZVPS_NGINX_DIR/sites-enabled"
    [[ "${FAKE_NGX_NOSTART:-0}" == "1" ]] || echo active >"$FAKE_NGX_SVC"
fi
exit 0
EOF

for c in systemctl curl sha256sum ss apt-get hostname; do ln -s "$STUBS/$c" "$SBOX/$c"; done
ln -s "$STUBS/apt-get" "$SBOX_NOCURL/apt-get"
for c in systemctl sha256sum ss; do ln -s "$STUBS/$c" "$SBOX_NOCURL/$c"; done
# Nginx sandboxes: NGX_BOX has no nginx (apt-get stub "installs" it), NGX_BOX_INST
# has it, NGX_BOX_DPKG has only a dpkg-query stub that says the package is installed.
NGX_BOX="$WORK/ngx-box"
NGX_BOX_INST="$WORK/ngx-box-inst"
NGX_BOX_DPKG="$WORK/ngx-box-dpkg"
mkdir -p "$NGX_BOX" "$NGX_BOX_INST" "$NGX_BOX_DPKG"
for c in systemctl ss apt-get; do
    ln -s "$STUBS/$c" "$NGX_BOX/$c"
    ln -s "$STUBS/$c" "$NGX_BOX_INST/$c"
    ln -s "$STUBS/$c" "$NGX_BOX_DPKG/$c"
done
ln -s "$STUBS/nginx" "$NGX_BOX_INST/nginx"
ln -s "$STUBS/dpkg-query" "$NGX_BOX_DPKG/dpkg-query"
for c in "$CORE_BIN"/*; do
    ln -s "$c" "$SBOX/${c##*/}"
    ln -s "$c" "$SBOX_NOCURL/${c##*/}"
    ln -s "$c" "$NGX_BOX/${c##*/}"
    ln -s "$c" "$NGX_BOX_INST/${c##*/}"
    ln -s "$c" "$NGX_BOX_DPKG/${c##*/}"
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
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$SCN/os-ubuntu"
printf 'PRETTY_NAME="Debian GNU/Linux 13 (trixie)"\nID=debian\nVERSION_ID="13"\n' >"$SCN/os-debian13"
OUT="$(printf '2\n1\n\n0\n\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$SCN/os-ubuntu" PATH="$SBOX" "$BASH_BIN" "$EZVPS" 2>&1)"
RC=$?
check "non-Debian-13 is refused" contains "$OUT" "needs Debian 13"
check "non-Debian-13: nothing downloaded" no_download
check "non-Debian-13: menu survives" equals "$RC" 0
OUT="$(printf '2\n1\nn\n\n0\n\n0\n' | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$SCN/os-debian13" PATH="$SBOX" "$BASH_BIN" "$EZVPS" 2>&1)"
check "Debian 13 passes the OS check" contains "$OUT" "will download the official 3x-ui installer"
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

# new_ngx <name>: a fresh fake machine without nginx
new_ngx() {
    new_scn "ngx-$1"
    export EZVPS_NGINX_DIR="$SCN/etc-nginx" FAKE_NGX_SVC="$SCN/ngx-svc"
    export EZVPS_NGINX_HTTP_PORT="$PORT_UP" EZVPS_NGINX_WAIT_SECONDS=0
    export FAKE_NGX_FAIL_DOMAIN="" FAKE_NGX_TEST_FAIL=0 FAKE_NGX_NOSTART=0 FAKE_APT_FAIL=0
    export FAKE_NGX_RESTART_FAIL=0 FAKE_NGX_RELOAD_FAIL=0
    rm -f "$NGX_BOX/nginx"
}
ngx_layout() { mkdir -p "$EZVPS_NGINX_DIR/sites-available" "$EZVPS_NGINX_DIR/sites-enabled"; }
ngx_up() { ngx_layout && echo active >"$FAKE_NGX_SVC"; }
ngx_down() { ngx_layout && echo inactive >"$FAKE_NGX_SVC"; }
AV() { printf '%s' "$EZVPS_NGINX_DIR/sites-available/$1"; }
EN() { printf '%s' "$EZVPS_NGINX_DIR/sites-enabled/$1"; }
# fixtures written independently of the module's own renderer
mk_ezvps_site() { # mk_ezvps_site <domain> <upstream>
    printf '%s\n' "# Managed by ezvps (Nginx module). fixture" "# ezvps:domain=$1" "# ezvps:upstream=$2" \
        "server {" "    listen 80;" "    server_name $1;" "    location / { proxy_pass http://$2; }" "}" >"$(AV "$1")"
    ln -s "$(AV "$1")" "$(EN "$1")"
}
mk_foreign_site() { # mk_foreign_site <file-name> <server_name> [enable 1|0]
    printf '%s\n' "server {" "    listen 80;" "    server_name $2;" "    return 200 'hand written';" "}" >"$(AV "$1")"
    [[ "${3:-1}" == "1" ]] && ln -s "$(AV "$1")" "$(EN "$1")"
    return 0
}
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

echo "-- install: detection of an existing nginx"
new_ngx inst_have
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}1\n\n0\n\n0\n"
check "installed nginx is detected" contains "$OUT" "Nginx is already installed (nginx/1.26.3)"
check "installed nginx is not reinstalled" contains "$OUT" "Not reinstalling"
check "installed nginx: apt-get is never called" no_apt
check "installed nginx: nothing is enabled/started/restarted" no_mutation
check "installed nginx: status is reported instead" contains "$OUT" "Nginx status"
check "installed nginx: exit 0" equals "$RC" 0
new_ngx inst_dpkg
run_ezvps "$NGX_BOX_DPKG" "${N}1\n\n0\n\n0\n"
check "package known to dpkg counts as installed" contains "$OUT" "Not reinstalling"
check "dpkg-detected nginx: apt-get is never called" no_apt
check "dpkg-detected nginx without the command is explained" contains "$OUT" "not in PATH"

echo "-- install: fresh machine"
new_ngx inst_new
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "installs from apt (update first)" contains "$(log)" "apt-get update -q"
check "installs the nginx package non-interactively" has_line "$(log)" "apt-get install -y -q nginx"
check "enables and starts the service" has_line "$(log)" "systemctl enable --now nginx"
check "runs the config test" contains "$(log)" "nginx -t"
check "service ends up running" equals "$(<"$FAKE_NGX_SVC")" active
check_py "verifies that nginx responds" contains "$OUT" "Verified: nginx answers on 127.0.0.1:${PORT_UP} (HTTP 200)"
check "says it is HTTP only and defers HTTPS to Certificates" contains "$OUT" "Certificates module"
check "does not touch the firewall" contains "$OUT" "firewall is not changed"
check "fresh install exits 0" equals "$RC" 0
new_ngx inst_nostart
FAKE_NGX_NOSTART=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a package that does not auto-start is started by enable --now" equals "$(<"$FAKE_NGX_SVC")" active
new_ngx inst_no
run_ezvps "$NGX_BOX" "${N}1\nn\n\n0\n\n0\n"
check "declining the install changes nothing" contains "$OUT" "Cancelled. Nothing was changed."
check "declined: apt-get never called" no_apt
check "declined: exit 0" equals "$RC" 0
new_ngx inst_deb
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$SCN/os-ubuntu"
OUT="$(printf '%b' "${N}1\ny\n\n0\n\n0\n" | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$SCN/os-ubuntu" PATH="$NGX_BOX" "$BASH_BIN" "$EZVPS" 2>&1)"
RC=$?
check "non-Debian-13 is refused" contains "$OUT" "Nginx install needs Debian 13"
check "non-Debian-13: apt-get never called" no_apt
check "non-Debian-13: menu survives" equals "$RC" 0
new_ngx inst_aptfail
FAKE_APT_FAIL=1
run_ezvps "$NGX_BOX" "${N}1\ny\n\n0\n\n0\n"
check "a failed apt install is reported" contains "$OUT" "still not available"
check "a failed apt install: nothing enabled" no_mutation
check "a failed apt install: menu survives" equals "$RC" 0

echo "-- install: port 80 busy"
new_ngx inst_busy
FAKE_LISTEN="$PORT_UP"
run_ezvps "$NGX_BOX" "${N}1\nn\n\n0\n\n0\n"
check "busy port is warned about" contains "$OUT" "Port ${PORT_UP} is already in use by another service"
check "busy port: the listener is shown" contains "$OUT" "LISTEN 0 4096 0.0.0.0:${PORT_UP}"
check "busy port: declining installs nothing" no_apt
run_ezvps "$NGX_BOX" "${N}1\ny\ny\n\n0\n\n0\n"
check "busy port: the user may install anyway" has_line "$(log)" "apt-get install -y -q nginx"
new_ngx inst_free
FAKE_LISTEN=""
run_ezvps "$NGX_BOX" "${N}1\nn\n\n0\n\n0\n"
check "free port: no port warning" not_contains "$OUT" "already in use"

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
check "status: version" contains "$OUT" "nginx/1.26.3"
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
echo "    BROKEN_DIRECTIVE on;" >>"$(AV broken.example.com)"
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
echo "    BROKEN_DIRECTIVE on;" >>"$(AV broken.example.com)"
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
mk_foreign_site default _
mk_foreign_site spare.example.com spare.example.com 0
ln -s "$SCN/does-not-exist" "$(EN dangling.example.com)"
run_ezvps "$NGX_BOX_INST" "${N}4\n\n0\n\n0\n"
check "list: header" contains "$OUT" "Enabled sites"
check "list: ezvps site shows domain and upstream" has_row "$OUT" '^  example\.com +example\.com +127\.0\.0\.1:3000 +ezvps$'
check "list: second ezvps site" has_row "$OUT" '^  api\.example\.com +api\.example\.com +127\.0\.0\.1:8080 +ezvps$'
check "list: other site shows its server_name, no upstream" has_row "$OUT" '^  legacy +old\.example\.org +- +not ezvps$'
check "list: Debian default site" has_row "$OUT" '^  default +_ +- +not ezvps$'
check "list: broken symlink is flagged" has_row "$OUT" 'dangling\.example\.com .*broken symlink'
check "list: disabled sites are listed separately" contains "$OUT" "Available but not enabled: spare.example.com"
check "list: a disabled site is not in the enabled table" not_contains "$(printf '%s\n' "$OUT" | grep -E '^  spare')" "spare"
check "list changes nothing" no_mutation
check "list: exit 0" equals "$RC" 0

echo "-- add site"
new_ngx add
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}5\nExample.COM\n127.0.0.1:3000\n\n0\n\n0\n"
A="$(AV example.com)"
E="$(EN example.com)"
check "add: site file created in sites-available (domain lower-cased)" test -f "$A"
check "add: enabled by a symlink in sites-enabled" test "$(readlink "$E")" = "$A"
check "add: marker with the domain" file_has "$A" "# ezvps:domain=example.com"
check "add: marker with the upstream" file_has "$A" "# ezvps:upstream=127.0.0.1:3000"
check "add: server_name" file_has "$A" "    server_name example.com;"
check "add: reverse proxy to the upstream" file_has "$A" "        proxy_pass http://127.0.0.1:3000;"
# shellcheck disable=SC2016 # $host is a literal nginx variable
check "add: forwards the Host header" file_has "$A" '        proxy_set_header Host $host;'
check "add: HTTP only (listens on 80)" file_has "$A" "    listen 80;"
check "add: IPv6 listener only when the kernel has IPv6 (not here)" file_lacks "$A" "[::]:80"
check "add: no TLS directives in the file" file_lacks "$A" "ssl"
check "add: no port 443 in the file" file_lacks "$A" "443"
check "add: config test ran" equals "$(nlog_count '^nginx -t$')" 1
check "add: config test ran BEFORE the reload" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "add: nginx reloaded once" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "add: no restart" equals "$(nlog_count '^systemctl restart')" 0
check "add: tells the user to use Certificates for HTTPS" contains "$OUT" "use the Certificates module once it"
check "add: says HTTP only" contains "$OUT" "HTTP only"
check "add: warns that nothing listens on the upstream yet" contains "$OUT" "Nothing is listening on 127.0.0.1:3000"
check "add: nothing existed, so no backup" equals "$(ngx_backups example.com)" 0
check "add: exit 0" equals "$RC" 0
SUM="$(file_sum "$A")"

echo "-- add site: no duplicates"
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "add again: recognised as existing" contains "$OUT" "already exists with the same upstream"
check "add again: file unchanged" equals "$(file_sum "$A")" "$SUM"
check "add again: still a single site file" equals "$(find "$EZVPS_NGINX_DIR/sites-available" -type f | wc -l)" 1
check "add again: still a single enabled entry" equals "$(find "$EZVPS_NGINX_DIR/sites-enabled" -mindepth 1 | wc -l)" 1
check "add again: no second reload" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "add again: no backup" equals "$(ngx_backups example.com)" 0
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:4000\nn\n\n0\n\n0\n"
check "different upstream: finds the existing site and asks before overwriting" contains "$OUT" "A site for example.com already exists"
check "different upstream, declined: cancelled" contains "$OUT" "Cancelled. Nothing was changed."
check "different upstream, declined: file unchanged" equals "$(file_sum "$A")" "$SUM"
check "different upstream, declined: no backup" equals "$(ngx_backups example.com)" 0
check "different upstream, declined: no reload" equals "$(nlog_count '^systemctl reload nginx$')" 1
run_ezvps "$NGX_BOX_INST" "${N}5\nexample.com\n127.0.0.1:4000\ny\n\n0\n\n0\n"
check "overwrite confirmed: new upstream written" file_has "$A" "# ezvps:upstream=127.0.0.1:4000"
check "overwrite confirmed: proxy_pass updated" file_has "$A" "        proxy_pass http://127.0.0.1:4000;"
check "overwrite confirmed: old file backed up first" equals "$(ngx_backups example.com)" 1
check "overwrite confirmed: backup holds the OLD upstream" file_has "$(ngx_backup_file example.com)" "# ezvps:upstream=127.0.0.1:3000"
check "overwrite confirmed: backup dir is mode 700" equals "$(stat -c %a "$EZVPS_BACKUP_DIR")" 700
check "overwrite confirmed: reloaded after the test" equals "$(nlog_count '^systemctl reload nginx$')" 2
check "overwrite confirmed: still a single site file and link" equals "$(find "$EZVPS_NGINX_DIR" -type f -o -type l | wc -l)" 2

echo "-- add site: IPv6 listener follows the kernel"
new_ngx add_v6
ngx_up
: >"$SCN/if_inet6"
EZVPS_IF_INET6_FILE="$SCN/if_inet6" run_ezvps "$NGX_BOX_INST" "${N}5\nv6.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "add: IPv6 listener written when IPv6 exists" file_has "$(AV v6.example.com)" "    listen [::]:80;"
check "add: IPv4 listener always written" file_has "$(AV v6.example.com)" "    listen 80;"

echo "-- add site: input validation"
new_ngx add_bad
ngx_up
for bad in "not a domain" "exam ple.com" "localhost" "-bad.example.com" "a..example.com" "exa_mple.com" "../etc/passwd" "example.com/x"; do
    run_ezvps "$NGX_BOX_INST" "${N}5\n${bad}\n127.0.0.1:3000\n\n0\n\n0\n"
    check "invalid domain '${bad}' is rejected" contains "$OUT" "is not a valid domain name"
done
for bad in "127.0.0.1" "127.0.0.1:0" "127.0.0.1:99999" "192.0.2.256:80" "https://127.0.0.1:443" "host name:80" ":80" "127.0.0.1:80x"; do
    run_ezvps "$NGX_BOX_INST" "${N}5\nok.example.com\n${bad}\n\n0\n\n0\n"
    check "invalid upstream '${bad}' is rejected" equals "$([[ "$OUT" == *"Upstream must look like"* || "$OUT" == *"Not a valid"* || "$OUT" == *"Port must be"* || "$OUT" == *"plain http upstreams"* ]] && echo yes)" yes
done
check "invalid input created no files" equals "$(find "$EZVPS_NGINX_DIR" -type f -o -type l | wc -l)" 0
check "invalid input reloaded nothing" no_mutation
check "invalid input ran no config test" equals "$(nlog_count '^nginx -t$')" 0
run_ezvps "$NGX_BOX_INST" "${N}5\n\n\n0\n\n0\n"
check "empty domain cancels" contains "$OUT" "Cancelled. Nothing was changed."
new_ngx add_forms
ngx_up
run_ezvps "$NGX_BOX_INST" "${N}5\na.example.com\nhttp://localhost:8080/\n\n0\n\n0\n"
check "upstream with http:// and trailing slash is normalised" file_has "$(AV a.example.com)" "# ezvps:upstream=localhost:8080"
run_ezvps "$NGX_BOX_INST" "${N}5\nb.example.com\n[::1]:3000\n\n0\n\n0\n"
check "IPv6 upstream is accepted" file_has "$(AV b.example.com)" "# ezvps:upstream=[::1]:3000"
run_ezvps "$NGX_BOX_INST" "${N}5\nc.example.com\nbackend.internal:9000\n\n0\n\n0\n"
check "hostname upstream is accepted" file_has "$(AV c.example.com)" "        proxy_pass http://backend.internal:9000;"
run_ezvps "$NGX_BOX_INST" "${N}5\nxn--bcher-kva.example\n192.0.2.5:0080\n\n0\n\n0\n"
check "punycode domain and leading-zero port are accepted and normalised" file_has "$(AV xn--bcher-kva.example)" "# ezvps:upstream=192.0.2.5:80"

echo "-- add site: conflicts, foreign files, failing config test"
new_ngx add_conf
ngx_up
mk_foreign_site legacy taken.example.com
run_ezvps "$NGX_BOX_INST" "${N}5\ntaken.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "domain served by another enabled file is refused" contains "$OUT" "already served by another enabled site file: legacy"
check "conflict: no new site file" test ! -e "$(AV taken.example.com)"
check "conflict: nothing reloaded" no_mutation
new_ngx add_foreign
ngx_up
mk_foreign_site hand.example.com hand.example.com
cp "$(AV hand.example.com)" "$SCN/hand-original"
run_ezvps "$NGX_BOX_INST" "${N}5\nhand.example.com\n127.0.0.1:3000\ny\n\n0\n\n0\n"
check "existing hand-written file for the domain: asks first" contains "$OUT" "NOT created by ezvps"
check "existing hand-written file: backed up before overwrite" cmp -s "$SCN/hand-original" "$(ngx_backup_file hand.example.com)"
check "existing hand-written file: replaced by the ezvps site" file_has "$(AV hand.example.com)" "# ezvps:domain=hand.example.com"
new_ngx add_rb
ngx_up
FAKE_NGX_FAIL_DOMAIN="bad.example.com"
run_ezvps "$NGX_BOX_INST" "${N}5\nbad.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "failing config test is reported" contains "$OUT" "config test FAILED after adding bad.example.com"
check "failing config test: nginx is NOT reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "failing config test: no restart either" equals "$(nlog_count '^systemctl restart')" 0
check "failing config test: new site file rolled back" test ! -e "$(AV bad.example.com)"
check "failing config test: new symlink rolled back" test ! -L "$(EN bad.example.com)"
check "failing config test: says it rolled back" contains "$OUT" "Rolled back"
check "failing config test: menu survives" equals "$RC" 0
new_ngx add_rb2
ngx_up
mk_ezvps_site bad.example.com 127.0.0.1:3000
SUM="$(file_sum "$(AV bad.example.com)")"
FAKE_NGX_FAIL_DOMAIN="bad.example.com"
run_ezvps "$NGX_BOX_INST" "${N}5\nbad.example.com\n127.0.0.1:4000\ny\n\n0\n\n0\n"
check "failed overwrite: previous file restored byte for byte" equals "$(file_sum "$(AV bad.example.com)")" "$SUM"
check "failed overwrite: previous symlink restored" test "$(readlink "$(EN bad.example.com)")" = "$(AV bad.example.com)"
check "failed overwrite: not reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "failed overwrite: backup was taken first" equals "$(ngx_backups bad.example.com)" 1
new_ngx add_none
run_ezvps "$NGX_BOX" "${N}5\n\n0\n\n0\n"
check "add: nginx not installed" contains "$OUT" "Nginx is not installed."
new_ngx add_stopped
ngx_down
run_ezvps "$NGX_BOX_INST" "${N}5\nidle.example.com\n127.0.0.1:3000\n\n0\n\n0\n"
check "add while nginx is stopped: site is written" test -f "$(AV idle.example.com)"
check "add while nginx is stopped: nothing is reloaded or started" no_mutation
check "add while nginx is stopped: user is told" contains "$OUT" "nginx is not running, so nothing was reloaded"

echo "-- remove site"
new_ngx rm
ngx_up
mk_ezvps_site gone.example.com 127.0.0.1:3000
mk_ezvps_site keep.example.com 127.0.0.1:3001
cp "$(AV gone.example.com)" "$SCN/gone-original"
run_ezvps "$NGX_BOX_INST" "${N}6\nnothere.example.com\n\n0\n\n0\n"
check "remove: unknown site" contains "$OUT" "No site named nothere.example.com"
check "remove: unknown site changes nothing" no_mutation
run_ezvps "$NGX_BOX_INST" "${N}6\ngone.example.com\nn\n\n0\n\n0\n"
check "remove: shows the site and asks for confirmation" contains "$OUT" "Site gone.example.com:"
check "remove: declining is reported" contains "$OUT" "Cancelled. Nothing was changed."
check "remove: declined, site file kept" test -f "$(AV gone.example.com)"
check "remove: declined, symlink kept" test -L "$(EN gone.example.com)"
check "remove: declined, no backup" equals "$(ngx_backups gone.example.com)" 0
check "remove: declined, nothing reloaded" no_mutation
run_ezvps "$NGX_BOX_INST" "${N}6\nGONE.example.com\ny\n\n0\n\n0\n"
check "remove: site file removed" test ! -e "$(AV gone.example.com)"
check "remove: symlink removed" test ! -L "$(EN gone.example.com)"
check "remove: backup kept and identical to the original" cmp -s "$SCN/gone-original" "$(ngx_backup_file gone.example.com)"
check "remove: exactly one backup" equals "$(ngx_backups gone.example.com)" 1
check "remove: config test ran after the removal" equals "$(nlog_count '^nginx -t$')" 1
check "remove: test before reload" runs_before '^nginx -t$' '^systemctl reload nginx$'
check "remove: reloaded once" equals "$(nlog_count '^systemctl reload nginx$')" 1
check "remove: other sites untouched" test -L "$(EN keep.example.com)"
check "remove: says so" contains "$OUT" "disabled and removed"
new_ngx rm_fail
ngx_up
mk_ezvps_site gone.example.com 127.0.0.1:3000
SUM="$(file_sum "$(AV gone.example.com)")"
FAKE_NGX_TEST_FAIL=1
run_ezvps "$NGX_BOX_INST" "${N}6\ngone.example.com\ny\n\n0\n\n0\n"
check "remove, failing config test: reported" contains "$OUT" "config test FAILED after removing gone.example.com"
check "remove, failing config test: NOT reloaded" equals "$(nlog_count '^systemctl reload')" 0
check "remove, failing config test: site restored" equals "$(file_sum "$(AV gone.example.com)")" "$SUM"
check "remove, failing config test: symlink restored" test "$(readlink "$(EN gone.example.com)")" = "$(AV gone.example.com)"
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
check "remove: invalid domain rejected" contains "$OUT" "is not a valid domain name"
new_ngx rm_none
run_ezvps "$NGX_BOX" "${N}6\n\n0\n\n0\n"
check "remove: nginx not installed" contains "$OUT" "Nginx is not installed."

echo "-- Nginx stays HTTP only"
no_tls_code() { ! grep -vE '^[[:space:]]*#' "$1" | grep -qiE 'ssl_certificate|certbot|acme\.sh|letsencrypt|listen 443|443 ssl'; }
check "ezvps contains no certificate/TLS configuration code" no_tls_code "$EZVPS"

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
            # Nginx module: upstream parsing/rendering, not network access
            'https://*' | 'http://}' | 'http://${2};') ;;
            *) echo "unexpected URL: $u" >&2; bad=1 ;;
        esac
    done < <(grep -vE '^[[:space:]]*#' "$1" | grep -oE "https?://[^\"' )]+")
    ((bad == 0))
}
check "curl is invoked only by the 3x-ui download and probe functions" equals "$(curl_functions "$EZVPS")" "xui_fetch_installer() xui_probe() "
check "ezvps never pipes a download into a shell" no_pipe_to_shell "$EZVPS"
check "ezvps only knows the pinned upstream URL" only_pinned_urls "$EZVPS"
check "ezvps has no URL for the private easyl2tp repo" not_contains "$(<"$EZVPS")" "raw.githubusercontent.com/<owner>"
check "install.sh has no curl/wget" no_downloads "$INSTALL"
check "install.sh never writes to an ezl2tp path" no_ezl2tp_writes "$INSTALL"
check "ezvps never writes to an ezl2tp path" no_ezl2tp_writes "$EZVPS"
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

echo
printf '%d passed, %d failed\n' "$PASS" "$FAILS"
exit $((FAILS > 0))
