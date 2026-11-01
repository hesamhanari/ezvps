# ezvps SPEC

Version: 0.0.1 (in development). This file is the source of truth for scope.
Each later PR implements one module from the list below and updates the
status table here.

## 1. What ezvps is

A bash TUI/CLI VPS manager for **Debian 13**, run as **root**. One script,
installed as `/usr/local/bin/ezvps`. It has no dependencies beyond what a
Debian 13 install already has; anything a module needs is checked first and
installed only with the user's say-so.

## 2. Principles (same as easyl2tp)

1. **Check before installing.** Detect what is already there (command,
   package, service, port) and skip or ask. Never blindly reinstall.
2. **Backup before overwriting.** Any config or binary that ezvps would
   replace is first copied to `/var/backups/ezvps/<name>.<timestamp>`
   (dir mode 700).
3. **Idempotent.** Re-running an installer or module action converges to the
   same state and never duplicates config lines, users, rules or services.
4. **No hardcoded secrets.** Secrets are generated at runtime, prompted for,
   or read from the environment. The only fixed credentials are the 3x-ui
   defaults the product owner explicitly specified (section 6.2), which are
   always paired with a change-password warning.
5. **No real data in the repo.** No real server IPs, secrets, tokens or
   usernames anywhere in code, docs, tests or commit history. Tests and docs
   use fake data only: `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`,
   `example.com`, `testuser`.
6. **Never fail the menu.** A module problem prints a clear message and
   returns to the menu. The menu only exits on `0` or EOF.
7. **Third-party tools are fetched deliberately.** Show what will be
   downloaded and from where, confirm, pin a version/ref where the project
   publishes one, and never pipe a download straight into a shell.

## 3. CLI

```
ezvps                 interactive menu
ezvps <module>        run one module directly
ezvps --version       print version
ezvps --help          usage
```

Module keys: `l2tp 3x-ui backpack ctunnel nginx certs lazyports ssh firewall
backup update uninstall`. Unknown command: usage on stderr, exit 2.

Menu/module commands require root (exit 1 otherwise). `--help` and
`--version` do not. `EZVPS_ALLOW_NONROOT=1` bypasses the check and exists
**for tests only**.

## 4. Main menu

Clean labels only: no description text after the item names. Exact output:

```
 1) L2TP
 2) 3x-ui
 3) Backpack
 4) ctunnel
 5) Nginx
 6) Certificates
 7) Lazyports
 8) SSH and Users
 9) Firewall
10) Backup
11) Check For Updates
12) Uninstall
 0) Exit
```

Behaviour: after a module returns, "Press Enter to return to the menu...",
then the menu redraws. Invalid input prints `Invalid choice: <input>` and
redraws. EOF on stdin exits 0.

## 5. Module contract

* A module is a function `module_<name>` dispatched by `run_module`.
* It returns 0 for "handled, back to the menu", including when the user
  cancels or a precondition is missing. Non-zero is reserved for unexpected
  internal errors, and the menu still continues.
* It prints what it is about to change before changing it, and asks before
  anything destructive.
* A planned-but-unbuilt module calls `module_not_implemented <key>`, which
  prints `<Label> is not implemented yet.` and returns 0.
* Each module PR adds: the module code, smoke-test coverage using fake data
  and stubs (no network, no real system changes), a section in
  `tests/fresh-vps-test.md`, and updates the table below.

## 6. v0.0.1 scope

| # | Menu item         | Status in PR 1      | Planned PR |
|---|-------------------|---------------------|------------|
| 1 | L2TP              | **implemented**     | PR 1       |
| 2 | 3x-ui             | not implemented yet | later      |
| 3 | Backpack          | not implemented yet | later      |
| 4 | ctunnel           | not implemented yet | later      |
| 5 | Nginx             | not implemented yet | later      |
| 6 | Certificates      | not implemented yet | later      |
| 7 | Lazyports         | not implemented yet | later      |
| 8 | SSH and Users     | not implemented yet | later      |
| 9 | Firewall          | not implemented yet | later      |
| 10| Backup            | not implemented yet | later      |
| 11| Check For Updates | not implemented yet | later      |
| 12| Uninstall         | not implemented yet | later      |

One module per PR.

### 6.1 L2TP (PR 1, done)

* If `ezl2tp` exists on `PATH`: print `Launching ezl2tp...`, run it as a
  child process (not `exec`), then print `Returned to ezvps.` and go back to
  the menu. A non-zero exit from ezl2tp is reported but never fails ezvps.
