# ezvps SPEC

Version: 0.0.1 (in development). This file is the source of truth for scope.
Each later PR implements one module from the list below and updates the
status table here. Done so far: L2TP (PR 1), 3x-ui (PR 2), Nginx (PR 3, conf.d in PR 4, nginx.org stable in PR 5), Ubuntu 24.04 LTS support (PR 6), Debian and Ubuntu LTS family support (PR 7), Certificates and the new Nginx site template (PR 8).

## 1. What ezvps is

A bash TUI/CLI VPS manager for the **Debian and Ubuntu LTS families**
(Debian 12 and 13; Ubuntu 22.04, 24.04 and 26.04 LTS), run as **root**. One
script, installed as `/usr/local/bin/ezvps`. It has no dependencies beyond what
a supported install already has (bash, coreutils, systemd); anything else a
module needs is checked with `command -v` first and installed only with the
user's say-so (3x-ui: `curl`; Nginx: `curl`, `gnupg` and the nginx.org `nginx` package itself;
Certificates: `curl` and the pinned acme.sh script).

### 1.1 Supported systems

The allowlist is exactly these five `ID` + `VERSION_ID` + `VERSION_CODENAME`
triples:

| System | Version | Codename | Status |
|--------|---------|----------|--------|
| Debian | 12 | `bookworm` | **supported** (PR 7) |
| Debian | 13 | `trixie` | **supported** |
| Ubuntu | 22.04 LTS | `jammy` | **supported** (PR 7) |
| Ubuntu | 24.04 LTS | `noble` | **supported** (PR 6) |
| Ubuntu | 26.04 LTS | `resolute` | **supported** (PR 7) |
| any other | Ubuntu interim releases (23.10, 25.04, 25.10, 26.10, ...), Debian 11 and older, Debian testing/sid, Fedora, derivatives such as Linux Mint, ... | n/a | **rejected** |

Per module:

| Module | Debian 12 | Debian 13 | Ubuntu 22.04 | Ubuntu 24.04 | Ubuntu 26.04 |
|--------|-----------|-----------|--------------|--------------|--------------|
| 3x-ui | yes | yes | yes | yes | yes |
| Nginx | yes: `nginx.org/packages/debian`, suite `bookworm` | yes: `.../debian`, `trixie` | yes: `nginx.org/packages/ubuntu`, suite `jammy` | yes: `.../ubuntu`, `noble` | yes: `.../ubuntu`, `resolute` |
| Certificates (acme.sh) | yes | yes | yes | yes | yes |
| L2TP (ezl2tp) | **no** (gate below) | yes | **no** (gate below) | **no** (gate below) | **no** (gate below) |

* **L2TP has its own gate.** ezvps running on a system does not mean ezl2tp
  does. L2TP is available only on the systems ezl2tp supports, listed in one
  place (`L2TP_SUPPORTED` in `ezvps`), currently **Debian 13 only**. ezl2tp is
  not ported in this release and ezvps never claims L2TP works elsewhere. When
  ezl2tp gains a system, only that list changes (and this table).
* **One shared check.** `detect_os` reads `/etc/os-release` (the `ID`,
  `VERSION_ID` and `VERSION_CODENAME` lines; the file is parsed, never sourced,
  and `ID_LIKE` is ignored) and sets `OS_ID`, `OS_VERSION`, `OS_CODENAME`.
  `os_is_supported` accepts a system only when **all three** values form one of
  the five allowlist entries above, so Ubuntu 24.04 with codename `jammy`,
  Debian 13 with `bookworm`, or Ubuntu 22.04 with no codename are rejected (a
  mismatch), as are Ubuntu 25.10, Debian 11, Debian testing/sid (no
  `VERSION_ID`), other distros, derivatives, and a missing or unreadable file.
  `require_supported_os "<action>"` runs it and refuses with one message built
  by `os_unsupported_message`:
  `<action> needs a supported system: Debian 12 (bookworm), Debian 13 (trixie),
  Ubuntu 22.04 LTS (jammy), Ubuntu 24.04 LTS (noble) or Ubuntu 26.04 LTS
  (resolute); found '<id> <version> <codename>'. Nothing was changed.` (for a
  recognised version with the wrong codename the text
  `(the codename does not match the version; <id> <version> is '<codename>')`
  follows `found '...'`), and the module returns to the menu. The 3x-ui and Nginx
  installs, the acme.sh install and Issue certificate, L2TP and `install.sh` all use
  this rule. `install.sh` cannot source
  `ezvps`, so the block between `# BEGIN ezvps-os-allowlist` and `# END
  ezvps-os-allowlist` is a verbatim copy in both files, and `tests/lint.sh`
  fails if the two differ or the list changes.
* **Branch on the distro only where they differ,** with a comment: the nginx.org
  repository path (6.3) and the L2TP gate (6.1). Everything else is one code path.
