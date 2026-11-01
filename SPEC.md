# ezvps SPEC

Version: 0.0.1 (in development). This file is the source of truth for scope.
Each later PR implements one module from the list below and updates the
status table here. Done so far: L2TP (PR 1), 3x-ui (PR 2).

## 1. What ezvps is

A bash TUI/CLI VPS manager for **Debian 13**, run as **root**. One script,
installed as `/usr/local/bin/ezvps`. It has no dependencies beyond what a
Debian 13 install already has (bash, coreutils, systemd); anything else a
module needs is checked with `command -v` first and installed only with the
user's say-so (for 3x-ui that is only `curl`).

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

| # | Menu item         | Status              | PR         |
|---|-------------------|---------------------|------------|
| 1 | L2TP              | **implemented**     | PR 1       |
| 2 | 3x-ui             | **implemented**     | PR 2       |
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

### 6.2 3x-ui (PR 2, done)

Menu item 2 opens a submenu. Clean labels only:

```
 1) Install 3x-ui
 2) Install with 3x-ui self installer
 3) Status
 4) Restart
 5) Panel info
 6) Change password
 0) Back
```

`0` or EOF returns to the main menu. After each action: "Press Enter to
continue...". Invalid input prints `Invalid choice: <input>`.

#### Upstream source and pin

* Project: <https://github.com/MHSanaei/3x-ui> (public; the "official" 3x-ui).
* Installer ezvps uses, **exact URL**:
  `https://raw.githubusercontent.com/MHSanaei/3x-ui/v3.11.0/install.sh`
  (the project's own `install.sh` at release tag **v3.11.0**, never
  `master`).
* Expected SHA-256 of that file:
  `9684bae4f769b2127fcceceb4f200045657381311867529e6ba76c6b58e2825d`
* The installer is also given the same tag as its version argument, so it
  installs the `v3.11.0` release archive from
  `https://github.com/MHSanaei/3x-ui/releases/download/v3.11.0/` and checks
  that archive against the `.sha256` file the project publishes next to it.
* The pin lives in `ezvps` as `XUI_PINNED_TAG` and `XUI_INSTALLER_SHA256`.
  To bump it: pick a newer release tag, download `install.sh` at that tag,
  read it, update both constants together and this section, run the tests.
* Download rules: ezvps prints the project, version, URL and expected hash
  and asks for a yes; downloads into a private temp directory
  (`curl --proto '=https' --tlsv1.2`); verifies the SHA-256 and **refuses to
  run on a mismatch**; then runs `bash <file> v3.11.0` and deletes the temp
  directory. Nothing is ever piped from the network into a shell.

#### Prechecks (both install modes)

1. Root (`require_root`).
2. Debian 13 (`/etc/os-release`: `ID=debian`, `VERSION_ID=13`); otherwise
   refuse, nothing changed.
3. Required commands present: coreutils, `systemctl`, `sha256sum`. `curl` is
   offered for install via `apt-get` (only after a yes) if missing.
4. **Existing panel detection first**: panel binary `/usr/local/x-ui/x-ui`,
   database `/etc/x-ui/x-ui.db`, or a `x-ui.service` unit.
5. Default mode only: port 3389 must be free (`ss`, else a `/dev/tcp`
   connect). An existing panel that is itself on 3389 does not count as busy.

#### 1) Install 3x-ui (default mode)

Opinionated; one confirmation, then non-interactive.

| Setting       | Value      |
|---------------|------------|
| Panel port    | `3389`     |
| Username      | `admin`    |
| Password      | `Admin123` |
| Web base path | `xuipanel` |
| TLS/certs     | none (plain HTTP) |

Fresh machine:

1. Prechecks, show the plan and the download details, ask.
2. Download and verify the pinned installer; run it with
   `XUI_NONINTERACTIVE=1 XUI_SSL_MODE=none XUI_PANEL_PORT=3389` and the pinned
   tag. (The upstream installer prints temporary generated credentials; they
   are replaced in the next step.)
3. Apply the defaults with the panel's own CLI:
   `x-ui setting -username admin -password Admin123 -port 3389 -webBasePath xuipanel`
   then `x-ui cert -reset` (no certificate). The CLI reports errors on stdout
   with exit 0, so ezvps checks its success messages and reads the settings
   back with `x-ui setting -show=true`.
4. `systemctl restart x-ui`, then **verify the panel responds** on
   `http://127.0.0.1:3389/xuipanel/` (HTTP 2xx/3xx; 404 means wrong path;
   retried for up to 30 s).
5. Record non-secret state, print a summary and the warning below.

Existing panel: show what was found and its port/path, back it up
(see Backups), then ask `Overwrite the existing panel settings with the
defaults?`. Only on yes are steps 3-5 applied; the panel software is not
re-downloaded. No: nothing changes. If the panel already has the ezvps
defaults, the re-run changes nothing, makes no backup, still verifies and
still prints the warning. Port 3389 held by something other than the panel
itself is refused before any backup or change.

**Mandatory warning** after every default install (and in Panel info while
the default password is still in use): change the password immediately,
because `admin` / `Admin123` is a known default and the panel runs on plain
HTTP. These defaults are the one owner-approved exception to the "no
hardcoded secrets" rule and always appear together with this warning.

#### 2) Install with 3x-ui self installer

