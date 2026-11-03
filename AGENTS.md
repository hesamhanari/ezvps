# AGENTS.md

Guidance for AI agents and contributors working on ezvps. Read `SPEC.md`
first; it is the source of truth for scope.

## Project

`ezvps` is a single bash script (`ezvps`) that gives a TUI menu and CLI for
managing a Debian (12, 13) or Ubuntu LTS (22.04, 24.04, 26.04) VPS as root. `install.sh` installs it to
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
  `dpkg-query`, optionally `ss`; Certificates: `nginx`, `systemctl`,
  `curl` and `sha256sum` (acme.sh download only), the installed `acme.sh`
  itself, optionally `openssl` (expiry dates), `crontab` (presence check and
  backup) and `ss`; Backpack, ctunnel and Lazyports: `uname`, `bash`, `sha256sum`,
  `curl` (installer download), `git`/`make`/`gcc` (ctunnel build), `go` (Lazyports,
  never installed by ezvps), `apt-get` (offered packages) and optionally `systemctl`
  (Backpack's `backpack-*.service` units); SSH and Users: `useradd`, `usermod`,
  `userdel`, `passwd`, `chown`, `sshd` (`-t`/`-T`), `systemctl`, optionally `ss` and `apt-get`;
  no `sed`/`awk`/`grep`/`ssh-keygen`: passwd, group and sshd_config are parsed in bash; Firewall:
  only the one detected backend's own command (`ufw`, `firewall-cmd`, `nft` or `iptables`), plus
  `ss` and `sshd` when present, `date`/`mkdir`/`chmod` for the rule listing copy, and no
  `sed`/`awk`/`grep`: backend output is parsed in bash). Shared
  helpers (`have_cmd`, `require_cmds`, `ask_yes_no`, `require_supported_os`,
  `port_in_use`, `backup_file`) are module-neutral; reuse them. Adding another
  one is a decision: check it exists (`command -v`) and degrade with a clear
  message; do not assume it.
* Downloads: `curl` is allowed only in `xui_fetch_installer` / `xui_probe`,
  in `ngx_fetch_key` (the nginx.org signing key), in `acme_fetch_script`
  (the pinned acme.sh script) and in `lc_fetch_installer` (the pinned Backpack and
  Lazyports installers); git may touch the network only in `lc_fetch_source` (the
  pinned ctunnel commit, https only). Lint enforces both.
  Download to a temp file, show URL and hash, verify, ask, then run. Never
  pipe or process-substitute a download into a shell. Pin a tag/version plus
  a SHA-256 (the nginx.org key is pinned by fingerprint); never
  `master`/`main`. acme.sh is the script at a release tag with a SHA-256 (SPEC
  6.4), never `get.acme.sh`.
* Backpack, ctunnel, Lazyports are **lifecycle modules only** (Install, Status, Update,
  Uninstall) on one shared flow (`lc_*`, per-tool table in `lc_load`). Tunnel setup,
  ports, tokens and every other setting stay in the tool's own interface: never rebuild
  them, never launch a tool after installing it, never ask for, store, print or log a
  tunnel token, setup link, password or key (config backups are byte-for-byte copies that
  ezvps does not read). Use only what upstream documents: no invented service name,
  version flag or update command; where upstream has none, say so and offer the
  documented reinstall (backup first). Upstream installer scripts are pinned (tag or full
  commit plus SHA-256), shown, confirmed and run with `</dev/null`. Adding a tool means a
  new `lc_load` entry, not a new submenu.
* SSH and Users (SPEC 6.8): never read `/etc/shadow`, never print, store or log a password,
  a password hash or a private key (a pasted private key is refused and discarded). A
  password is only ever asked for by the system's own `passwd` prompt. Delete user refuses
  root, UID 0, the current user, system accounts and users with running processes with no
  override prompt; a home directory is removed only with `userdel -r` after its own second
  confirmation. sshd changes: only Port, PermitRootLogin and PasswordAuthentication, backup
  first, `sshd -t` before any restart, and a rollback to the backup on any failure; verify
  with `sshd -T`/the listening port, never trust the file alone (drop-ins and socket
  activation can make a written line ineffective).
