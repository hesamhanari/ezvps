# ezvps SPEC

Version: 0.0.1 (in development). This file is the source of truth for scope.
Each later PR implements one module from the list below and updates the
status table here. Done so far: L2TP (PR 1), 3x-ui (PR 2), Nginx (PR 3, conf.d in PR 4, nginx.org stable in PR 5), Ubuntu 24.04 LTS support (PR 6).

## 1. What ezvps is

A bash TUI/CLI VPS manager for **Debian 13** and **Ubuntu 24.04 LTS**, run as
**root**. One script, installed as `/usr/local/bin/ezvps`. It has no
dependencies beyond what a Debian 13 or Ubuntu 24.04 install already has (bash,
coreutils, systemd); anything else a
module needs is checked with `command -v` first and installed only with the
user's say-so (3x-ui: `curl`; Nginx: `curl`, `gnupg` and the nginx.org `nginx` package itself).

### 1.1 Supported systems

| System | Version | Codename | Status | L2TP (ezl2tp) | 3x-ui | Nginx |
|--------|---------|----------|--------|---------------|-------|-------|
| Debian | 13 | `trixie` | **supported** | yes | yes | yes (`nginx.org/packages/debian`) |
| Ubuntu | 24.04 LTS | `noble` | **supported** (PR 6) | **no: Debian 13 only for now** | yes | yes (`nginx.org/packages/ubuntu`) |
| any other | Ubuntu 22.04, Debian 12, Fedora, derivatives such as Linux Mint, ... | n/a | **rejected** | n/a | n/a | n/a |

* **One shared check.** `detect_os` reads `/etc/os-release` (the `ID`,
  `VERSION_ID` and `VERSION_CODENAME` lines; the file is parsed, never sourced,
  and `ID_LIKE` is ignored) and sets `OS_ID`, `OS_VERSION`, `OS_CODENAME`.
  `require_supported_os "<action>"` calls it and accepts exactly `debian 13` and
  `ubuntu 24.04`; everything else (other versions, other distros, derivatives, a
  missing or unreadable file, a Debian without `VERSION_ID`) is refused with
  `<action> needs Debian 13 or Ubuntu 24.04 LTS; found '<id> <version>'. Nothing
  was changed.` and the module returns to the menu. The 3x-ui and Nginx installs,
  L2TP and `install.sh` all use this rule; there is no separate Debian-only
  check any more.
* **Branch on the distro only where they differ,** with a comment: the nginx.org
  repository path (6.3) and L2TP (6.1). Everything else is one code path.
* **Audit of Debian-specific assumptions** (done for PR 6; re-check it when a
  module is added):

  | Area | Debian 13 | Ubuntu 24.04 | Result |
  |------|-----------|--------------|--------|
  | L2TP | ezl2tp supported | ezl2tp not ported | branch: Ubuntu prints a message and returns |
  | 3x-ui installer | upstream `install.sh` handles `debian` | handles `ubuntu` the same way (`apt-get` dependencies, `x-ui.service.debian` unit) | one path |
  | 3x-ui paths and service | `/usr/local/x-ui`, `/etc/x-ui`, `x-ui.service` | identical | one path |
  | apt tooling | `apt-get`, `apt-cache`, `dpkg-query` | identical | one path |
  | nginx package and service names | `nginx`, `nginx-common`, `libnginx-mod-*`, `nginx.service` | identical | one path |
  | nginx.org repository | `packages/debian`, codename `trixie` | `packages/ubuntu`, codename `noble` | branch: URL and codename from the detected distro |
  | nginx.org package version suffix | `~trixie` | `~noble` | one path (suffix is the detected codename) |
  | distribution's own nginx | Debian's `1.26.x...+deb13...` | Ubuntu's `1.24.x...ubuntu...` | one path (anything not ending in `~<codename>` is replaced) |
  | `/etc/nginx` layout and nginx.org `conf.d/default.conf` | `sites-*` plus `conf.d` | identical | one path |
  | signing key, pin | `nginx.org` key fingerprints, `origin nginx.org` at 900 | identical | one path |
  | 3x-ui/nginx prerequisites (`curl`, `gnupg`, `ca-certificates`) | same package names | same package names | one path |

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
| 5 | Nginx             | **implemented**     | PR 3       |
| 6 | Certificates      | not implemented yet | later      |
| 7 | Lazyports         | not implemented yet | later      |
| 8 | SSH and Users     | not implemented yet | later      |
| 9 | Firewall          | not implemented yet | later      |
| 10| Backup            | not implemented yet | later      |
| 11| Check For Updates | not implemented yet | later      |
| 12| Uninstall         | not implemented yet | later      |

