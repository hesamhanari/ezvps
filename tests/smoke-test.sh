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
pinned=0
[[ -f "$EZVPS_APT_DIR/preferences.d/99nginx" && -f "$EZVPS_APT_DIR/sources.list.d/nginx.list" ]] && pinned=1
cand="1.26.3-3+deb13u1"
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
    ver="1.26.3-3+deb13u1"
    pinned=0
    [[ -f "$EZVPS_APT_DIR/preferences.d/99nginx" && -f "$EZVPS_APT_DIR/sources.list.d/nginx.list" ]] && pinned=1
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

# Fixtures: the primary-key fingerprints nginx.org publishes (as the fake gpg reads them),
# and a Debian 13 os-release (codename trixie) for the nginx.org repository line.
printf 'fpr=%s\n' 8540A6F18833A80E9C1653A42FD21310B49F6B46 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3 >"$WORK/nginx-key"
printf '%s\n' 'ID=debian' 'VERSION_ID="13"' 'VERSION_CODENAME=trixie' >"$WORK/os-debian13"
export EZVPS_OS_RELEASE="$WORK/os-debian13"

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
    export FAKE_APT_NOCAND=0 FAKE_APT_UPDATE_FAIL=0 FAKE_PURGE_WIPES_SITES=0 FAKE_PURGE_WIPES_CONFD=0
    export FAKE_NGX_VERSION="1.30.2" FAKE_TOOLS_DIR="$NGX_BOX" NGX_BOX_DIR="$NGX_BOX"
    rm -f "$NGX_BOX/nginx" "$NGX_BOX_NOTOOLS/nginx" "$NGX_BOX_NOTOOLS/curl" "$NGX_BOX_NOTOOLS/gpg"
}
# nginx.conf fixture shaped like Debian's: mk_nginx_conf [1|0] (0 = the conf.d
# include is missing; only a commented-out one remains)
mk_nginx_conf() {
    {
        printf '%s\n' "user www-data;" "events {" "    worker_connections 768;" "}" "http {" "    sendfile on;" "    include $EZVPS_NGINX_DIR/mime.types;"
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
check "a Debian package version after install aborts" contains "$OUT" "still a Debian package version (1.26.3-3+deb13u1)"
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
printf 'ID=ubuntu\nVERSION_ID="24.04"\nVERSION_CODENAME=noble\n' >"$SCN/os-ubuntu"
OUT="$(printf '%b' "${N}1\ny\n\n0\n\n0\n" | env -u EZVPS_SKIP_OS_CHECK EZVPS_OS_RELEASE="$SCN/os-ubuntu" PATH="$NGX_BOX" "$BASH_BIN" "$EZVPS" 2>&1)"
RC=$?
check "non-Debian-13 is refused" contains "$OUT" "Nginx install needs Debian 13"
check "non-Debian-13: apt-get never called" no_apt
check "non-Debian-13: menu survives" equals "$RC" 0
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
check "replace, wrong version installed: aborts" contains "$OUT" "still a Debian package version"
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
check "add: tells the user to use Certificates for HTTPS" contains "$OUT" "use the Certificates module once it"
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
            # Nginx module: the nginx.org stable repository and its signing key
            'https://nginx.org/packages/debian' | 'https://nginx.org/keys/nginx_signing.key') ;;
            # Nginx module: upstream parsing/rendering, not network access
            'https://*' | 'http://}' | 'http://${2};') ;;
            *) echo "unexpected URL: $u" >&2; bad=1 ;;
        esac
    done < <(grep -vE '^[[:space:]]*#' "$1" | grep -oE "https?://[^\"' )]+")
    ((bad == 0))
}
check "curl is invoked only by the 3x-ui download/probe functions and the nginx.org key download" equals "$(curl_functions "$EZVPS")" "ngx_fetch_key() xui_fetch_installer() xui_probe() "
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