* **Audit of version differences** (done for PR 7; re-check it when a module is
  added). Checked against the real package, service and repository names, not
  assumed:

  | Area | Debian 12 / 13 | Ubuntu 22.04 / 24.04 / 26.04 | Result |
  |------|----------------|------------------------------|--------|
  | L2TP | ezl2tp: Debian 13 only | not supported by ezl2tp | gate list (`L2TP_SUPPORTED`): a message and return everywhere else |
  | 3x-ui installer | pinned upstream `install.sh` (v3.11.0) branches on `ID` (`ubuntu \| debian \| armbian`) only; `VERSION_ID` matters only for CentOS 7 | same code path | one path |
  | 3x-ui paths and service | `/usr/local/x-ui`, `/etc/x-ui`, `x-ui.service` | identical | one path |
  | apt tooling | `apt-get`, `apt-cache`, `dpkg-query` | identical | one path |
  | nginx package and service names | `nginx`, `nginx-common`, `libnginx-mod-*`, `nginx.service` | identical | one path |
  | nginx.org repository | `packages/debian`, suite `bookworm` / `trixie` | `packages/ubuntu`, suite `jammy` / `noble` / `resolute` | branch: path from the distro, suite is the detected codename. All five suites exist on nginx.org and carry stable 1.30.x builds |
  | nginx.org package version suffix | `~bookworm` / `~trixie` | `~jammy` / `~noble` / `~resolute` | one path (suffix is the detected codename) |
  | distribution's own nginx | Debian's `...+deb12u...` / `...+deb13u...` | Ubuntu's `...ubuntu...` | one path (anything not ending in `~<codename>` is replaced) |
  | `/etc/nginx` layout and nginx.org `conf.d/default.conf` | `sites-*` plus `conf.d` for the distro package; `conf.d` only for nginx.org | identical | one path |
  | signing key, pin | `nginx.org` key fingerprints, `origin nginx.org` at 900 | identical | one path |
  | apt source file format | `nginx.list` one-line source; the mainline scan reads every file under `sources.list.d`, so deb822 `.sources` files are covered | identical | one path |
  | prerequisites (`curl`, `gnupg`, `ca-certificates`) | same package names | same package names | one path |
  | acme.sh (PR 8) | the same pinned script, `bash ./acme.sh --install`; needs `openssl` (always present), `curl`, optionally `crontab` | identical | one path |
  | `http2 on;` in the HTTPS site (PR 8) | needs nginx 1.25.1+; the module only ever installs nginx.org stable 1.30+ | identical | one path |
  | certificate store `/etc/ssl/ezvps` (PR 8) | no package owns it | no package owns it (Ubuntu's `ssl-cert` group is not used) | one path |

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
| 6 | Certificates      | **implemented**     | PR 8       |
| 7 | Lazyports         | not implemented yet | later      |
| 8 | SSH and Users     | not implemented yet | later      |
| 9 | Firewall          | not implemented yet | later      |
| 10| Backup            | not implemented yet | later      |
| 11| Check For Updates | not implemented yet | later      |
| 12| Uninstall         | not implemented yet | later      |

One module per PR. Every implemented module runs on all five supported systems
(section 1.1), **except L2TP, which is Debian 13 only** for now (the ezl2tp gate).

### 6.1 L2TP (PR 1, done; Debian 13 only, gated by ezl2tp)

* **Debian 13 only for now.** L2TP is gated by ezl2tp's own requirements, not
  by ezvps's. ezl2tp is not ported in PR 7 (or earlier) and ezvps does not try.
  The module first applies the shared OS check: an unsupported system is
  refused (`L2TP needs a supported system: ...; found ...`). Then it checks the
  ezl2tp list (`L2TP_SUPPORTED`, currently only `debian 13 trixie`). On any
  other supported system (Debian 12, Ubuntu 22.04, 24.04, 26.04) it prints
  `L2TP via ezl2tp is Debian 13 only for now (found <System> <version>,
  <codename>).` and `ezvps does not launch or install ezl2tp on this system.
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
2. A supported system (`require_supported_os`, section 1.1); otherwise refuse,
   nothing changed.
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

**Add site writes plain HTTP.** The Nginx menu never issues or stores a
certificate, and the site Add site writes has no `listen 443` / `ssl_*`
directives. HTTPS is added afterwards by the Certificates module (section 6.4),
which rewrites that one ezvps-made site file. List sites, Add site and Remove
site work with such a site like with any other.

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
  older sites-available layout used, so old files can be moved unchanged). A
  site the Certificates module switched to HTTPS also has `# ezvps:https=on`.
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
| apt source (`/etc/apt/sources.list.d/nginx.list`) | `deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] <repo> <suite> nginx` (stable). `<repo>` follows the distro and `<suite>` is the detected codename (`ngx_select_repo`): **Debian 12:** `https://nginx.org/packages/debian` + `bookworm`; **Debian 13:** `.../packages/debian` + `trixie`; **Ubuntu 22.04 LTS:** `https://nginx.org/packages/ubuntu` + `jammy`; **Ubuntu 24.04 LTS:** `.../packages/ubuntu` + `noble`; **Ubuntu 26.04 LTS:** `.../packages/ubuntu` + `resolute`. The codename is `VERSION_CODENAME` from `/etc/os-release` and must form an allowlist entry with the distro and `VERSION_ID` (section 1.1): an Ubuntu 24.04 file that says `jammy`, a Debian 13 file that says `noble`, or an unlisted release is refused (also when the test-only `EZVPS_SKIP_OS_CHECK` is set), and a missing codename or any other distro is refused. |
| signing key | `https://nginx.org/keys/nginx_signing.key`, dearmored into `/usr/share/keyrings/nginx-archive-keyring.gpg` |
| key check | every primary key in the downloaded file must have one of the **pinned fingerprints** (`NGX_ORG_KEY_FPRS` in `ezvps`: `8540A6F18833A80E9C1653A42FD21310B49F6B46`, `573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62`, `9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3`); anything else, or no key, is refused before anything is written. If nginx.org rotates its keys the install refuses until the pins are updated here and in the script. |
| apt pin (`/etc/apt/preferences.d/99nginx`) | `Package: *` / `Pin: origin nginx.org` / `Pin-Priority: 900`, so later upgrades stay on nginx.org and the distribution's `nginx` (priority 500) can never win |
| download | only the key, with `curl --proto '=https' --tlsv1.2`, into a private temp dir, in `ngx_fetch_key` (the only Nginx function that may use `curl`) |

Install steps:

1. Root and a supported system (section 1.1) with a readable codename that
   matches its version; otherwise refuse, nothing changed.
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
`NAME  DOMAIN  UPSTREAM  CREATED BY`. **Every** `*.conf` file is parsed, ezvps-made
or not, and its `proxy_pass` upstream is shown when it has one:

* `DOMAIN`: sites created by ezvps use the `# ezvps:domain=` marker, any other
  file its first `server_name`;
* `UPSTREAM`: the first `proxy_pass` target found in the file (comments are
  ignored; it may sit on a one-line `location / { proxy_pass ...; }`), shown
  without the leading `http://` (`127.0.0.1:3000`, `backend.internal:9000/api/`);
  a non-http scheme is kept (`https://192.0.2.9:8443`); with several distinct
  targets the first one is followed by `(+N more)`; `-` when the file has none
  (static sites, `return`, a commented-out `proxy_pass`). An ezvps-made file
  without any `proxy_pass` falls back to its `# ezvps:upstream=` marker, and
  when both exist the real `proxy_pass` wins;
* `CREATED BY`: exactly `ezvps` (the file carries the ezvps marker) or
  `not ezvps`;
* a dangling symlink or a non-regular file is flagged.

Listing never edits a file, whoever made it.

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
6. Makes sure `nginx.conf` defines the `$connection_upgrade` map (see "The
   connection map"), then writes `/etc/nginx/conf.d/<domain>.conf` (temp file in
   `conf.d` + `mv`). The generated file is the site template below: a plain
   `listen 80` server (plus `listen [::]:80` only when the kernel has IPv6, i.e.
   `/proc/net/if_inet6` exists; otherwise `nginx -t` fails on such hosts).
7. `nginx -t`: pass => reload; fail => rollback (see above: the new file is
   removed, or the previous file restored, and a disabled default site is
   renamed back). Note that nginx resolves a hostname upstream when it loads the
   config, so a name that does not resolve fails the test and the site is
   rolled back; use an IP or a resolvable name.
8. Reminders: point DNS at the server, port 80 must be open (the firewall is
   not changed here); a warning if nothing listens on a loopback upstream yet;
   a note that the site is HTTP only and that Certificates -> Issue certificate
   can enable HTTPS for it.

#### The site template (PR 8)

One file per domain, `conf.d/<domain>.conf`. The reverse-proxy part is shared by
the HTTP form (Add site) and the HTTPS server block (Certificates), so both proxy
identically. Plain form, exactly as written (IPv6 line only on IPv6 hosts):

```
# Managed by ezvps (Nginx module). Reverse proxy; edit via ezvps or keep the markers.
# ezvps:domain=example.com
# ezvps:upstream=127.0.0.1:3000
server {
    listen 80;
    server_name example.com;

    client_max_body_size 64M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_connect_timeout 60s;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
}
```

`Connection` is **not** hardcoded to `upgrade` (that would turn every request
into a protocol upgrade request and break keep-alive to the backend): it comes
from the `$connection_upgrade` map, which is `upgrade` for a request that sent an
`Upgrade` header (WebSocket) and `close` otherwise. Existing sites written by an
older ezvps keep their old text until Add site overwrites them or the
Certificates module rewrites them.

#### The connection map (PR 8)

Before any ezvps site that uses `$connection_upgrade` is written (Add site, and
the Certificates module when it rewrites a site), `nginx.conf` must define it
exactly once in the `http` context:

```
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }
```

* **Already defined = untouched.** A non-comment `map $http_upgrade
  $connection_upgrade {` line in `nginx.conf`, in any `conf.d/*.conf` or in a
  legacy `sites-enabled` file counts, so the map is never duplicated (a second
  definition would make `nginx -t` fail).
* Missing: `nginx.conf` is backed up first (`nginx.conf-map.<timestamp>.<pid>`,
  a different name from the conf.d-include backup so both survive), the map is
  inserted inside `http`, just before its `include .../conf.d/*.conf;` line (else
  before the closing brace), and **`nginx -t` must pass**; a failing test restores
  `nginx.conf` byte for byte, nothing is written or reloaded, and the action
  stops. No `http` block or a missing `nginx.conf` also stop the action with an
  explanation.
* The order of the checks in every writing action is: conf.d include, then map,
  then the site file.

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
(overwritten or removed site), `nginx.conf.<timestamp>.<pid>`, `nginx.conf-map.<timestamp>.<pid>` (before the
connection map is added),
`nginx-default-conf.<timestamp>.<pid>` (the disabled default site),
`apt-<file>.<timestamp>.<pid>` (a different apt source, pin or keyring that is replaced),
`nginx-etc.<timestamp>.<pid>` (the whole of `/etc/nginx` before a package is replaced),
`nginx-legacy-<domain>[.enabled].<timestamp>.<pid>` (migration). A failed
backup aborts the action before anything is changed. Adding a brand-new site
makes no backup (nothing existed).

### 6.4 Certificates (PR 8, done)

Menu item 6 opens a submenu. Clean labels only:

```
 1) Install acme.sh
 2) Issue certificate
 3) List certificates
 4) Renew certificates
 5) Remove certificate
 0) Back
```

`0` or EOF returns to the main menu; after each action "Press Enter to
continue..."; invalid input prints `Invalid choice: <input>`. Module key `certs`
maps to `module_certs`; its helpers are prefixed `cert_` / `acme_`.

**Scope: one domain, HTTP-01 through nginx, Let's Encrypt.** Out of scope, and
refused or absent on purpose: wildcard certificates, DNS API / DNS-01 validation,
asking for or storing **any** DNS provider credential, several domains in one
certificate, a certificate shared between sites, `stream` blocks (HTTPS is served
on 443 by an ordinary `server` block, never behind a `stream` and never on
4443), Xray, and certbot. Input such as `*.example.com`, `a.com,b.com` or `a.com b.com`
is rejected with a message that says so.

#### acme.sh: source, pin, install

* Project: <https://github.com/acmesh-official/acme.sh> (public, the official
  acme.sh).
