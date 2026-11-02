# AGENTS.md

Guidance for AI agents and contributors working on ezvps. Read `SPEC.md`
first; it is the source of truth for scope.

## Project

`ezvps` is a single bash script (`ezvps`) that gives a TUI menu and CLI for
managing a Debian 13 or Ubuntu 24.04 LTS VPS as root. `install.sh` installs it to
`/usr/local/bin/ezvps`. Same principles as easyl2tp.

## Rules that must never be broken

1. **Check before installing.** Detect existing commands/packages/services
   first; skip or ask.
2. **Backup before overwriting** any config or binary
   (`/var/backups/ezvps/<name>.<timestamp>`).
3. **Idempotent re-runs.** Running anything twice must not duplicate or
   break state.
4. **No hardcoded secrets.** Generate, prompt, or read from the environment.
   (The 3x-ui default credentials in SPEC 6.2 are the one owner-approved
   exception, always with a change-password warning.)
5. **No real data in the repo or its history:** no real server IPs, secrets,
   tokens, hostnames or usernames, in code, docs, tests, fixtures or commit
   messages. Use `192.0.2.x`, `198.51.100.x`, `203.0.113.x`, `example.com`,
   `testuser`, `<owner>`.
6. **ezl2tp is separate.** Never copy or rewrite the ezl2tp installer into
   this repo. Never download the private easyl2tp repo anonymously (no raw
   URL `curl`/`wget`). The L2TP module launches an installed `ezl2tp`, or
   prints `git clone` instructions with private auth. `install.sh` must
   never modify an existing ezl2tp install.
7. **Never fail the menu.** Modules return 0 to the menu; show a clear
   message instead of crashing. Unbuilt modules print
   `<Label> is not implemented yet.` and return.
8. **Menu labels are clean:** just the item name, no description text.

## Layout

```
ezvps                    the panel script (bash; menu + L2TP are builtins-only)
install.sh               installer
tests/lint.sh            bash -n + shellcheck + hygiene scan
tests/smoke-test.sh      automated smoke test (fake data, stubs, temp dirs)
tests/fresh-vps-test.md  manual fresh-VPS checklist
SPEC.md  README.md  AGENTS.md
```

## Code conventions

* `#!/usr/bin/env bash`, `set -uo pipefail` (no blanket `set -e`; handle
  errors explicitly so the menu survives).
* Must pass `shellcheck` clean. Quote everything; use `[[ ]]`; `local`
  variables; functions named `module_<key>` for modules.
* Menu and L2TP use bash builtins only. Module code may use coreutils and
  the few external commands its SPEC section lists (3x-ui: `systemctl`,
  `sha256sum`, `curl`, optionally `ss`/`sqlite3`/`hostname`; Nginx:
  `systemctl`, `apt-get`, `apt-cache`, `nginx`, `gpg`, `curl` (key only),
  `dpkg-query`, optionally `ss`). Shared
  helpers (`have_cmd`, `require_cmds`, `ask_yes_no`, `require_supported_os`,
  `port_in_use`, `backup_file`) are module-neutral; reuse them. Adding another
  one is a decision: check it exists (`command -v`) and degrade with a clear
  message; do not assume it.
* Downloads: `curl` is allowed only in `xui_fetch_installer` / `xui_probe`
  and in `ngx_fetch_key` (the nginx.org signing key); lint enforces it.
  Download to a temp file, show URL and hash, verify, ask, then run. Never
  pipe or process-substitute a download into a shell. Pin a tag/version plus
  a SHA-256 (the nginx.org key is pinned by fingerprint); never
  `master`/`main`.
* nginx comes only from the nginx.org **stable** repository (never the Debian
  or Ubuntu package, never mainline) with the apt pin; do not weaken that
  (SPEC 6.3). The repository path follows the detected distro
  (`packages/debian` + `trixie`, `packages/ubuntu` + `noble`).
* Supported systems are exactly Debian 13 and Ubuntu 24.04 LTS (SPEC 1.1).
  Every module that needs a supported system calls `require_supported_os` (which
  runs `detect_os` and sets `OS_ID` / `OS_VERSION` / `OS_CODENAME`); never read
  `/etc/os-release` yourself and never add a version to the list without a
  tested module change. Where Debian and Ubuntu really differ, branch on
  `$OS_ID` with a comment saying why; where they behave the same keep one code
  path. L2TP (ezl2tp) stays Debian 13 only until the owner says otherwise.
* Output goes through `info` / `warn` / `err`. Colour only on a TTY and
  honour `NO_COLOR`.
* Test-only switches are environment variables documented in `SPEC.md`
  section 7a (`EZVPS_ALLOW_NONROOT`, `EZVPS_XUI_DIR`, ...). Do not add switches that
  weaken real behaviour.

## Adding a module

1. Write `module_<key>` and wire it in `run_module` (replace the
   `module_not_implemented` entry).
2. Follow the module contract in `SPEC.md` section 5.
3. Extend `tests/smoke-test.sh` with stubs/fakes: no network, no real
   system changes, fake data only (the 3x-ui section is the template: a fake
   panel CLI, stub `systemctl`/`curl`/`ss`, per-scenario temp dirs). Remove
   the module from the not-yet-implemented loop.
4. Add a section to `tests/fresh-vps-test.md` and update the status table in
   `SPEC.md`.
5. One module per PR.

## Before every PR

```
bash tests/lint.sh
bash tests/smoke-test.sh
```

Both must pass. Work on a branch and open a PR; never push to `main`
directly.
