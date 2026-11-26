#!/usr/bin/env bash
# PTY tests for the interactive TUI (tui_select + banner). The smoke test
# only exercises the non-TTY fallback (piped stdin), so arrow keys, number
# jumps and the rendered banner need a real terminal. Needs python3; skips
# cleanly when python3 is not available.
#
# Usage: bash tests/tui-test.sh
set -u
cd "$(dirname "$0")/.." || exit 1

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not found; tui-test needs it for the PTY harness."
    exit 0
fi

python3 - <<'PYEOF'
import os, pty, re, select, signal, struct, sys, termios, time, fcntl

EZVPS = os.path.abspath("ezvps")
passed = failed = 0

def check(name, cond):
    global passed, failed
    if cond:
        passed += 1
        print(f"ok   - {name}")
    else:
        failed += 1
        print(f"FAIL - {name}")

def strip_ansi(b):
    return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", b.decode("utf-8", "replace"))

def run(rows, keys, wait=0.45, cols=80):
    """Run ezvps in a PTY of `rows`x`cols`, send `keys` (bytes), return all output."""
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    pid = os.fork()
    if pid == 0:
        os.setsid()
        os.dup2(slave, 0); os.dup2(slave, 1); os.dup2(slave, 2)
        os.close(master); os.close(slave)
        os.environ["TERM"] = "xterm-256color"
        os.environ["LANG"] = "C.UTF-8"
        os.execv("/bin/bash", ["bash", EZVPS])
    os.close(slave)
    def read_all(timeout):
        out = b""
        end = time.time() + timeout
        while time.time() < end:
            r, _, _ = select.select([master], [], [], 0.2)
            if r:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                out += data
        return out
    out = read_all(1.5)
    for k in keys:
        os.write(master, k)
        time.sleep(wait)
        out += read_all(0.8)
    try:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    except (ProcessLookupError, ChildProcessError):
        pass
    os.close(master)
    return out

# 1. Banner glyphs render, no literal '?' in the banner/menu area.
out = run(40, [])
txt = strip_ansi(out)
banner = txt.split("Main menu")[0]
check("banner has block art, no literal '?'", "\u2588" in txt and "?" not in banner)
check("rule is a horizontal line, not '?'", "\u2500" in txt)
check("hint shows arrows and Enter glyph", "\u2191/\u2193" in txt and "\u23ce" in txt)
check("prompt bullet and selection marker render", "\u203a" in txt and "\u25b8" in txt)

# 2. Down + Enter selects item 2 (3x-ui submenu opens).
out = run(40, [b"\x1b[B", b"\r"])
check("Down+Enter opens 3x-ui submenu", "Xray proxy panel" in strip_ansi(out))

# 3. '9' jumps straight to Firewall (auto-submit, no Enter needed).
out = run(40, [b"9"])
check("'9' jumps to Firewall", "backend:" in strip_ansi(out))

# 4. '13' on the 12-item menu: the '3' is ignored, Enter confirms choice 1.
out = run(40, [b"1", b"3", b"\r"])
clean = strip_ansi(out)
check("'13' never submits as invalid", "Invalid choice: 13" not in clean)
check("'13' selects item 1 instead", "L2TP" in clean)

# 5. '01' in a submenu selects choice 1, never 'Invalid choice: 01'.
out = run(40, [b"2", b"0", b"1"])
clean = strip_ansi(out)
check("'01' never submits as invalid", "Invalid choice: 01" not in clean)
check("'01' selects submenu item 1", "Download and run the installer now?" in clean)

# 6. '0' then an out-of-range digit stays on Back; Enter backs out.
out = run(40, [b"2", b"0", b"9", b"\r"])
clean = strip_ansi(out)
check("'0' then '9' stays on Back", "Invalid choice" not in clean
      and "Press Enter to return to the menu" in clean)

# 7. Up wraps to Exit; Enter exits cleanly.
out = run(40, [b"\x1b[A", b"\r"])
check("Up wraps to Exit and exits", b"\x1b[?25h" in out)

# 8. q backs out of a submenu.
out = run(40, [b"2", b"q"])
check("q backs out of a submenu", "Press Enter to return to the menu" in strip_ansi(out))

# 9. Short terminal (<30 rows) gets the compact banner, no art.
out = run(24, [])
txt = strip_ansi(out)
check("24-row terminal gets the compact banner", "\u2588" not in txt
      and "VPS management, made simple" in txt and "Main menu" in txt)

# 10. Narrow terminal (44 cols, like a phone in portrait): no line may be
# wider than the terminal (wrapped rows garble the fixed-line redraw), the
# banner is the compact one-liner, and navigation still works.
out = run(24, [], cols=44)
txt = strip_ansi(out)
wide = [l for l in txt.split("\n") if len(l) > 44]
check("44-col terminal: no line wider than the terminal", not wide)
check("44-col terminal: compact banner, menu present", "\u2588" not in txt
      and "Main menu" in txt and "Check For Updates" in txt)
out = run(40, [], cols=44)
txt = strip_ansi(out)
check("44-col tall terminal: compact banner by width, not rows",
      "\u2588" not in txt and "Main menu" in txt)
out = run(24, [b"\x1b[B", b"\r"], cols=44)
check("44-col terminal: Down+Enter still opens 3x-ui submenu",
      "Xray proxy panel" in strip_ansi(out))

# 11. The ezvps file itself stays pure ASCII (glyphs are \\u escapes).
raw = open(EZVPS, "rb").read()
check("ezvps file is pure ASCII", all(b < 128 for b in raw))

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PYEOF