* **Exact URL** ezvps downloads (the `acme.sh` script at release tag **3.1.6**,
  never a branch):
  `https://raw.githubusercontent.com/acmesh-official/acme.sh/3.1.6/acme.sh`
* Expected SHA-256 of that file (294,737 bytes):
  `c7d68b021cfd6380ea83a82962abde5b484779fee0b97d38681dfa1396bbc8d7`
* The pin lives in `ezvps` as `ACME_UPSTREAM`, `ACME_PINNED_TAG`,
  `ACME_SCRIPT_URL` and `ACME_SCRIPT_SHA256`. To bump it: pick a newer release tag,
  download `acme.sh` at that tag, read it, update the tag and hash together and this
  section, run the tests. `tests/lint.sh` checks the pin is present and well formed.
* **Why not `curl https://get.acme.sh | sh`:** that is piped into a shell, not
  pinned, and installs from a moving branch. ezvps downloads one file to a private
  temp directory (`curl --proto '=https' --tlsv1.2`, in `acme_fetch_script`, the only
  place acme.sh is fetched), verifies the SHA-256, **refuses to run it on a
  mismatch**, and runs it as `bash ./acme.sh --install --home <home> --no-profile`
  from that directory. Only the script is installed: acme.sh's `dnsapi`, `deploy` and
  `notify` plug-in folders are not needed for HTTP-01 and are not fetched (its own
  `--install` copies them only when present, checked in the 3.1.6 source).
