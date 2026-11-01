#!/usr/bin/env bash
# Smoke test for ezvps and install.sh. Safe to run anywhere: it never touches
# /usr/local/bin, /var/backups or a real ezl2tp. All data is fake.
#   bash tests/smoke-test.sh

# Helpers are invoked indirectly through `check`.
# shellcheck disable=SC2329

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
    [[ "${KEYS[$i]}" == "l2tp" ]] && continue
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

echo "== source rules"
no_downloads() { ! grep -vE '^[[:space:]]*#' "$1" | grep -qE 'curl|wget'; }
no_ezl2tp_writes() {
    ! grep -vE '^[[:space:]]*#' "$1" | grep 'ezl2tp' | grep -qE '^[[:space:]]*(cp|mv|rm|install|tee|chmod|chown)[[:space:]]|>>?[[:space:]]*[^/&[:space:]]'
}
check "ezvps has no curl/wget (no anonymous downloads)" no_downloads "$EZVPS"
check "install.sh has no curl/wget" no_downloads "$INSTALL"
check "install.sh never writes to an ezl2tp path" no_ezl2tp_writes "$INSTALL"

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