One module per PR. Every implemented module runs on Debian 13 and Ubuntu 24.04
LTS (section 1.1), **except L2TP, which is Debian 13 only** for now.

### 6.1 L2TP (PR 1, done; Debian 13 only)

* **Debian 13 only for now.** ezl2tp is not ported to Ubuntu in PR 6 and ezvps
  does not try. The module first applies the shared OS check: an unsupported
  system is refused (`L2TP needs Debian 13 or Ubuntu 24.04 LTS; found ...`).
  On **Ubuntu 24.04** it prints `L2TP via ezl2tp is Debian 13 only for now
  (found Ubuntu 24.04).` and `ezvps does not launch or install ezl2tp on Ubuntu.
  Nothing was changed.`, then returns to the menu; it neither launches an
  `ezl2tp` that happens to be on `PATH` nor prints install instructions. The
  rest of this section describes Debian 13.
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
2. Debian 13 or Ubuntu 24.04 LTS (`require_supported_os`, section 1.1);
   otherwise refuse, nothing changed.
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

### 6.3 Nginx (PR 3, done; conf.d layout in PR 4; nginx.org stable in PR 5)

Menu item 5 opens a submenu. Clean labels only:

```
 1) Install Nginx
 2) Status
 3) Restart
 4) List sites
 5) Add site
 6) Remove site
 0) Back
```

`0` or EOF returns to the main menu; after each action "Press Enter to
continue..."; invalid input prints `Invalid choice: <input>`. Module key
`nginx` maps to `module_nginx`; its helpers are prefixed `ngx_`.

**HTTP only.** This module never issues, stores or references a certificate
and writes no `listen 443` / `ssl_*` directives. A site that needs HTTPS is
told to use the Certificates module (section 6.4) once it exists; until then
the message says it is not available yet.

#### Where sites live: `conf.d`

Nginx sites managed by ezvps live **only** in `/etc/nginx/conf.d`, one file per
domain, named `/etc/nginx/conf.d/<domain>.conf`. ezvps does not create, read
or manage `sites-available`/`sites-enabled` files for its own sites. The only
uses of those directories are (a) the legacy migration below, which reads
`sites-available` files that carry the ezvps marker, (b) the duplicate check,
which looks for another file already serving the domain. This matches the
nginx.org package, whose `nginx.conf` includes `conf.d/*.conf` and has no
`sites-available`/`sites-enabled` at all. The one file shipped by that package
that matters here is `conf.d/default.conf` (section 5).