* Home: `$HOME/.acme.sh` (`/root/.acme.sh`). `--no-profile` keeps acme.sh from adding
  an alias to the shell profile; ezvps always calls it by full path
  (`<home>/acme.sh --home <home> ...`).
* **Renewal job.** Unless `--nocron` applies, acme.sh's own `--install` adds its daily
  `acme.sh --cron` entry to root's crontab. The plan says so; the current crontab
  (when it is not empty) is first copied to
  `/var/backups/ezvps/crontab-root.<timestamp>.<pid>` (mode 600). Without a
  `crontab` command the install runs with `--nocron`, the plan and the install end
  with a warning, and certificates must be renewed with Renew certificates. ezvps
  never sets acme.sh's `AUTO_UPGRADE`: the `account.conf` that the 3.1.6 `--install`
  writes only has it as a commented-out example, and acme.sh's cron job upgrades the
  script only when `AUTO_UPGRADE="1"` is set there (verified by running the real
  install), so the pinned script is not replaced behind the pin.
* **Certificate authority:** every issue passes `--server letsencrypt`. acme.sh 3.x
  defaults to ZeroSSL, which needs an account with an e-mail address; Let's Encrypt
  needs neither, so ezvps asks for no e-mail and stores none.

#### Certificate store and backups

* `/etc/ssl/ezvps/<domain>/fullchain.pem` (mode 644) and
  `/etc/ssl/ezvps/<domain>/privkey.pem` (**mode 600, root only**). `/etc/ssl/ezvps`
  and `/etc/ssl/ezvps/<domain>` are mode 700. The files are written by
  `acme.sh --install-cert`, so renewals (cron or Renew certificates) refresh the same
  paths, and ezvps then sets the modes. nginx's master process (root) reads them.
