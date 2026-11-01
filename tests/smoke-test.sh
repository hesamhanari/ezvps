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
trap 'rm -rf "$WORK"' EXIT

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
    [[ "${KEYS[$i]}" == "l2tp" || "${KEYS[$i]}" == "3x-ui" ]] && continue
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
for c in bash cp mkdir mv rm rmdir mktemp date chmod; do
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
verb="${1:-}"
case "$verb" in
    is-active)
        [[ -f "$FAKE_SVC" && "$(<"$FAKE_SVC")" == "active" ]] && exit 0
        exit 3 ;;
    is-enabled) [[ -f "$FAKE_SVC" ]] && { echo enabled; exit 0; }; exit 1 ;;
    list-unit-files) [[ -f "$FAKE_SVC" ]] && echo "x-ui.service enabled enabled"; exit 0 ;;
    restart | start)
        echo "systemctl $*" >>"$FAKE_LOG"
        [[ "${FAKE_RESTART_FAIL:-0}" == "1" ]] && exit 1
        echo active >"$FAKE_SVC"
        exit 0 ;;
    *) echo "systemctl UNEXPECTED $*" >>"$FAKE_LOG"; exit 0 ;;
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
exit 0
EOF

for c in systemctl curl sha256sum ss apt-get hostname; do ln -s "$STUBS/$c" "$SBOX/$c"; done
ln -s "$STUBS/apt-get" "$SBOX_NOCURL/apt-get"
for c in systemctl sha256sum ss; do ln -s "$STUBS/$c" "$SBOX_NOCURL/$c"; done
for c in "$CORE_BIN"/*; do
    ln -s "$c" "$SBOX/${c##*/}"
    ln -s "$c" "$SBOX_NOCURL/${c##*/}"
done
export WORK_FAKE_INSTALLER="$WORK/fake-installer.sh" FAKE_XUI_TEMPLATE="$WORK/fake-xui"
export STUBS_DIR="$STUBS" SBOX_NOCURL_DIR="$SBOX_NOCURL"
export EZVPS_XUI_WAIT_SECONDS=0

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
        case "$u" in
            https://github.com/\$\{XUI_UPSTREAM\}* | https://raw.githubusercontent.com/\$\{XUI_UPSTREAM\}/\$\{XUI_PINNED_TAG\}/install.sh | 'http://127.0.0.1'* | 'http://<server-ip>'* | 'https://github.com/<owner>/'* | 'https://www.shellcheck.net'*) ;;
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