* **Domain sanitising.** The domain is trimmed and lower-cased, then rejected
  unless it contains only letters, digits, dot and hyphen (anything with a
  `/` or `\` is rejected with a path-separator message) and is a hostname with
  at least two labels. Only a validated domain is ever used to build a file
  name, so `../x`, `a/b`, `x;y`, spaces or non-ASCII characters never reach
  the file system.
* **ezvps-made sites** carry a `# Managed by ezvps` header and
  `# ezvps:domain=` / `# ezvps:upstream=` marker lines (the same markers the
  older sites-available layout used, so old files can be moved unchanged).
* **nginx.conf must load conf.d** (checked by Add site and by the migration;
  List sites only warns). The check is a small brace-aware scan for an
  `include .../conf.d/*...;` directly inside the `http { }` block, ignoring
  comments. If it is missing: `nginx.conf` is backed up
  (`/var/backups/ezvps/nginx.conf.<timestamp>.<pid>`), the line
  `include <nginx dir>/conf.d/*.conf;` is added just before the closing brace
  of the `http` block, and `nginx -t` must pass; if it fails `nginx.conf` is
  restored and the action stops. No `http` block, an unreadable layout or a
  missing `nginx.conf` also stop the action with an explanation (nothing is
  guessed). A missing `conf.d` directory is created.

#### The one rule: test before reload

`nginx -t` must pass before nginx is reloaded or restarted, every time. A
change whose test fails is **rolled back** (new files removed, an overwritten
or removed site restored byte for byte, `nginx.conf` or a disabled
`default.conf` restored), nginx is left
alone, the nginx error output is shown, and the menu continues. A reload is
only attempted when the `nginx` service is running; otherwise ezvps says the
config is valid and nothing was reloaded.

#### Install source: nginx.org stable only

nginx is **never** installed from the Debian or Ubuntu repository and **never**
from the nginx.org mainline branch. The only source is the official nginx.org *stable*
repository, so the installed version is **stable 1.30 or newer** (stable
branches have an even minor number; 1.31 is mainline).

| Item | Value |
|------|-------|
| apt source (`/etc/apt/sources.list.d/nginx.list`) | `deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] <repo> <codename> nginx` (stable). `<repo>` and `<codename>` follow the detected system (`ngx_select_repo`): **Debian 13:** `https://nginx.org/packages/debian` + `trixie`; **Ubuntu 24.04 LTS:** `https://nginx.org/packages/ubuntu` + `noble`. The codename is `VERSION_CODENAME` from `/etc/os-release` and must match the supported release (an Ubuntu 24.04 file that says `jammy`, or a Debian 13 file that says `noble`, is refused); a missing codename or any other distro is refused. |
| signing key | `https://nginx.org/keys/nginx_signing.key`, dearmored into `/usr/share/keyrings/nginx-archive-keyring.gpg` |
| key check | every primary key in the downloaded file must have one of the **pinned fingerprints** (`NGX_ORG_KEY_FPRS` in `ezvps`: `8540A6F18833A80E9C1653A42FD21310B49F6B46`, `573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62`, `9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3`); anything else, or no key, is refused before anything is written. If nginx.org rotates its keys the install refuses until the pins are updated here and in the script. |
| apt pin (`/etc/apt/preferences.d/99nginx`) | `Package: *` / `Pin: origin nginx.org` / `Pin-Priority: 900`, so later upgrades stay on nginx.org and the distribution's `nginx` (priority 500) can never win |
| download | only the key, with `curl --proto '=https' --tlsv1.2`, into a private temp dir, in `ngx_fetch_key` (the only Nginx function that may use `curl`) |

Install steps:

1. Root and a supported system (Debian 13 or Ubuntu 24.04 LTS, section 1.1) and a
   readable codename matching it; otherwise refuse, nothing changed.
2. **What is installed already?** (apt package `nginx` via `dpkg-query`, else the
   `nginx` command):
   * nginx.org package, stable >= 1.30 (`<version>~<codename>`): do not
     reinstall; print `Nginx is already installed (...). Not reinstalling` and
     the Status block (plus a warning if the apt pin file is missing);
   * `nginx` command but no apt package (built by hand): not touched, same
     message;
   * a package that is **not** from nginx.org (for example Debian's or Ubuntu's own), or an
     nginx.org package that is mainline or older than 1.30: it is **replaced**
     (see below);
   * nothing: fresh install.
3. A `nginx.org/packages/mainline` source anywhere in apt's config
   (`sources.list`, `sources.list.d/*`, comments ignored) is refused: the pin
   could otherwise select a mainline build. Nothing is changed.
4. Fresh install only: if port 80 is already in use (`ss`, else a `/dev/tcp`
   connect) warn, show who listens (`ss -ltnp`) and ask whether to install
   anyway.
5. Show the plan (repository line, key URL, pin, version rule, what is
   replaced) and ask once. If `curl` or `gpg` is missing the plan says so and
   they (`curl gnupg ca-certificates`) are installed with `apt-get` first.
6. Download and verify the key (above); write the keyring, the apt source and
   the pin (an identical existing file is left alone, a different one is backed
   up as `/var/backups/ezvps/apt-<name>.<timestamp>.<pid>` first); `apt-get
   update -q`. A failure here rolls the new files back and stops.
7. **Candidate check before anything is removed or installed**: `apt-cache
   policy nginx` must name a candidate ending in `~<codename>` (nginx.org),
   stable and >= 1.30. A Debian/Ubuntu candidate (the pin is not working), a
   candidate built for another codename, a mainline (1.31) candidate, an older
   one or none: refuse, roll the repository files back, leave any installed
   nginx alone. This is the "never install over a Debian/Ubuntu nginx without
   the pin" guard.
8. Replacing another nginx (only after step 7 passed): `/etc/nginx` is backed
   up first to `/var/backups/ezvps/nginx-etc.<timestamp>.<pid>`; then the old
   packages (`nginx`, `nginx-common`, `nginx-*`, `libnginx-mod-*`) are
   **purged** so the nginx.org package installs its own clean configuration.
   A failing purge stops the install and says where the backup is.
9. `DEBIAN_FRONTEND=noninteractive apt-get install -y -q -o
   Dpkg::Options::=--force-confold nginx`.
10. **Version check** with `nginx -v` (and `dpkg-query`): abort with a clear
    error, without starting nginx or restoring anything, if the package is
    still a Debian/Ubuntu version (not `~<codename>`), if the version is below 1.30,
    or if it is a mainline build (odd minor, such as 1.31). The error names
    the backup of the previous `/etc/nginx` when one was taken.
11. `systemctl enable --now nginx`; `nginx -t`.
12. If a package was replaced, **restore/migrate the ezvps sites** from the
    backup: ezvps-made old-layout sites (if the purge removed them they are put
    back first) are moved to `conf.d` with the usual migration (backup, copy,
    config test, remove, config test); ezvps-made `conf.d/<domain>.conf` files
    that are missing are copied back; then `nginx.conf` is checked for the
    `conf.d` include and `nginx -t` must pass **before any reload**. If the
    test fails the restored files are removed again, nginx is not reloaded and
    the backup path is shown. Hand-written sites are not restored
    automatically; they are listed with the backup path, as is the old
    default site.
13. **Verify it responds** (pure bash `/dev/tcp` HEAD, retried up to 15 s) and
    print the HTTP-only / Certificates note.

#### 2) Status

Read-only: installed + version, service running/not running and enabled at
boot, **config test passes/FAILS** (with the nginx error output when it
fails), and whether it responds on port 80.

#### 3) Restart

Runs the config test **first**. Test fails: `nginx was NOT restarted or
reloaded`, error output shown, nothing else happens. Test passes:
`systemctl restart nginx`, then the same responds check. Never reloads or
restarts a broken config.

#### 4) List sites

Offers the legacy migration first if there is anything to migrate (see
Migration), then lists `/etc/nginx/conf.d/*.conf` as a table
`NAME  DOMAIN  UPSTREAM  CREATED BY`:

* sites created by ezvps: domain and upstream from the markers, `ezvps`;
* any other `*.conf` file: its first `server_name`, no upstream, `not ezvps`;
* a dangling symlink or a non-regular file is flagged.

Files in `conf.d` that do not end in `.conf` are not loaded by nginx and are
not listed; `sites-available`/`sites-enabled` are not listed. If `nginx.conf`
does not include `conf.d` a warning says the listed sites are not loaded.
Apart from the migration offer it is read-only.

#### 5) Add site

1. Needs nginx installed. Offers the legacy migration if there is anything to
   migrate.
2. Asks for the **domain** (sanitised as above) and the **upstream**
   `host:port` (IPv4, hostname or `[IPv6]`; optional `http://` and trailing
   `/` are accepted and normalised; `https://` upstreams and a missing/invalid
   port are rejected). Invalid input changes nothing.
3. **No duplicates.** If another file already serves the domain
   (`server_name` in another `conf.d/*.conf`, or in a legacy `sites-enabled`
   file) the add is refused. If `conf.d/<domain>.conf` exists: identical
   (ezvps-made, same upstream) => `Nothing to do`, no change, no reload;
   otherwise it is described and ezvps **asks before overwriting**, then backs
   the old file up first.
4. **nginx.org default site.** The package ships `conf.d/default.conf`
   (`listen 80; server_name localhost;`). If it exists, was not made by ezvps
   and either lists the domain in `server_name` or listens on port 80 (so,
   loaded first, it answers every request that matches no `server_name`),
   ezvps warns and asks whether to disable **that file only**. Yes: it is
   backed up (`/var/backups/ezvps/nginx-default-conf.<timestamp>.<pid>`) and
   renamed to `default.conf.disabled`, which nginx does not load; it is never
   deleted, and a failing config test renames it back. No: it stays as it is.
   A symlinked `default.conf` is left alone. Files in `sites-enabled` are
   never deleted.
5. Checks that `nginx.conf` includes `conf.d` (see above).
6. Writes `/etc/nginx/conf.d/<domain>.conf` (temp file in `conf.d` + `mv`).
   The generated file is a plain `listen 80` server (plus `listen [::]:80`
   only when the kernel has IPv6, i.e. `/proc/net/if_inet6` exists; otherwise
   `nginx -t` fails on such hosts) with `proxy_pass http://<upstream>`,
   `proxy_http_version 1.1` and `Host`, `X-Real-IP`, `X-Forwarded-For`,
   `X-Forwarded-Proto`, `Upgrade`, `Connection` headers.
7. `nginx -t`: pass => reload; fail => rollback (see above: the new file is
   removed, or the previous file restored, and a disabled default site is
   renamed back). Note that nginx resolves a hostname upstream when it loads the
   config, so a name that does not resolve fails the test and the site is
   rolled back; use an IP or a resolvable name.
8. Reminders: point DNS at the server, port 80 must be open (the firewall is
   not changed here); a warning if nothing listens on a loopback upstream yet;
   the HTTP-only / Certificates note.

#### 6) Remove site

Offers the legacy migration if there is anything to migrate, asks for the
domain (sanitised as above), shows `conf.d/<domain>.conf` (and whether ezvps
created it; a file not created by ezvps gets an explicit warning), **requires
a yes**, backs the file up, deletes it, runs `nginx -t`, and reloads only if
it passes (otherwise the file is restored and nginx is not reloaded). An
unknown domain changes nothing. Nothing in `sites-enabled` is touched.

#### Migration from the legacy layout

Earlier ezvps versions wrote `sites-available/<domain>` plus a symlink in
`sites-enabled`. List sites, Add site and Remove site look for **ezvps-made**
files there (regular files in `sites-available` that carry the
`# Managed by ezvps` marker with a valid `# ezvps:domain=`) and offer to move
them. Hand-written files are never migrated or touched.

* Only a site that is **enabled** (a `sites-enabled` symlink to that file) and
  whose `conf.d/<domain>.conf` does not exist yet is moved; a disabled one
  would be switched on by conf.d, and an existing conf.d file is never
  overwritten. Those stay where they are and are named in the warning.
* On yes: `nginx.conf` is checked/fixed first; every file and symlink is
  backed up (`nginx-legacy-<domain>.<ts>.<pid>` and
  `nginx-legacy-<domain>.enabled.<ts>.<pid>`); the files are **copied** to
  `conf.d/<domain>.conf`; `nginx -t` must pass; only then the `sites-enabled`
  symlink and the `sites-available` file are removed; `nginx -t` runs again
  and nginx is reloaded only if it passes. A failure at any step restores the
  legacy files and removes the copies, and nginx is not reloaded.
* On no: nothing is changed, and ezvps **warns that those sites are still in
  the legacy layout** (they keep working, but ezvps no longer manages them).
  The offer comes back the next time one of the three actions is used.

#### Backups

Before overwriting, removing, migrating or editing a file, it is copied to
`/var/backups/ezvps/` (dir mode 700): `nginx-site-<domain>.<timestamp>.<pid>`
(overwritten or removed site), `nginx.conf.<timestamp>.<pid>`,
`nginx-default-conf.<timestamp>.<pid>` (the disabled default site),
`apt-<file>.<timestamp>.<pid>` (a different apt source, pin or keyring that is replaced),
`nginx-etc.<timestamp>.<pid>` (the whole of `/etc/nginx` before a package is replaced),
`nginx-legacy-<domain>[.enabled].<timestamp>.<pid>` (migration). A failed
backup aborts the action before anything is changed. Adding a brand-new site
makes no backup (nothing existed).

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
* Requires root; **refuses** (exit 1, nothing installed) when the OS is not
  Debian 13 or Ubuntu 24.04 LTS, using the same rule as `require_supported_os`
  (section 1.1; it reads `/etc/os-release`, or `EZVPS_OS_RELEASE`, without
  sourcing it).
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
| `EZVPS_SKIP_OS_CHECK=1` | ezvps (3x-ui, Nginx, L2TP), install.sh | skip the "supported system" check only. Detection still runs: L2TP still refuses to run on Ubuntu, and Nginx still picks the repository from the detected distro (an unknown distro gets none) |
| `EZVPS_OS_RELEASE` | ezvps (3x-ui, Nginx, L2TP), install.sh | os-release file to read (default `/etc/os-release`) |
| `EZVPS_XUI_DIR` | ezvps (3x-ui) | panel install dir (default `/usr/local/x-ui`) |
| `EZVPS_XUI_DB_DIR` | ezvps (3x-ui) | panel database dir (default `/etc/x-ui`) |
| `EZVPS_STATE_DIR` | ezvps (3x-ui) | state dir (default `/var/lib/ezvps`) |
| `EZVPS_BACKUP_DIR` | ezvps (3x-ui, Nginx), install.sh | backup dir (default `/var/backups/ezvps`) |
| `EZVPS_NGINX_DIR` | ezvps (Nginx) | nginx config dir (default `/etc/nginx`) |
| `EZVPS_APT_DIR` | ezvps (Nginx) | apt config dir for the nginx.org source and pin (default `/etc/apt`) |
| `EZVPS_KEYRING_DIR` | ezvps (Nginx) | where `nginx-archive-keyring.gpg` is stored (default `/usr/share/keyrings`) |
| `EZVPS_NGINX_HTTP_PORT` | ezvps (Nginx) | port used for the port-in-use check and the responds probe (default `80`; generated sites always listen on 80) |
| `EZVPS_IF_INET6_FILE` | ezvps (Nginx) | file whose existence means "kernel has IPv6" (default `/proc/net/if_inet6`) |
| `EZVPS_NGINX_WAIT_SECONDS` | ezvps (Nginx) | how long to wait for nginx to answer (default 15) |
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
  Nginx is tested against a **fake `nginx`** (its version comes from the fake
  dpkg state; its `-t` fails on a site containing `BROKEN_DIRECTIVE`, on a
  named domain, on the Nth call, or always on request) with stub `systemctl`,
  `apt-get`, `apt-cache`, `dpkg-query`, `gpg`, `curl` (the key download), `ss`,
  and a small local HTTP server standing in for "nginx answers on port 80"
  (those checks are skipped without `python3`). The fake apt installs Debian's
  package unless both the nginx.org source and the pin exist, which is how the
  tests prove the pin matters. Covered: submenu labels; install detection
  (nginx.org stable, dpkg only, built by hand: no reinstall, no apt call);
  fresh install from nginx.org stable (key download flags, pinned
  fingerprints, keyring/source/pin contents, order key -> update -> install,
  `nginx -v` check, enable --now, config test, verify), identical or different
  repository files, wrong/extra key fingerprint, key download failure, a
  mainline source in apt, a candidate that is Debian / mainline 1.31 / older /
  missing (nothing installed, repository files rolled back), an installed
  build that is mainline / below 1.30 / a Debian version (abort, not started),
  declined / non-Debian / missing codename / apt failure / missing curl+gpg /
  port 80 busy; replacing a Debian nginx (backup of `/etc/nginx` before the
  purge, order, sites kept or restored from the backup, old-layout sites
  migrated, hand-written sites listed not restored, failing config test after
  the restore, no working pin leaves Debian's nginx untouched, wrong version
  after install, nginx.org mainline replaced); status
  (running, stopped, failing config); restart with the config test before the
  restart, and a failing test that must neither restart nor reload; against a
  **fake `conf.d` layout** (a fixture `nginx.conf`, `conf.d/`, and the legacy
  directories for the negative and migration cases): list sites (ezvps,
  foreign, dangling, non-`.conf` files, legacy files not listed); add site
  (generated `conf.d/<domain>.conf`, nothing created in `sites-*`, test
  before reload, no duplicates on re-run, overwrite with backup, declined
  overwrite, domain sanitising incl. path separators, input validation,
  conflicts with `conf.d` and legacy files, failing test rolls back and does
  not reload, nginx stopped); missing `conf.d` include in `nginx.conf` (backup,
  inserted once inside `http`, commented-out include ignored, failing test
  restores, no `http` block, no `nginx.conf`); the nginx.org
  `default.conf` (ask, backup and rename to `default.conf.disabled`, restore
  on a failing test, symlink and non-conflicting cases left alone, other
  `sites-enabled` files untouched); remove site (confirmation, backup, test
  before reload, failing test restores); migration from `sites-available`
  (accepted, declined, failing test after the copy, failing final test,
  missing include, existing `conf.d` file, disabled and hand-written sites
  left alone, re-run is a no-op); no certificate/TLS code at all.
  It touches nothing outside its temp dir and uses no network.
  `tests/lint.sh` additionally checks that the repository URL is the stable
  one (never mainline), the key URL, the fingerprint pins and the priority-900
  pin are present, and that `curl` is used only in the 3x-ui download/probe
  functions and `ngx_fetch_key`.
* **Operating systems** (`== operating systems` in the smoke test, always with
  fake os-release files in a temp dir and the check switched ON): Debian 13 and
  Ubuntu 24.04 (also with a quoted `ID="ubuntu"`) are accepted; Ubuntu 22.04,
  Debian 12, an unknown distro (Fedora), a derivative whose `ID_LIKE` says
  ubuntu (Linux Mint), a Debian without `VERSION_ID` and a missing file are
  rejected with the exact message, by 3x-ui, Nginx, L2TP and `install.sh`, and
  nothing is changed. Nginx repository selection: the plan and
  `nginx.list` carry `packages/debian ... trixie` on Debian and
  `packages/ubuntu ... noble` on Ubuntu (never the other path, never mainline);
  the fake apt only honours the pin when the source line names the right path
  and codename, which is how the tests prove it. A full fake install flow runs
  on both systems (key check, order key -> update -> install, `~<codename>`
  package, version check, enable, config test, no-op re-run) as does the
  replacement of the distribution's own nginx (backup of `/etc/nginx` before the
  purge, restore of the ezvps sites), plus Ubuntu refusals (pin not working,
  wrong repository path, mainline source/candidate, old candidate, candidate for
  another codename, Ubuntu package after install, wrong or missing codename).
  L2TP on Ubuntu prints the Debian-only message, does not launch ezl2tp even
  when it is present and shows no install instructions. A default 3x-ui install
  runs on Ubuntu 24.04.
* `tests/fresh-vps-test.md`: manual checklist on a throwaway Debian 13 VPS and
  on a throwaway Ubuntu 24.04 LTS VPS.