* **Never printed.** ezvps never reads or prints `privkey.pem`. acme.sh's own output
  is shown, but anything between private-key markers is replaced by
  `(private key material hidden)`.
* Before a certificate directory is replaced or removed it is copied (`cp -a`,
  so file modes are kept) to `/var/backups/ezvps/cert-<domain>.<timestamp>.<pid>`
  (backup dir mode 700). A failed backup aborts before anything is changed.
* `acme.sh --install-cert` is given `--reloadcmd "nginx -t && systemctl reload nginx"`,
  so acme.sh's cron renewals reload nginx too, and only with a valid config.

#### 1) Install acme.sh

1. A supported system (`require_supported_os`, section 1.1) or refuse.
2. **Already installed** (`<home>/acme.sh` executable, else `acme.sh` on `PATH`):
   print `acme.sh is already installed (<path>). Not reinstalling.`, check that
   `acme.sh --version` works, done. Nothing is downloaded or changed.
3. Needs `sha256sum` and `curl` (`curl` is offered via `apt-get` after a yes).
4. Show the plan (project, tag, exact URL, expected SHA-256, home, what the install
   does, cron status) and ask. No: nothing is changed.
5. Back up the crontab, download, verify, run the installer (a failing installer is
   reported and nothing else is done).
6. **Verify the command works afterwards:** `acme.sh --version` must print a `vX.Y.Z`
   line (`Verified: the acme.sh command works (v3.1.6, <path>)`); a different version
   than the pinned one is warned about.

#### 2) Issue certificate

Prerequisites, each refused with a message and **no change** when missing:

* a supported system; acme.sh installed (else `Choose 'Install acme.sh' first.`);
* nginx installed **and running**, with something **listening on port 80**
  (`ss`, else a `/dev/tcp` connect; nginx must answer HTTP-01, so this is checked
  before anything else; whether the internet can reach port 80 cannot be tested from
  the server, so the firewall reminder is printed instead);
* exactly one valid domain (same sanitising as the Nginx module, plus the wildcard
  and list messages above);
* an nginx `server_name` that names the domain in a loaded file (`conf.d/*.conf` or
  the legacy `sites-enabled`). acme.sh's nginx mode answers the challenge through
  the server block of the domain, so a domain with no server block at all is refused
  with `Add the site first (Nginx -> Add site)`. ezvps **never creates a site by
  itself**.

Then ezvps prints that the domain is validated with HTTP-01 through nginx, that no
DNS provider credentials are asked for or stored, and, as a warning, that **the DNS
record of the domain must point to this server before issuing** and that port 80
must be reachable from the internet; it mentions an existing stored certificate
(which will be backed up) and **asks for confirmation**. No: nothing is changed.

On yes:

1. `acme.sh --issue -d <domain> --nginx --server letsencrypt`. In nginx mode acme.sh
   (3.1.6, read in its source and run against nginx 1.30 for this PR) finds the first
   `server` block whose `server_name` names the domain and that has a non-SSL
   `listen`, saves a backup of that file, **temporarily inserts** a `location ^~
   /.well-known/acme-challenge/` right after the `server_name` line, tests and
   reloads nginx, and puts the file back afterwards.
2. `nginx -t` is run again; if it fails (acme.sh left something behind) ezvps says so,
   stores nothing and stops. Exit status 2 from acme.sh means the certificate is still
   valid and was not re-issued: ezvps says so and carries on with the existing one.
   Any other failure prints acme.sh's message and hints (DNS, port 80, rate limits),
   stores nothing and changes no site.
3. The store directory is created (modes above). An **existing certificate for the
   domain is backed up first** (`cert-<domain>.*`), then
   `acme.sh --install-cert -d <domain> --fullchain-file <store>/fullchain.pem
   --key-file <store>/privkey.pem --reloadcmd "nginx -t && systemctl reload nginx"`
   writes the files; ezvps sets the key to 600 and checks both files exist and are
   not empty. On failure the previous directory is restored byte for byte from the
   backup (or the new one removed) and the failure is reported.
4. Summary: the two paths (the key marked "never shown"), the expiry date and whether
   acme.sh's renewal job is in root's crontab (a warning when it is not).
5. **Offer HTTPS** for the site of that domain, by `conf.d/<domain>.conf` only:

| State of `conf.d/<domain>.conf` | What ezvps does |
|---|---|
| ezvps-made, plain HTTP | explains the change and **asks**; yes: see "HTTPS for an ezvps site" |
| ezvps-made, HTTPS already on | nothing to rewrite; `nginx -t`, then reload so nginx serves the new certificate |
| not made by ezvps, a symlink, broken markers, or no such file (the domain is served from a file with another name) | the certificate is **stored only**: ezvps says there is no ezvps site, creates nothing, edits nothing; how to add a site and run Issue again |