* Certificates: HTTP-01 through nginx, one domain, Let's Encrypt only. No
  wildcard, DNS API, DNS provider credentials, `stream` or certbot. A private
  key is never printed or read by ezvps; certificates live in `/etc/ssl/ezvps`
  (dir 700, key 600). Only an ezvps-made site file (valid markers) is ever
  rewritten for HTTPS or back; hand-written files are never edited.
* The site template (`ngx_render_site`) is shared by the HTTP and HTTPS forms;
  `Connection` comes from the `$connection_upgrade` map, never a hardcoded
  `"upgrade"`, and `ngx_ensure_upgrade_map` must run before any site that uses
  it is written. `nginx -t` before every reload, rollback on failure.
* nginx comes only from the nginx.org **stable** repository (never the Debian
  or Ubuntu package, never mainline) with the apt pin; do not weaken that
  (SPEC 6.3). The repository path follows the detected distro
  (`packages/debian`, `packages/ubuntu`) and the suite is the detected codename
  (`bookworm`, `trixie`, `jammy`, `noble`, `resolute`), never a per-distro constant.
* Supported systems are exactly the five `ID` + `VERSION_ID` + `VERSION_CODENAME`
  triples in SPEC 1.1 (Debian 12/13, Ubuntu 22.04/24.04/26.04); all three must
  agree. The allowlist block is duplicated verbatim in `ezvps` and `install.sh`
  and lint keeps the copies identical.
  Every module that needs a supported system calls `require_supported_os` (which
  runs `detect_os` and sets `OS_ID` / `OS_VERSION` / `OS_CODENAME`); never read
  `/etc/os-release` yourself and never add a version to the list without a
  tested module change. Where Debian and Ubuntu really differ, branch on
  `$OS_ID` with a comment saying why; where they behave the same keep one code
  path. L2TP (ezl2tp) is gated by `L2TP_SUPPORTED` (Debian 13 only) until the
  owner says otherwise; never claim L2TP works where ezl2tp does not.
* Firewall (SPEC 6.9): the backend is the first present of `ufw`, `firewalld`, `nftables`,
  `iptables` (fixed order, `FW_BACKENDS`); use only that backend's documented commands, always
  through `fw_run` (C locale, output captured), and never install a firewall tool. Never enable,
  disable, reset or flush a firewall, reload firewalld, change a default policy, zone, table or
  chain, or remove more than the one rule the user picked by ID (lint enforces the command list).
  Every change starts with `fw_change_preflight` (root, supported system, backend, and for
  `ufw`/`firewalld` an enabled firewall), validates port (1-65535, digits only) and protocol
  (`tcp`/`udp`), refuses a duplicate, asks once, saves a text copy of the listing, and re-reads the
  rules from the backend afterwards; removing a rule that allows SSH needs its own warning and
  second confirmation, and the rules are re-read to make sure the chosen rule is still the same.
  nftables/iptables changes are runtime only and say so; do not rewrite their saved configuration.
* Output goes through `info` / `warn` / `err`. Colour only on a TTY and
  honour `NO_COLOR`.
* Test-only switches are environment variables documented in `SPEC.md`
  section 7a (`EZVPS_ALLOW_NONROOT`, `EZVPS_XUI_DIR`, `EZVPS_ACME_HOME`,
  `EZVPS_CERT_DIR`, `EZVPS_TOOL_PREFIX`, `EZVPS_BACKPACK_CONF_DIR`, `EZVPS_PASSWD_FILE`,
  `EZVPS_SSHD_CONFIG`, ...). Do not add switches that weaken real behaviour.

## Adding a module

1. Write `module_<key>` and wire it in `run_module` (replace the
   `module_not_implemented` entry).
2. Follow the module contract in `SPEC.md` section 5.
3. Extend `tests/smoke-test.sh` with stubs/fakes: no network, no real
   system changes, fake data only (the 3x-ui section is the template: a fake
   panel CLI, stub `systemctl`/`curl`/`ss`, per-scenario temp dirs; the
   Certificates section adds a fake `acme.sh`). Remove the module from the
   not-yet-implemented loop. The test sandbox `PATH` holds only bash, a few
   coreutils and the stubs, so module code may not rely on other tools. When a
   test compares a file to a copy of itself it proves nothing: check that each
   new assertion fails when the behaviour it covers is broken.
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