Same prechecks except the port-3389 check. Existing panel: it is backed up
first, including the panel binary. Then ezvps shows the download details,
asks, downloads and verifies the pinned installer, and launches
`bash install.sh v3.11.0` **interactively** with the terminal attached. The
installer asks its own questions (port, credentials, certificates, ...);
ezvps passes no environment variables, no defaults and no answers. When it
exits, ezvps prints `Returned to ezvps.` (and a warning if the exit status
was non-zero) and shows the panel status. A Ctrl-C meant for the installer
does not kill ezvps.

#### 3) Status

Whether `x-ui` is running (and enabled at boot), the port and base path from
the panel's own settings, whether TLS is configured, and whether the panel
**responds** (a local HTTP(S) request to `127.0.0.1:<port>/<path>/`). Without
`curl` the response line says so instead of failing. Read-only.

#### 4) Restart

`systemctl restart x-ui` and nothing else (no other service, no reboot, no
settings change), then the same response check as Status.

#### 5) Panel info

URL (`http://<server-ip>:<port>/<path>/`; the real address list from
`hostname -I` is shown when available), port, path, TLS, username. The
password line depends on how the panel was installed:

* default install: the known default (`Admin123`), with the warning, until
  Change password is used; afterwards "the one you set ... ezvps does not
  store it";
* self installer: "the password is the one you set during the 3x-ui self
  installer and is not stored by ezvps";
* panel not installed through ezvps: "not managed by ezvps".

The panel CLI cannot print the username, so ezvps uses its state file, then
the panel database if `sqlite3` is installed, else says it is unknown.

#### 6) Change password

1. Needs the username too, because the panel CLI sets username and password
   together: taken from the state file / database, else asked (with a warning
   that a typo renames the login).
2. Password prompted twice without echo; at least 8 characters; the known
   default is rejected.
3. Back up the panel config, then `x-ui setting -username <user> -password
   <new>` (the panel's own settings command), check its success message,
   `systemctl restart x-ui`, verify the panel responds.
4. The new password is **never printed, logged or stored** by ezvps: the CLI
   output is only shown on failure, with the password masked. (The panel CLI
   takes the password as an argument, so it is visible in the process list
   for the instant the command runs; that is a limitation of the CLI.)

#### Backups and state

* Backup before any change to an existing panel (default-mode overwrite,
  self installer over an existing panel, Change password):
  `/var/backups/ezvps/x-ui.<timestamp>.<pid>/` (mode 700) holding `db/` (a
  copy of `/etc/x-ui`), `config.json` (the panel's `bin/config.json`) and,
  for the self installer, the `x-ui` binary. If a backup fails the action is
  aborted before anything is changed.
* State file `/var/lib/ezvps/3x-ui.state` (dir 700, file 600), plain
  `key=value` lines read without `source`: `mode` (`default` or `self`),
  `username`, `password_default` (`1` while the known default is in use).
  **No password is ever stored.**
* Module key `3x-ui` maps to the function `module_3x_ui`.

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

## 7a. Test-only environment variables

Defaults are the real paths; none of these relax a check on a real server.

| Variable | Used by | Meaning |
|----------|---------|---------|
| `EZVPS_ALLOW_NONROOT=1` | ezvps, install.sh | skip the root check |
| `EZVPS_SKIP_OS_CHECK=1` | ezvps (3x-ui), install.sh | skip the Debian 13 check |
| `EZVPS_OS_RELEASE` | ezvps (3x-ui) | os-release file to read (default `/etc/os-release`) |
| `EZVPS_XUI_DIR` | ezvps (3x-ui) | panel install dir (default `/usr/local/x-ui`) |
| `EZVPS_XUI_DB_DIR` | ezvps (3x-ui) | panel database dir (default `/etc/x-ui`) |
| `EZVPS_STATE_DIR` | ezvps (3x-ui) | state dir (default `/var/lib/ezvps`) |
| `EZVPS_BACKUP_DIR` | ezvps (3x-ui), install.sh | backup dir (default `/var/backups/ezvps`) |
| `EZVPS_XUI_WAIT_SECONDS` | ezvps (3x-ui) | how long to wait for the panel to answer (default 30) |
| `EZVPS_NO_PAUSE=1` | ezvps | do not wait for Enter |

## 8. Tests

* `tests/lint.sh`: `bash -n` + `shellcheck` on every script, plus a hygiene
  scan (no non-documentation IPs, key material or token patterns) and the
  download rules: `curl` only inside `xui_fetch_installer` / `xui_probe`, no
  download piped into a shell, none in `install.sh`, installer URL pinned to
  a tag (not `master`), pin constants present.
* `tests/smoke-test.sh`: runs in a temp dir with an empty/stub `PATH`;
  covers the exact menu, the L2TP launch path with a fake `ezl2tp` stub
  (success and non-zero exit), the missing-ezl2tp path, every
  not-yet-implemented module via menu and CLI, and `install.sh`
  (fresh, re-run, changed file + backup, ezl2tp preserved, broken source
  refused). 3x-ui is tested against a **fake panel settings CLI** (`x-ui`
  stub with its own fake database) plus stub `systemctl`, `curl`, `ss`,
  `sha256sum`, `apt-get` and a fake installer: submenu labels, prechecks
  (non-Debian-13, busy port, missing curl), default install settings,
  idempotent re-run, existing panel (backup, decline, overwrite, busy port),
  hash mismatch / download failure / installer failure, self installer launch
  (no defaults forced), status, restart (only `x-ui`), panel info for all
  three install origins, and change password (never printed or stored).
  It touches nothing outside its temp dir and uses no network.
* `tests/fresh-vps-test.md`: manual checklist on a throwaway Debian 13 VPS.