Running Issue certificate again for the same domain is safe: acme.sh skips a
certificate that is not due, the store is refreshed (with a backup) and the HTTPS
offer is made again, which is also how HTTPS is enabled for a site added later.

#### HTTPS for an ezvps site

Only an ezvps-made site (valid markers, the domain's own `conf.d/<domain>.conf`) is
rewritten, and only that file. The order is: `nginx.conf` checks (conf.d include,
then the connection map, as in 6.3) -> **backup of the site file**
(`nginx-site-<domain>.<timestamp>.<pid>`) -> write (temp file + `mv`) -> **`nginx -t`**
-> reload. A failing test **restores the file byte for byte**, does not reload nginx
and keeps the certificate stored. The file becomes (IPv6 lines only on IPv6 hosts):

```
# Managed by ezvps (Nginx module). Reverse proxy; edit via ezvps or keep the markers.
# ezvps:domain=example.com
# ezvps:upstream=127.0.0.1:3000
# ezvps:https=on
server {
    listen 80;
    server_name example.com;

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name example.com;

    ssl_certificate /etc/ssl/ezvps/example.com/fullchain.pem;
    ssl_certificate_key /etc/ssl/ezvps/example.com/privkey.pem;

    client_max_body_size 64M;

    location / {
        (the same proxy block as the plain template in 6.3)
    }
}
```

* HTTPS listens on **443 ssl directly** (not 4443, no `stream`). `http2 on;` needs
  nginx 1.25.1+, which holds because ezvps installs nginx.org stable 1.30+ only.
* The redirect is a 301 to `https://$host$request_uri` and lives **inside**
  `location /` on purpose: a server-level `return` is executed before locations are
  matched, which would stop acme.sh's temporary `location ^~
  /.well-known/acme-challenge/` from answering renewals through the HTTP block.
  (Checked with the real acme.sh nginx mode against nginx 1.30: the challenge path
  answers `200`, every other path still gets the 301.)
* Port 443 must be open; the firewall is not changed here.

#### 3) List certificates

Read-only. For each directory in `/etc/ssl/ezvps` a row `DOMAIN  EXPIRES  NGINX SITE`:

* `EXPIRES`: `YYYY-MM-DD (N days left)` or `YYYY-MM-DD (EXPIRED)`, read from
  `fullchain.pem` with `openssl x509 -enddate`; `unknown (openssl not installed)`,
  `no certificate file` or `unreadable certificate` otherwise;
* `NGINX SITE`: `yes (<file>.conf[, ...])` when a `conf.d/*.conf` file has an
  `ssl_certificate` pointing at this domain's stored `fullchain.pem` (made by ezvps or
  not), else `no`.

No certificate: `(none)`. Works without acme.sh and without nginx.

#### 4) Renew certificates

Runs `acme.sh --renew-all` (acme.sh renews what is due and skips the rest; its
`--install-cert` settings copy the new files into the store). Before and after, every
`<acme home>/*/fullchain.cer` and `/etc/ssl/ezvps/*/fullchain.pem` is compared by
content (pure bash). **Nothing changed** -> `No certificate was renewed ... nginx was
not reloaded.` **Something changed** -> `nginx -t`, and nginx is reloaded only if it
passes; a failing test prints the nginx error and does **not** reload. An acme.sh
error is reported but the change check still decides about the reload. Without nginx
there is nothing to reload.

#### 5) Remove certificate

1. Asks for the domain (sanitised as above). No such directory in the store: nothing
   is changed.
2. If nginx is installed, every `conf.d/*.conf` that uses this certificate must be the
   domain's own ezvps HTTPS site; any other file (hand-written, or the site of another
   domain) makes ezvps **refuse before changing anything**, because it would break
   when the files disappear and ezvps does not edit files it did not make.
3. Shows the plan and **requires a yes**.
4. Backs up the certificate directory (including the key, mode 600 kept).
5. For an ezvps HTTPS site: the **HTTPS block is removed and the plain HTTP proxy block
   restored** by rewriting the file from its markers (same procedure and rollback as
   "HTTPS for an ezvps site": `nginx.conf` checks, **backup of the site file first**,
   write, **`nginx -t`**). A failing test restores the HTTPS site, **keeps the
   certificate** and the acme.sh renewal, and does not reload nginx.
6. Only after the site is valid: deletes `/etc/ssl/ezvps/<domain>`, runs
   `acme.sh --remove -d <domain>` (so acme.sh's renewal does not recreate the files;
   a failure there is a warning), and reloads nginx if the site changed.
7. acme.sh keeps its own copy of the files in `<acme home>/<domain>`; the message says
   so and leaves deleting it to the user.

#### Known limits

* The domain must already be served by an nginx `server` block (see Issue).
* Only ezvps-made sites are switched to HTTPS or back; ezvps rewrites such a file
  from its markers, so hand edits inside an ezvps-made file are lost (the old file is
  backed up first, as with Add site's overwrite).
* A certificate is not removed while a file ezvps did not make uses it.

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
  in the supported list, using the same allowlist, check and error text as
  `require_supported_os` (section 1.1; a verbatim copy of the same block, kept
  identical by lint; it reads `/etc/os-release`, or `EZVPS_OS_RELEASE`, without
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
| `EZVPS_SKIP_OS_CHECK=1` | ezvps (3x-ui, Nginx, Certificates, L2TP), install.sh | skip the "supported system" check only. Detection still runs: L2TP is still gated by the ezl2tp list, and Nginx still picks the repository from the detected distro and codename and still refuses an unknown distro, an unlisted release or a codename mismatch (none gets a repository) |
| `EZVPS_OS_RELEASE` | ezvps (3x-ui, Nginx, Certificates, L2TP), install.sh | os-release file to read (default `/etc/os-release`) |
| `EZVPS_XUI_DIR` | ezvps (3x-ui) | panel install dir (default `/usr/local/x-ui`) |
| `EZVPS_XUI_DB_DIR` | ezvps (3x-ui) | panel database dir (default `/etc/x-ui`) |
| `EZVPS_STATE_DIR` | ezvps (3x-ui) | state dir (default `/var/lib/ezvps`) |
| `EZVPS_BACKUP_DIR` | ezvps (3x-ui, Nginx, Certificates), install.sh | backup dir (default `/var/backups/ezvps`) |
| `EZVPS_NGINX_DIR` | ezvps (Nginx) | nginx config dir (default `/etc/nginx`) |
| `EZVPS_APT_DIR` | ezvps (Nginx) | apt config dir for the nginx.org source and pin (default `/etc/apt`) |
| `EZVPS_KEYRING_DIR` | ezvps (Nginx) | where `nginx-archive-keyring.gpg` is stored (default `/usr/share/keyrings`) |
| `EZVPS_NGINX_HTTP_PORT` | ezvps (Nginx) | port used for the port-in-use check and the responds probe (default `80`; generated sites always listen on 80) |
| `EZVPS_IF_INET6_FILE` | ezvps (Nginx) | file whose existence means "kernel has IPv6" (default `/proc/net/if_inet6`) |
| `EZVPS_NGINX_WAIT_SECONDS` | ezvps (Nginx) | how long to wait for nginx to answer (default 15) |
| `EZVPS_XUI_WAIT_SECONDS` | ezvps (3x-ui) | how long to wait for the panel to answer (default 30) |
| `EZVPS_ACME_HOME` | ezvps (Certificates) | acme.sh home (default `$HOME/.acme.sh`) |
| `EZVPS_CERT_DIR` | ezvps (Nginx, Certificates) | certificate store, also the path written into HTTPS sites (default `/etc/ssl/ezvps`) |
| `EZVPS_NO_PAUSE=1` | ezvps | do not wait for Enter |

## 8. Tests

* `tests/lint.sh`: `bash -n` + `shellcheck` on every script, plus a hygiene
  scan (no non-documentation IPs, key material or token patterns) and the
  download rules: `curl` only inside `xui_fetch_installer` / `xui_probe` /
  `ngx_fetch_key` / `acme_fetch_script`, no
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
  left alone, re-run is a no-op).
  The default `nginx.conf` fixture already carries the connection map, so these
  scenarios see one config test per change; the PR 8 scenarios below use a fixture
  without it.
  **Site template and connection map** (PR 8, `== Nginx site template and connection
  map`): every line of the template (body size, `proxy_http_version`, each header,
  `Connection $connection_upgrade` and not `"upgrade"`, the three timeouts, no TLS
  in the plain form); the map added to `nginx.conf` exactly once, inside `http`
  before the include, with a byte-for-byte backup and a config test that runs before
  the site exists; a second site does not duplicate it or back up again; a map
  already defined in another `conf.d` file or in a legacy `sites-enabled` file is
  not duplicated, a commented-out one is not mistaken for a real one; missing include
  plus missing map (separate backups); a failing config test after adding the map
  restores `nginx.conf`, writes no site and does not reload; no `http` block.
  List sites shows the `proxy_pass` upstream of ezvps and non-ezvps files (plain,
  with a path and a trailing comment, `https://`, several targets, one-line
  `location`, none, commented-out, marker fallback, real `proxy_pass` over a stale
  marker), `CREATED BY` is only `ezvps` / `not ezvps`, and nothing is changed.
  **Certificates** (`== Certificates module`) runs against a **fake acme.sh** (it is
  also the "downloaded" script, so the install really runs it; its certificates are
  text files with a `notAfter=` line, its private key is a marker that must never be
  printed, and like the real one it writes with the default umask), a fake `openssl`
  (reads that line), a fake `crontab`, the fake `nginx` with the test switches above,
  stub `curl`/`sha256sum`/`ss`/`systemctl`, and sandbox `PATH`s that each lack one
  command. Covered: submenu labels; install (plan with URL, tag and hash, pinned URL
  downloaded once with `--proto =https --tlsv1.2`, `--install --home ... --no-profile`,
  version verified, crontab backup, already installed or on `PATH` = no download and
  no reinstall, a broken existing one reported, declined, SHA-256 mismatch, download
  failure, installer failure, no `crontab` = `--nocron` and a warning, missing `curl`
  offered and only installed after a yes, unsupported system); issue (every
  precondition refuses without running acme.sh; wildcard, list, junk and traversal
  input; no server block; the DNS and port-80 notice; declined; the exact acme.sh
  command lines, `--nginx --server letsencrypt`, no DNS mode; certificate-only when
  no ezvps site exists and a hand-written site is untouched; store paths and modes
  600/644/700; the key never in the output; expiry and cron shown; **re-issue with a
  byte-for-byte backup of the old certificate and key**; "not due"; acme.sh failure,
  nginx test failure after acme.sh, install-cert failure with and without an existing
  certificate, key block hidden); **HTTPS for an ezvps site** (offer, byte-for-byte site
  backup, `# ezvps:https=on`, `listen 443 ssl`, `http2 on`, the store's `ssl_certificate`
  and key, 443 not 4443, no `stream`, the 301 to `https://$host$request_uri` inside
  `location /`, the proxy block with every header and timeout only in the 443 block,
  config test before the reload, already-on = reload after a test, declined, hand-written
  and differently named files untouched, a **failing config test restores the site byte
  for byte and does not reload**, the map ensured as well); list (empty, expiry dates,
  site status, expired, sorted, no openssl, a directory without or with an unreadable
  certificate; read-only); renew (nothing due = no test and no reload, a renewed
  certificate = test then one reload, a **failing test = no reload**, acme.sh failure, a
  certificate outside the store, no nginx); remove (unknown domain, bad input, declined,
  **backup of the certificate and the key**, store entry gone, HTTPS site backed up and
  **restored to the plain HTTP proxy**, other sites untouched, test before reload,
  `acme.sh --remove`, a **failing config test restores the HTTPS site, keeps the
  certificate and does not reload**, refusal while another file or a non-ezvps site uses
  the certificate, no ezvps site, `--remove` failure, no nginx).
  It touches nothing outside its temp dir and uses no network.
  `tests/lint.sh` additionally checks that the OS allowlist block is identical
  in `ezvps` and `install.sh` and lists exactly the five supported systems, that
  the nginx.org suite is not hardcoded, that the repository URL is the stable
  one (never mainline), the key URL, the fingerprint pins and the priority-900
  pin are present, that `curl` is used only in the 3x-ui download/probe
  functions, `ngx_fetch_key` and `acme_fetch_script`, that the acme.sh pin (tag,
  exact tag-based URL, SHA-256) is present and well formed, and that the script has
  no `get.acme.sh`, DNS-validation, DNS-credential or certbot code.
* **Operating systems** (`== operating systems` in the smoke test, always with
  fake os-release files in a temp dir and the check switched ON): Debian 12
  (bookworm), Debian 13 (trixie), Ubuntu 22.04 (jammy), Ubuntu 24.04 (noble, also
  with a quoted `ID="ubuntu"`) and Ubuntu 26.04 (resolute) are accepted; Ubuntu
  25.10, 25.04, 23.10 and 26.10, Debian 11, Debian testing/sid (no `VERSION_ID`),
  an unknown distro (Fedora), a derivative whose `ID_LIKE` says ubuntu (Linux
  Mint), a missing file, and the codename mismatches (Ubuntu 24.04 with `jammy`,
  Ubuntu 22.04 with `noble` or no codename, Debian 13 with `bookworm`, Debian 12
  with `noble`) are rejected with the exact shared message (the mismatch cases
  also say the codename does not match), by 3x-ui, Nginx, L2TP and `install.sh`,
  and nothing is changed. The skip switch never makes Nginx guess a repository
  for an unlisted release or a mismatch. Nginx repository selection, for **every
  accepted system**: `nginx.list` is exactly the one line
  `packages/<debian|ubuntu> <detected codename> nginx` (never the other path,
  never mainline), the package must end in `~<codename>` (a candidate for another
  suite is refused), a mainline source (also in a deb822 `.sources` file) is
  refused, and the key URL and pin are unchanged; the fake apt only honours the
  pin when the source line names the right path and codename, which is how the
  tests prove it. A full fake install flow runs on every system (key check,
  order key -> update -> install, package version, enable, config test, no-op
  re-run) as does the replacement of the distribution's own nginx (backup of
  `/etc/nginx` before the purge, restore of the ezvps sites), plus Ubuntu 24.04
  refusals (pin not working, wrong repository path, mainline source/candidate,
  old candidate, candidate for another codename, Ubuntu package after install,
  wrong or missing codename). L2TP on Debian 12 and on Ubuntu 22.04, 24.04 and
  26.04 prints the Debian-13-only message, does not launch ezl2tp even when it is
  present and shows no install instructions. A default 3x-ui install runs on all
  five systems.
* `tests/fresh-vps-test.md`: manual checklist on a throwaway VPS of each
  supported release (Debian 12, 13; Ubuntu 22.04, 24.04, 26.04), including the
  Certificates module, which needs a real domain pointing at the VPS.