* If it does not exist: print clear instructions to install ezl2tp from its
  **private** repository using `git clone` with the user's own
  authentication (GitHub CLI login, SSH/deploy key, or HTTPS with a token
  typed at git's prompt), then return to the menu. Placeholders such as
  `<owner>` are used; nothing real is hardcoded.
* ezvps does **not** download the private easyl2tp repo anonymously (no
  `curl`/`wget` of raw URLs), and does **not** copy or reimplement the
  ezl2tp installer. ezl2tp stays a separate product with its own installer.

### 6.2 3x-ui (later PR) - two modes

Both modes: check for an existing install first (binary, service, port);
back up the panel database/config before any change; idempotent re-runs;
check that the chosen port is free before installing.

**Default mode** (opinionated, non-interactive after one confirmation):

| Setting       | Value      |
|---------------|------------|
| Panel port    | `3389`     |
| Username      | `admin`    |
| Password      | `Admin123` |
| Web base path | `xuipanel` |
| TLS/certs     | none (plain HTTP) |

These are well-known defaults, so after install ezvps must print a
prominent **warning to change the password** (and the username if wanted)
immediately, and must also say that the panel is served without TLS.
Not a secret store: ezvps never saves or logs a changed password.

**Self installer mode:** run the upstream 3x-ui project's own installer
and let it ask its own questions; ezvps only checks prerequisites beforehand
and shows the resulting panel status afterwards. The exact upstream source
and pin are decided in that PR.

### 6.3 Nginx (later PR)

Detect/install nginx; manage reverse-proxy site configs (list, add, enable,
disable, remove) with backup before overwrite, `nginx -t` before every
reload, rollback to the backup if the test fails.

### 6.4 Certificates (later PR)

Issue/renew/list/remove certificates for domains the user enters (ACME
client chosen in that PR), hook into nginx reload, show expiry. Checks that
the domain resolves to this server and port 80 is reachable before issuing.

### 6.5 Backpack (later PR)

Install/update/remove **github.com/AminMGMT/BackPack**. Show what will be
fetched, confirm, pin a release/ref, check existing install first.

### 6.6 ctunnel (later PR)

Install/update/remove **github.com/alienrobotarmy/ctunnel**. Same fetch
rules as above.

### 6.7 Lazyports (later PR)

Install/update/remove **github.com/v9mirza/lazyports**. Same fetch rules as
above.

### 6.8 SSH and Users (later PR)

SSH: show effective sshd settings, change port / root login / password
auth, with `sshd -t` before reload and backup of `sshd_config`; guard
against locking the user out (confirm, keep the current session working).
VPS users: list, add, lock, unlock, delete users; add/remove authorized
keys; sudo membership.

### 6.9 Firewall (later PR; v0.0.1 = show only)

Read-only view of the active firewall (nftables/ufw/iptables, whichever is
present) and listening ports. No rule changes in v0.0.1.

### 6.10 Backup (later PR)

Back up ezvps-managed configs to `/var/backups/ezvps`, list backups,
restore one (backing up the current file first).

### 6.11 Check For Updates (later PR)

Compare the installed ezvps with the latest source and offer to update by
re-running the installer path (which backs up the old script). Open
question for that PR: how the update source is located without hardcoding
anything private (for example, the git remote of the original checkout).

### 6.12 Uninstall (later PR)

Remove ezvps per module with confirmation, backing up first. Never removes
ezl2tp unless the user explicitly picks it.

## 7. Installer (`install.sh`)

* Installs `ezvps` to `/usr/local/bin/ezvps` (mode 0755) from the checkout
  it is run from. Downloads nothing.
* Requires root; warns (does not fail) when the OS is not Debian 13.
* Refuses to install a script that fails `bash -n` or `--version`.
* Safe to re-run: identical file => "already up to date", no backup. Changed
  file => old copy saved to `/var/backups/ezvps/ezvps.<timestamp>.<pid>`,
  then atomic replace (temp file + `mv`).
* Never touches ezl2tp (command, config, state); only reports whether it is
  found.
* Test overrides: `EZVPS_BIN_DIR`, `EZVPS_BACKUP_DIR`, `EZVPS_SOURCE`,
  `EZVPS_ALLOW_NONROOT=1`, `EZVPS_SKIP_OS_CHECK=1`.

## 8. Tests

* `tests/lint.sh`: `bash -n` + `shellcheck` on every script, plus a hygiene
  scan (no non-documentation IPs, key material or token patterns; no
  `curl`/`wget` in `ezvps`).
* `tests/smoke-test.sh`: runs in a temp dir with an empty/stub `PATH`;
  covers the exact menu, the L2TP launch path with a fake `ezl2tp` stub
  (success and non-zero exit), the missing-ezl2tp path, every
  not-yet-implemented module via menu and CLI, and `install.sh`
  (fresh, re-run, changed file + backup, ezl2tp preserved, broken source
  refused). It touches nothing outside its temp dir.
* `tests/fresh-vps-test.md`: manual checklist on a throwaway Debian 13 VPS.
