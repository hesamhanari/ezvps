# ezvps SPEC

Version: 0.0.1 (in development). This file is the source of truth for scope.
Each later PR implements one module from the list below and updates the
status table here. Done so far: L2TP (PR 1), 3x-ui (PR 2), Nginx (PR 3, conf.d in PR 4, nginx.org stable in PR 5), Ubuntu 24.04 LTS support (PR 6), Debian and Ubuntu LTS family support (PR 7), Certificates and the new Nginx site template (PR 8), the Backpack, ctunnel and Lazyports lifecycle modules (PR 9), SSH and Users (PR 10), Firewall (PR 11), Backup, Check For Updates and Uninstall (PR 12): **the panel is complete, every menu item is implemented**.

## 1. What ezvps is

A bash TUI/CLI VPS manager for the **Debian and Ubuntu LTS families**
(Debian 12 and 13; Ubuntu 22.04, 24.04 and 26.04 LTS), run as **root**. One
script, installed as `/usr/local/bin/ezvps`. It has no dependencies beyond what
a supported install already has (bash, coreutils, systemd); anything else a
module needs is checked with `command -v` first and installed only with the
user's say-so (3x-ui: `curl`; Nginx: `curl`, `gnupg` and the nginx.org `nginx` package itself;
Certificates: `curl` and the pinned acme.sh script; Backpack and Lazyports: `curl`;
ctunnel: `git`, `make`, `gcc` and the OpenSSL and zlib development packages. Lazyports needs
Go, which ezvps never installs; SSH and Users: `sudo`, only when you ask for sudo access on a
system without it. It never installs the OpenSSH server; Firewall: nothing, it uses the firewall
backend that is already present and never installs one; Check For Updates and Update ezvps: `git`, only to fetch
the private repository with the user's own authentication, never installed by ezvps; Backup, Restore and Uninstall:
nothing beyond coreutils, `cmp` and `bash`).

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
| Backpack, ctunnel, Lazyports (`x86_64` and `aarch64` only) | yes | yes | yes | yes | yes |
| SSH and Users | yes | yes | yes | yes | yes |
| Firewall (whichever of ufw, firewalld, nftables, iptables is present) | yes | yes | yes | yes | yes |
| Backup, Check For Updates, Uninstall (ezvps itself) | yes | yes | yes | yes | yes |
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
  | Backpack, ctunnel, Lazyports (PR 9) | upstream installers branch on nothing distro-specific (Backpack's `install.sh` keys on `uname -m` only; ctunnel is `make`; Lazyports is `go install`); apt package names `git make gcc libssl-dev zlib1g-dev curl` are identical | identical | one path (Go is not installed by ezvps, so the distro's Go version only matters to Lazyports, see 6.7) |
  | SSH and Users (PR 10) | `useradd`/`usermod`/`userdel`/`passwd` (shadow-utils), group `sudo` (only when the `sudo` package is installed, which a minimal Debian image may lack), `ssh.service` | same commands; group `sudo`; sudo is preinstalled; **Ubuntu 22.10+ starts sshd through `ssh.socket`**, whose port is not always taken from `sshd_config` | one code path. The group name (`sudo`, not `wheel`) and the documented command (`usermod -aG sudo <user>`) are the same on both. The socket difference is handled by *verifying* that sshd listens on the new port after a port change and rolling back if it does not (6.8); ezvps does not branch on the distro for it |
  | Backup, Check For Updates, Uninstall (PR 12) | coreutils (`cp`, `mv`, `rm`, `mkdir`, `mktemp`, `date`, `chmod`, `stat`, `du`, `cmp`, `sha256sum`) and `git` have the same arguments and the same package names (`git`) | same | one code path. Restoring nginx sites uses the same `nginx -t` and `systemctl` as the Nginx module on all five systems; `/etc/nginx/conf.d` is the nginx.org layout everywhere |
  | Firewall (PR 11) | which backend exists differs by image (Ubuntu usually ships `ufw`; Debian usually has `nftables`/`iptables`), not by release: `ufw`, `firewall-cmd`, `nft` and `iptables` take the same arguments on all five systems | same | one code path. The backend is chosen by which command is present, in the fixed order of 6.9, never by `ID`; ezvps does not branch on the distro |

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
| 3 | Backpack          | **implemented**     | PR 9       |
| 4 | ctunnel           | **implemented**     | PR 9       |
| 5 | Nginx             | **implemented**     | PR 3       |
| 6 | Certificates      | **implemented**     | PR 8       |
| 7 | Lazyports         | **implemented**     | PR 9       |
| 8 | SSH and Users     | **implemented**     | PR 10      |
| 9 | Firewall          | **implemented**     | PR 11      |
| 10| Backup            | **implemented**     | PR 12      |
| 11| Check For Updates | **implemented**     | PR 12      |
| 12| Uninstall         | **implemented**     | PR 12      |

One module per PR. **All twelve items are implemented: the full panel is complete.** Every implemented
module runs on all five supported systems (section 1.1), **except L2TP, which is Debian 13 only** for now
(the ezl2tp gate).

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
5. Print the one-line progress message `Installing nginx (stable, nginx.org)...`
   (the repository line, key URL, pin and version rule above are not repeated
   on screen), list what is replaced, and ask once. If `curl` or `gpg` is missing the plan says so and
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
    print a short result: the installed version, that the config test passed
    and that nginx is enabled and running. A failed check prints what was found
    and what was required (for example the version found and "stable 1.30 or
    newer from nginx.org").

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

### 6.5 Backpack (PR 9, done), with the rules shared by 6.5 to 6.7

Backpack, ctunnel (6.6) and Lazyports (6.7) are **lifecycle modules** that share one
flow. Menu items 3, 4 and 7 open the **same submenu** for each tool. Clean labels only:

```
 1) Install
 2) Status
 3) Update
 4) Uninstall
 0) Back
```

`0` or EOF returns to the main menu; after each action "Press Enter to continue...";
invalid input prints `Invalid choice: <input>`. Module keys `backpack`, `ctunnel`,
`lazyports` map to `module_backpack`, `module_ctunnel`, `module_lazyports`, each a
one-line wrapper around the shared `lc_module <key>`; all helpers are prefixed `lc_`.

**Scope: lifecycle only.** These three tools have their own interface (Backpack: an
interactive CLI, ctunnel: a command-line tunnel program, Lazyports: a terminal UI).
ezvps manages Install, Status, Update and Uninstall and **nothing else**. Tunnel setup,
port management, tokens, setup links, certificates, ciphers and every other setting stay
in the tool's own CLI or TUI: ezvps does not rebuild, wrap or script them, does not
launch a tool after installing it (it prints how to open it), and **never asks for,
stores, prints or logs a tunnel token, setup link, password or private key**. The
lifecycle code contains no input prompt other than the submenu choice and yes/no
confirmations (a test enforces it). The one place ezvps starts a tool is Update and
Uninstall of Backpack, whose documented method *is* Backpack's own menu: ezvps opens it
as a child process on the terminal, the user picks the menu item, and ezvps goes on when
it exits.

One table, `lc_load`, holds what differs per tool (installer, binary, config, version
command, services, update and uninstall method, architectures, the text of the plan);
everything else is the shared flow below. Only what **upstream documents** is used; each
fact has its upstream source named in 6.5 to 6.7. Where upstream documents nothing, ezvps
says so and does not guess (no invented service, version flag or update command).

#### Shared rules (6.5 to 6.7)

**Install**
1. A supported system (`require_supported_os`, section 1.1) and an upstream-supported
   architecture (`uname -m`; `x86_64` or `aarch64` for all three, see each tool), otherwise
   refuse with `<Label> install does not support architecture '<arch>' (supported: ...).
   Nothing was changed.` or the shared OS message, with no download and no file touched.
2. **Already installed** (a documented location, else a command on `PATH`): print
   `<Label> is already installed (<path>[, version <v>]).` and ask before reinstalling;
   `n` changes nothing, makes no download and no backup.
3. Prerequisites: installer tools need `sha256sum` and `curl` (`curl` is offered via
   `apt-get` after a yes, as elsewhere); Lazyports needs `go` (6.7); ctunnel needs `git`,
   `make`, `gcc` (offered via one `apt-get install git make gcc libssl-dev zlib1g-dev`
   after a yes).
4. The plan is printed before anything is fetched: project, installer URL or git URL, the
   pin (tag or commit), the expected SHA-256, what the upstream install does and which
   files it touches, that existing files are backed up first and that the tool is not
   started and nothing is asked for. Then `ezvps` asks once; `n` changes nothing.
5. **Backup before overwriting.** Each existing config path and binary of the tool is
   copied byte for byte with `cp -a` to `/var/backups/ezvps/<key>-<n>-<name>.<timestamp>.<pid>`
   (dir mode 700; configs first, then binaries, `n` counts the copies). ezvps never reads
   or prints a config; since a config can contain a token or key, the backup directory is
   root-only. A failed backup aborts before anything is changed. Nothing existing = no
   backup. ezvps never deletes a backup.
6. Fetch, verify, run (per tool, below). A download or checksum failure, or an installer
   failure, is reported and the module returns to the menu.
7. **Verify afterwards:** the binary must exist at a documented location, otherwise
   `The installer finished, but no <cmd> binary was found ... <Label> is NOT installed.`
   On success print `Installed: <path>`, the version (or that none is reported) and
   `To open <Label>: run: <command>`; nothing is launched.

**Fetching rules.** An installer script is downloaded with `curl --proto '=https'
--tlsv1.2` into a private temp directory by `lc_fetch_installer` (the only `curl` of these
modules), hashed, compared with the pinned SHA-256 and **refused on a mismatch**, then run
with `bash <file> </dev/null` (the script's terminal input is `/dev/null`: Backpack's
installer would otherwise open Backpack's menu on a terminal, and ezvps must not launch the
tool). It is never piped or process-substituted into a shell. Nothing from the network is
run without the URL and pin having been shown and a yes. The pins live in `ezvps` as
`LC_BACKPACK_*`, `LC_CTUNNEL_*`, `LC_LAZYPORTS_*`; to bump one, read the upstream file at
the new tag or commit, change the tag/commit and the hash together, update 6.5 to 6.7 and
run the tests (`tests/lint.sh` checks that the pins exist and are well formed).

**Status.** Read-only. `Installed: yes/no`, each binary path found, `Version:` (the first
line of the tool's documented version command, or `not reported` when it has none),
services (below), and how to open the tool. A tool without a documented service says so
(`Service: none documented upstream ...`): status is then *installed + binary present*,
never *running* or *stopped*.

**Update.** Only through the tool's documented update method, never a guessed command.
* *Documented menu update* (Backpack): explain, ask, back up the config and binary, open
  the tool's own menu, report `Updated: <old>  ->  <new>` (or `Version is unchanged (...)`
  when the version did not move, e.g. already latest or the menu was left without updating).
* *No documented update* (ctunnel, Lazyports): print `<Label> has no documented update
  command upstream, and ezvps does not guess one.` and offer the **documented reinstall**
  from the same source as Install: ask, the full Install flow (plan, confirmation, backup
  first, pinned source), then `Version: <old>  ->  <new>` when the tool reports versions.
Not installed: `... there is nothing to update. Choose Install first.`

**Uninstall.** Not installed: nothing to do. Otherwise ezvps states what will be removed,
**asks (default no)**, backs up the config and binary, removes the tool through the
documented method, and then **verifies the binary is gone** (`Verified: the <cmd> binary is
gone.`, or a warning that it is still present, for example when Backpack's menu was left
without choosing Uninstall). Only paths named in the table are ever removed; a copy found
only elsewhere on `PATH` is reported and left alone. Backups are kept and their location is
printed.

**Test-only variables** (7a): `EZVPS_TOOL_PREFIX` (default `/usr/local`; binaries live in
`<prefix>/bin`, ctunnel's man page in `<prefix>/share/man/man1`) and
`EZVPS_BACKPACK_CONF_DIR` (default `/etc/backpack`); `HOME` (as root, `/root`) locates
`~/.passkey`, `~/go/bin` and the shell startup files. `EZVPS_BACKUP_DIR` and
`EZVPS_SKIP_OS_CHECK` apply as everywhere.

#### Backpack specifics

* Project: <https://github.com/AminMGMT/BackPack> (public). Read for this PR at v1.9.0
  (`README.md`, `docs/install.md`, `docs/updates.md`, `docs/server-layout.md`,
  `docs/cli-menu.md`, `docs/troubleshooting.md`, `install.sh`, `internal/menu/system.go`).
* **Install.** Upstream's one documented install is its own `install.sh` (docs/install.md:
  `bash <(curl -fsSL https://raw.githubusercontent.com/AminMGMT/BackPack/main/install.sh)`).
  ezvps downloads **the same script at the release tag v1.9.0**, never `main`, **exact URL**
  `https://raw.githubusercontent.com/AminMGMT/BackPack/v1.9.0/install.sh`, expected SHA-256
  `270be80ff0599fc63f03e952b66f4721552c1965b448f5269d62645bacb9e20d` (byte-identical to
  `main` when this was written). That script downloads the latest release archive for the
  architecture from GitHub, verifies it against the `SHA256SUMS` published with the release
  and refuses an archive it cannot verify, installs `/usr/local/bin/backpack`, creates
  `/etc/backpack` and `/root/BackPack`, and records `/etc/backpack/install_path`. It would
  open Backpack's menu when it has a terminal on stdin; ezvps runs it with `</dev/null`
  (shared rules) so it only installs. No environment variable is passed (the script also
  reads `BP_HELPERS` and `BP_BUILD_FROM_SOURCE`, which ezvps never sets).
* **Architectures:** `x86_64` (amd64) and `aarch64` (arm64), the release architectures the
  README lists. (The script also maps a few 32-bit ones; ezvps does not claim them.)
* **Config backed up:** `/etc/backpack` (tunnel `.toml` files and state, which can contain a
  tunnel token) and the binary `/usr/local/bin/backpack`. Backpack's own backup archives in
  `/root/BackPack/backups` are not copied by ezvps (they can be large); the Uninstall plan
  warns that upstream's uninstaller deletes them.
* **Version:** `backpack version` (docs/troubleshooting.md; prints the version, then the
  source URL); ezvps shows the first line.
* **Services:** upstream documents `backpack-<name>.service` per tunnel and
  `backpack-monitor.service` (docs/server-layout.md). Status runs `systemctl list-units
  --type=service --all --no-legend --plain 'backpack-*.service'` and prints each unit's
  state; no such unit = "no tunnel is configured yet"; no `systemctl` = a message.
* **Update:** documented as *Main menu -> 8) Update* (docs/cli-menu.md, docs/updates.md:
  verified download, restore point, automatic rollback), and offline by repeating the
  install with a newer archive. Backpack has **no non-interactive update command**, so
  ezvps backs up and opens `backpack`, prints `In Backpack's menu choose 8 (Update), follow
  its prompts, then leave the menu (10, Exit).`, and compares versions afterwards. It does
  not re-run the online installer as an update.
* **Uninstall:** documented as *Main menu -> 9) Uninstall* ("Removes everything Backpack
  installed"; asks its own `Are You Sure`, deletes tunnels, services, `/etc/backpack`, the
  binary and `/root/BackPack` including its backups). ezvps backs up `/etc/backpack` and the
  binary, opens the menu with the hint to choose 9, then verifies the binary is gone.
* Tunnel setup (Setup Iran / Setup Kharej), tokens, setup links, ports, transports, the web
  panel, Telegram and everything else: Backpack's own menu only.

### 6.6 ctunnel (PR 9, done)

* Project: <https://github.com/alienrobotarmy/ctunnel> (public). Read at commit
  `ec5e388e1dd3b684cd1cea1ed5c67f99d42bf4f3` (`README.md`, `INSTALL`, `Makefile`,
  `Makefile.cfg`, `src/Makefile`, `src/opt.c`, `ctunnel.1`). It is a **command-line tunnel
  program** (`ctunnel -c|-s -l ip:port -f ip:port -C cipher`), not a TUI panel, and has no
  systemd unit, no installer script, no releases and no tags. ezvps invents none of them.
* **Install:** upstream's documented method is building from source: `make; make install`
  (README "Building", INSTALL). ezvps fetches **one pinned commit**
  (`ec5e388e1dd3b684cd1cea1ed5c67f99d42bf4f3`, the latest when this was written; there are
  no tags) from `https://github.com/alienrobotarmy/ctunnel.git` into a temp directory with
  `git -c protocol.allow=never -c protocol.https.allow=always init/fetch --depth 1/checkout`
  in `lc_fetch_source` (the only git network access), requires `git rev-parse HEAD` to equal
  the pinned commit, runs `make PREFIX=/usr/local` (the OpenSSL build, upstream's default
  `CRYPTO_TYPE`) and `make install PREFIX=/usr/local`. That installs `/usr/local/bin/ctunnel`
  and `/usr/local/share/man/man1/ctunnel.1` (`Makefile`: `install ctunnel $(PREFIX)/bin`, the
  man page). The build log is shown only on failure (last 20 lines, with a hint about
  `libssl-dev zlib1g-dev`); nothing is installed after a failed build.
* **Build packages:** `git`, `make`, `gcc` are checked; if any is missing, one `apt-get
  install git make gcc libssl-dev zlib1g-dev` is offered (a yes is required).
* **Architectures:** upstream states no list (a C source build). ezvps accepts `x86_64` and
  `aarch64`, the two architectures the supported systems are used on.
* **Config backed up:** `~/.passkey` (README "Keys": ctunnel keeps its pre-shared Key and IV
  there) and the binary. The file is a secret: it is copied byte for byte, never read or
  printed, and never deleted or created by ezvps (ctunnel creates it itself on first run).
* **Version:** `ctunnel -v` ("Print Version information then exit", `src/opt.c`; with no
  other option ctunnel prints its banner, then usage, and exits 0). ezvps shows the first
  line, `ctunnel <major>.<minor> Copyright ...`. It is the only way ezvps ever runs ctunnel.
* **Services:** none documented upstream: Status says so and reports installed + binary
  present, not running/stopped. Tunnels are started by hand by the user.
* **Update:** upstream documents **no update command**. Update says so
  (`ctunnel has no documented update command upstream, and ezvps does not guess one.`) and
  offers the documented reinstall (the Install flow above, backup first), then reports the
  version before and after.
* **Uninstall:** upstream's `make uninstall` is `rm -f $(PREFIX)/bin/ctunnel` and `rm -f
  $(PREFIX)/share/man/man1/ctunnel.1`. ezvps lists those two paths (the ones that exist),
  asks, backs up the binary and `~/.passkey`, removes exactly them (without downloading the
  source again to run `make`) and verifies the binary is gone. `~/.passkey` and the backups
  are left. A ctunnel found only elsewhere on `PATH` (for example a distro package) is
  reported and not touched.
* Tunnels, ciphers, keys, VPN mode: the `ctunnel` command line only.

### 6.7 Lazyports (PR 9, done)

* Project: <https://github.com/v9mirza/lazyports> (public). Read at commit
  `84647db0ea0e0c7b90b247e35a6c47d44d4bba95` (`README.md`, `install.sh`, `go.mod`,
  `main.go`). A Go terminal UI; no releases, tags, services, config files or version flag.
* **Install:** upstream's documented install is its `install.sh`
  (`curl -sL https://raw.githubusercontent.com/v9mirza/lazyports/main/install.sh | bash`).
  ezvps downloads the same script **at that commit, never `main`**, **exact URL**
  `https://raw.githubusercontent.com/v9mirza/lazyports/84647db0ea0e0c7b90b247e35a6c47d44d4bba95/install.sh`,
  expected SHA-256 `6324d8c6e4fe736f994e41de5a985040b0d4d6b734968f0ad554833ca0940a60`,
  and runs it with `</dev/null`. The script requires Go (it exits with "Go is not installed"
  otherwise), runs `GOPROXY=direct go install github.com/v9mirza/lazyports@main`, copies the
  binary from `$(go env GOPATH)/bin` to `/usr/local/bin/lazyports`, and, when that Go bin
  directory is not on `PATH`, **appends an `export PATH=...` line to `~/.bashrc` or
  `~/.zshrc`**. Honest limit, shown in the plan: the script is pinned and hash-checked but
  `go install ...@main` builds upstream's **current main branch**, which cannot be pinned
  without changing upstream's script.
* **Go:** required, never installed by ezvps (upstream: "Please install Go"). Missing =
  refuse with the Go install URL, nothing changed. `go.mod` needs Go 1.24 (toolchain
  go1.24.12): below 1.21 (cannot fetch a newer toolchain) is refused, 1.21 to 1.23 is
  warned about (Go will try to download the toolchain; the installer reports failure
  otherwise), 1.24 and newer pass.
* **Architectures:** upstream states none (a Go source build). ezvps accepts `x86_64` and
  `aarch64`.
* **Config backed up:** Lazyports has no config. The files its installer may change are
  backed up first: the existing `~/.bashrc` and `~/.zshrc`, plus any installed binary.
* **Binary:** `/usr/local/bin/lazyports` or `~/go/bin/lazyports` (README).
* **Version:** none documented; Status prints `not reported`. No `--version` is guessed.
* **Services:** none (an interactive TUI): Status says so.
* **Update:** upstream documents **no update command**; Update says so and offers the
  documented reinstall (the same installer, which rebuilds the current upstream `main`).
* **Uninstall:** documented as removing the binary (README "Uninstallation": `sudo rm
  /usr/local/bin/lazyports` and `rm ~/go/bin/lazyports`). ezvps lists the paths that exist,
  asks, backs up, removes exactly those and verifies. The PATH line the installer added to a
  shell startup file is **not** removed (upstream does not document it); the message says
  shell startup files stay as they are.
* Everything the TUI does (filter, sort, kill): Lazyports itself.

### 6.8 SSH and Users (PR 10, done)

Menu item 8 opens a submenu. Clean labels only:

```
 1) List users
 2) Add user
 3) Delete user
 4) SSH settings
 5) Add SSH key
 0) Back
```

`0` or EOF returns to the main menu; after each action "Press Enter to continue...";
invalid input prints `Invalid choice: <input>`. Module key `ssh` maps to `module_ssh`; its helpers
are prefixed `usr_` (accounts) and `ssh_` (sshd settings and keys). **Scope:** list, add and delete
ordinary accounts, three sshd settings, and authorized keys. Locking or unlocking accounts, changing
a password, sudoers files, other sshd directives, firewall rules and host keys are out of scope.

**Checks before any change** (Add user, Delete user, each SSH setting, Add SSH key): root
(`require_root`), a supported system (`require_supported_os "SSH and Users"`, section 1.1), a valid
username, and for SSH changes a passing `sshd -t`. A refusal says why and changes nothing. List users
and the read-only view of the current sshd settings need no OS check. Nothing is ever changed without
a yes: a username, a key, a port or a choice are *inputs*, and each change is then shown and confirmed
(default no). **Never read, printed, stored or logged:** a password, a password hash (only the passwd
and group files are read, never `/etc/shadow`, and field 2 of passwd is discarded), or a private key.

**Files and commands.** Reads `/etc/passwd`, `/etc/group`, `/etc/shells`, `/proc/<pid>/status` and
`/proc/self/loginuid`, and the sshd config, in pure bash. Commands: `useradd`, `usermod`, `userdel`,
`passwd`, `chown`, `sshd` (`-t`, `-T`), `systemctl`, optionally `ss` (through `port_in_use`) and
`apt-get` (to offer the `sudo` package). All are checked with `command -v`; a missing one gives a
message and no change. Paths can be redirected for tests (section 7a); the defaults are the real ones.

#### 1) List users

Read-only. A table `USER  UID  SUDO`, one account per row, for accounts with a **login shell** (not
empty, not `nologin`/`false`, and listed in `/etc/shells`, which is what shells(5) defines as a valid
login shell, so pseudo accounts such as `sync` are excluded; without a readable shells file only the
`nologin`/`false` rule applies) **and an existing home directory**. `SUDO` is `yes` when the account is
a member of the `sudo` group (listed in it, or with it as the primary group), `no` otherwise, `n/a` for
UID 0. Rules in `/etc/sudoers*` are not inspected, and the output says so. System service accounts
with a `nologin`/`false` shell are hidden; the module then asks `Also show system service accounts
(nologin/false shells)?` and, on yes, prints every account with its shell. A password hash is never
shown (field 2 is not read into any variable that is printed).

#### 2) Add user

1. Asks for a username. **Strict validation:** `^[a-z][a-z0-9_-]{0,30}$` (a lower-case letter first, at
   most 31 characters; no upper case, dots, `$`, spaces, slashes or leading `-`). Empty input
   cancels.
2. **Refuses** an existing user (any entry in passwd, including `root`) and a name that is already a
   group.
3. Asks `Grant '<name>' sudo access (adds the user to the 'sudo' group)?` If yes and the `sudo` group
   does not exist (the package is not installed, as on a minimal Debian image) it says so and offers
   `apt-get install -y -q sudo` (only after a yes); if the group is still missing it asks whether to
   create the user without sudo, and cancels on no.
4. Shows the plan and asks `Create user '<name>' now?`.
5. `useradd --create-home --shell /bin/bash -- <name>`; the account is read back from passwd
   (otherwise the failure is reported and nothing else is done). **No backup is made for a new user.**
6. If sudo was chosen: `usermod -aG sudo -- <name>`, the **only** group added. The documented method is
   the same on Debian and Ubuntu (the group is `sudo`, not `wheel`). It is **verified** by reading the
   group file again; a failed or ineffective `usermod` is reported as `Sudo access was NOT granted`
   and the summary says `sudo : no`.
7. Asks `Set a password for '<name>' now?` Yes: runs `passwd -- <name>` with the terminal attached, so
   the **system's own prompt** asks for it; ezvps never reads, stores, prints or logs it. No (or a failed
   `passwd`): the account has no password, so password login is locked, and the message says how to set
   one or to use Add SSH key.
8. Summary: `Created user: <name> (UID n)`, the home directory, `sudo : yes|no`, `password : set with
   passwd|not set (password login is locked)`.

#### 3) Delete user

Refusals, each before anything is asked or changed:

| Case | Message |
|------|---------|
| `root` | `Refusing to delete root.` |
| any account with UID 0 | `UID 0 is a root account` |
| the current user: `SUDO_USER`/`SUDO_UID`, the effective user, or the audit login uid in `/proc/self/loginuid` (the account that logged in, even after `su`) | `that is the account you are logged in with` |
| a system account (UID below 1000, or 65534) | `it is a system account, not a regular user` |
| unknown or invalid name | message |
| **running processes**: any process whose real or effective UID matches (read from `/proc/*/status`) | `N process(es) are running as this user (PIDs: ...)`. **Final: ezvps neither kills them nor offers an override or a second prompt**; log the user out and try again |
| `/proc` not readable | `Cannot check running processes` |

Then: `Delete the user '<name>'?` (default no); then, as a **separate second confirmation**,
`Also DELETE the home directory <path>?` (default no, so **a home directory is never deleted by
default**). The second question is only asked when the home directory is removable: a plain directory
directly under `/home` (`EZVPS_HOME_BASE`), not a symbolic link, existing, and not shared with or
nested in another account's home. Otherwise the home is kept and the reason is printed. `passwd` and
`group` are copied to `/var/backups/ezvps/users-passwd.<timestamp>.<pid>` and `users-group...` first
(not `/etc/shadow`: it holds hashes, and userdel keeps its own `shadow-`). Then `userdel -- <name>`, or
`userdel -r -- <name>` only after the second yes (shadow-utils' own checks apply on top). The account
is read back from passwd to verify it is gone, and the summary says whether the home was removed or
kept.

#### 4) SSH settings

Shows the effective values from `sshd -T` (Port, PermitRootLogin, PasswordAuthentication) and a
submenu with exactly `1) SSH port`, `2) PermitRootLogin`, `3) PasswordAuthentication`, `0) Back`: **one
setting at a time, and no other**. Needs `sshd` (never installed by ezvps), a readable
`/etc/ssh/sshd_config`, and a configuration for which `sshd -t` **already passes** (a broken file is
not touched). Choosing a value that is already effective is a no-op: no backup, no restart.

Every change follows the same sequence, and **any failure puts the backup back**:

1. Warnings and a confirmation (below).
2. **Backup** of `sshd_config` to `/var/backups/ezvps/sshd_config.<timestamp>.<pid>` (byte for byte,
   dir mode 700). A failed backup aborts.
3. **Rewrite**, pure bash, into a temp file next to the config (mode and owner kept) and `mv`:
   a managed block `# ezvps:managed <Key>` + `<Key> <value>` is written at the **very top** of the
   file, active lines for the same keyword in the global section are commented out as
   `# ezvps disabled: <line>`, a block from an earlier run is replaced (no duplicates), Match blocks
   and every other line are copied unchanged. At the top because sshd uses the **first** value it sees
   and Debian 12+/Ubuntu 22.04+ start `sshd_config` with `Include sshd_config.d/*.conf` (cloud-init
   ships `PasswordAuthentication yes` there). `Port` is cumulative, so older `Port` lines are disabled.
4. **`sshd -t`**. Failure: the output is shown, the backup is restored, **sshd is not restarted**.
5. **`sshd -T` must report exactly the requested value** (for Port: exactly that one port). If a
   drop-in still sets it, the change is rolled back with `The change would not take effect`; a change
   that would silently do nothing is never reported as done. A Match block that also sets the keyword
   is warned about (it overrides the global value for the connections it matches).
6. **Restart** (`systemctl restart ssh`) only after steps 4 and 5 passed. For a port change, when
   `ssh.socket` is active (systemd socket activation) the units are reloaded and `ssh.socket` is
   restarted too. A failing restart restores the backup and restarts again.
7. **Verify:** a port change must find something **listening on the new port** (`port_in_use`, up to
   `EZVPS_SSH_WAIT_SECONDS`, default 10); otherwise the backup is restored, sshd is restarted again
   and the message names `ssh.socket` (Ubuntu's socket unit may own the port). The other two settings
   check that the service is active. Last, the backup path is printed.

*SSH port:* 22 or 1024-65535 only; refused when something already listens on it; warns that new
connections must use the new port, that the firewall is not changed by ezvps (open the new port before
closing the old), and to test from a second terminal first.
*PermitRootLogin:* `no`, `prohibit-password` or `yes`. `no` warns that it can lock you out and, when
no other non-root account with sudo exists, asks a stronger `Continue anyway?`. `yes` warns it is not
recommended.
*PasswordAuthentication:* `no` or `yes`. `no` warns that only keys will work, tells you to test a key
login first and, when no account has a non-empty `authorized_keys`, asks a stronger `Continue
anyway?`; afterwards it warns if `KbdInteractiveAuthentication` is still enabled (PAM may still offer
a password prompt; ezvps does not change that setting). `yes` warns about password guessing.
**The current session:** when `SSH_CONNECTION` is set, every change prints that you appear to be
connected over SSH, that restarting sshd keeps existing sessions open, that the change applies to new
connections, and to keep the session until a new one works.

#### 5) Add SSH key

1. Asks for a username (must exist in passwd; `root` is allowed) and checks its home directory: an
   existing absolute directory without `..`. `~/.ssh` or `~/.ssh/authorized_keys` that is a **symbolic
   link**, or not a regular directory/file, is refused (ezvps runs as root and does not follow links
   planted in a user's home); a missing home is not created.
2. Asks for the public key **without echo** (`read -s`), as one line; a multi-line paste's leftover
   lines are drained on a terminal so they cannot answer later prompts.
3. **Validation** (the key is never echoed back, even on failure): a line that contains `PRIVATE KEY`
   or starts with `PuTTY-User-Key-File` is **refused as a private key** and discarded (any other
   PEM block, such as `BEGIN PUBLIC KEY`, is refused as not an OpenSSH public key);
   control characters or more than 8192 characters are refused; otherwise it must be exactly
   `<type> <base64> [comment]` with a type in `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-nistp256|384|521`,
   `sk-ssh-ed25519@openssh.com`, `sk-ecdsa-sha2-nistp256@openssh.com`, a base64 blob (length a multiple
   of 4, `=` padding only at the end) that **starts with the base64 of the key's own type string** (so a
   blob that does not match its type is refused), and no options in front. Pure bash, no `ssh-keygen`.
4. Shows user, type and comment (not the key data) and asks for confirmation.
5. Creates `~/.ssh` if missing, **backs up** an existing `authorized_keys` to
   `/var/backups/ezvps/authorized_keys-<user>.<timestamp>.<pid>`, writes the old lines plus the new one
   to a temp file in `~/.ssh` (a missing final newline is repaired), sets `~/.ssh` to **700** and the file
   to **600**, `mv`s it in place and `chown <uid>:<gid>` both from passwd. A failing chmod/chown is
   reported (never silently a root-owned file) and the success message is not printed.
6. A key that is already present (same type and data) is a no-op: no write, no backup.
7. Reminds you to test a key login in a second terminal before disabling passwords.

### 6.9 Firewall (PR 11, done)

Menu item 9 opens a submenu. Clean labels only:

```
 1) Show firewall status
 2) List rules
 3) Allow port
 4) Remove rule
 0) Back
```

`0` or EOF returns to the main menu; after each action "Press Enter to continue..."; invalid input
prints `Invalid choice: <input>`. Module key `firewall` maps to `module_firewall`; its helpers are
prefixed `fw_`. **Scope:** show the status, list the rules, allow one port, remove one rule, through the
one backend that is present. ezvps never installs a firewall tool, never enables, disables, resets or
flushes a firewall, and never changes a default policy, a zone, a table or a chain.

#### The backend: detected, in this order

The backend is the **first** one of these whose command exists (`command -v`), in this fixed order
(`FW_BACKENDS` in `ezvps`; lint checks it):

| Order | Backend | Detected by the command | Why it comes here |
|-------|---------|-------------------------|-------------------|
| 1 | `ufw` | `ufw` | a front end that owns the rules it manages, so it goes first |
| 2 | `firewalld` | `firewall-cmd` | likewise a manager over nftables/iptables |
| 3 | `nftables` | `nft` | the kernel framework that the two above and modern iptables sit on |
| 4 | `iptables` | `iptables` | the legacy interface (also the `iptables-nft` compatibility command) |

Only that backend's documented commands are used; the others are never called (the tests assert it).
The chosen backend is named in every action (`Firewall backend: ufw (command: ufw)`) and under the
submenu title. **No backend found** (none of the four commands exists): the module prints `No firewall
backend found (looked for, in this order: ufw, firewalld, nftables, iptables).` and `ezvps does not
install a firewall tool. Nothing was changed.`, does not open the submenu, and returns to the main
menu. The commands are checked each time an action runs, so a backend that disappears is reported
again. Detection is by command, not by service state: a backend that is installed but switched off is
still the backend, and is reported as `disabled`.

| Backend | Commands ezvps runs (all with `LC_ALL=C`) |
|---------|--------------------------------------------|
| ufw | `ufw status verbose`, `ufw status numbered`, `ufw app list`, `ufw app info <profile>`, `ufw allow <port>/<proto>`, `ufw --force delete <number>` |
| firewalld | `firewall-cmd --state`, `--get-default-zone`, `--get-active-zones`, `--zone=<z> --list-all`, `--list-ports`, `--list-services`, `--list-rich-rules`, `--list-sources`, `--info-service=<s>`, `--zone=<z> --add-port=<port>/<proto>`, `--remove-port=`, `--remove-service=`, `--remove-rich-rule=` (each change twice: once for the running firewall and once with `--permanent`; never `--reload`) |
| nftables | `nft -a list ruleset`, `nft insert rule <family> <table> <chain> <proto> dport <port> accept`, `nft delete rule <family> <table> <chain> handle <handle>` |
| iptables | `iptables -w -S INPUT`, `iptables -w -I INPUT 1 -p <proto> --dport <port> -j ACCEPT`, `iptables -w -D INPUT <number>` |

#### Checks

* **Read-only actions** (status, list): a detected backend. Nothing else; they run no write command.
* **Every change** (Allow port, Remove rule), before anything is asked: root (`require_root`), a
  supported system (`require_supported_os "Firewall"`, section 1.1; the shared refusal text), a
  detected backend, and, for `ufw` and `firewalld`, a firewall that is **enabled**. A disabled ufw
  (`Status: inactive`) or a firewalld that is not running does not report its rules back, and ezvps
  never enables or disables a firewall, so it refuses with `<backend> is disabled. ...` and `Nothing was
  changed.` nftables and iptables have no switch, so they are never refused for that reason.
* Then a valid port and protocol (below). A refusal says why and changes nothing.

#### 1) Show firewall status

Read-only. `Status` is `enabled` or `disabled` as the backend reports it, and `Default policy` is what
the backend reports, or says it does not:

| Backend | enabled / disabled | Default policy shown |
|---------|--------------------|----------------------|
| ufw | `Status: active` / `inactive` | the `Default:` line of `ufw status verbose` (`not reported while ufw is inactive`) |
| firewalld | `--state` is `running` / not running | the default zone and its `target` (`not reported while firewalld is not running`) |
| nftables | at least one input chain (`type filter hook input`) has a policy other than `accept` or has rules / otherwise | each input chain's `policy` (`not reported: no input filter chain is loaded`) |
| iptables | the `INPUT` policy is not `ACCEPT` or the chain has rules / otherwise | `INPUT policy <policy>` |

nftables and iptables have no on/off switch, so for them `enabled` means filtering is loaded; the output
says so.

#### 2) List rules

Read-only: it never changes a rule and runs no write command. One rule per row, in the backend's own
order, with the columns `ID  ACTION  PROTO  PORT/SERVICE  SOURCE` and, last, the rule exactly as the
backend reports it:

| Backend | What is listed | ID | ACTION | PORT/SERVICE, SOURCE |
|---------|----------------|----|--------|-----------------------|
| ufw | every row of `ufw status numbered` (IPv4 and IPv6 rows have their own numbers) | ufw's rule number | ufw's word (`allow in`, `deny in`, `limit in`, ...) | the `To` column (port, range, or application profile followed by its ports from `ufw app info`) and the `From` column |
| firewalld | ports, services and rich rules of the **default zone and every other active zone**; the zone is part of the rule text; zones bound to sources get a note | the row number in this list (firewalld has no numbers); the rule is removed by what it is, not by the number | `allow` for ports and services, `accept`/`reject`/`drop` for rich rules | the port, or the service name followed by the ports `--info-service` reports; a rich rule's source |
| nftables | the rules of every **input chain** (`type filter hook input`); a set definition, a forward/output chain, other tables' chains are not shown; a note says so | the nftables rule **handle** | the verdict (`accept`, `drop`, `reject`, ...) | `dport` (a `{ 80, 443 }` set is shown as `80,443`) and `saddr` |
| iptables | the `INPUT` chain of the filter table, IPv4 (no `ip6tables`); a note says so | the rule number in that chain | `-j` target (`accept`, `drop`, `reject`, or a chain name) | `--dport`/`--dports` and `-s` |

A cell the backend does not report for a rule is `-`. A disabled ufw or a firewalld that is not running
says it reports no rules. Nothing is guessed from files on disk.

#### 3) Allow port

1. The checks above, then the port and the protocol, **strictly validated**: the port is one number of
   digits only, `1`-`65535`, no leading zero, no sign, range, list, or `/proto` (surrounding spaces are
   ignored); the protocol is exactly `tcp` or `udp` (any case). Anything else is refused with the reason
   and nothing is changed. An empty port cancels. (To open both protocols, run it twice.)
2. The rules are read. **A port that is already allowed is refused** (`Port <port>/<proto> is already
   allowed by:` and the rules): an allow rule with no source restriction whose port, range, list, service
   or application profile covers that port and protocol (for ufw, the rules of an application profile
   such as `Nginx Full` count; for firewalld, the ports of an enabled service such as `http` count, in the
   default zone). A rule limited to one source address does not count, and neither does the other
   protocol. Re-running it is therefore a no-op.
3. **A blocking rule** (`deny`, `reject`, `drop`) that covers the same port is warned about, since the
   backend may evaluate it first; it does not stop the user.
4. **A port in use** (`ss -ltnp` or `-lunp`, filtered on the port; without `ss`, tcp falls back to a
   connection test and udp says it cannot be checked): the process and listening address are shown with
   a warning, and the confirmation question changes to `Port <port>/<proto> is already in use. Allow it
   anyway?`. It is a warning, not a block: after one yes the rule is added.
5. The exact command(s) are shown and one confirmation is asked (default no). Declined, or EOF: nothing
   changes.
6. A text copy of the listing the backend just reported is saved to
   `/var/backups/ezvps/firewall-<backend>.<timestamp>.<pid>` (dir 700, file 600; a reference copy, not a
   restore file). A failed copy aborts before the change.
7. The rule is added **only through the detected backend**: ufw `allow <port>/<proto>` (ufw places it);
   firewalld in the **default zone**, running and permanent; nftables `insert` at the **top** of the input
   chain; iptables `-I INPUT 1`. At the top, because a rule appended after a final `drop`/`reject` would
   never match. nftables chooses the chain from those loaded: with one input chain it is used, with
   several the user is asked, with none ezvps stops (`ezvps does not create tables or chains`). The
   backend's refusal is shown and nothing else is changed.
8. **The rules are read again from the backend and shown**, followed by `The rule as <backend> reports
   it:` with the matching rule(s). If the backend does not list an allow rule for the port after the
   change, that is reported as a problem and not as success.
9. For nftables and iptables a note says the change applies to the running firewall only (see the limits).
   A firewalld change that reached the running firewall but not the permanent configuration says so.

#### 4) Remove rule

1. The checks above, then the rules are listed with their IDs. No rules: nothing to do.
2. The ID is asked (an empty ID cancels). Only an ID in the list is accepted; `all`, ranges, lists and
   anything else are refused, so **exactly one rule can be removed per run**, and there is no
   remove-all. The rule and the exact command(s) are shown.
3. `Remove rule <id>? The firewall stays enabled and every other rule stays as it is.` (default no).
4. **SSH protection, a separate warning and a separate confirmation.** The SSH ports are the ports
   `sshd -T` reports (else the `Port` lines of `sshd_config`, else 22) plus the server port of the SSH
   session ezvps is running in (`SSH_CONNECTION`). A removal is treated as an SSH removal when the rule
   **allows** traffic and it (a) covers an SSH port (a port, a range, a list, an application profile or
   a service such as `OpenSSH`/`ssh`), (b) is the SSH service or profile by name when its ports cannot
   be read, or (c) has **no port and no protocol restriction at all** (for example a source-only allow,
   an established-connections rule, or a loopback rule), which may be what keeps SSH or the current
   session working. Then ezvps prints `WARNING: rule <id> <why>.`, that removing it can lock the user out
   of the server including the current session and cannot be undone remotely, and (when connected over
   SSH) that the session appears to be an SSH one, and asks `Remove this SSH-related rule anyway?`
   (default no). One yes to the first question is not enough. Removing a block rule is not an SSH
   removal.
5. The numbers can move between listing and removing (ufw, iptables, firewalld), so the rules are read
   again and the chosen rule must still be the same rule; otherwise `The rules changed while you were
   choosing` and nothing is changed.
6. The listing is saved as in Allow port (step 6), then the rule is removed through the backend: ufw
   `--force delete <number>` (the `--force` only skips ufw's own prompt, ezvps has asked already),
   firewalld `--remove-port/-service/-rich-rule` for the running and the permanent configuration,
   nftables `delete rule ... handle <handle>`, iptables `-D INPUT <number>`.
7. **The rules are read again and shown;** the rule must be gone (one fewer rule with that text), else
   it is reported. The summary says `Only that rule was removed; the firewall was not disabled.`

ezvps never blocks a port, so it cannot block SSH; the only way it can cut SSH is by removing an allow
rule, which is why that is the case guarded above.

#### Known limits

* **nftables and iptables changes are runtime only.** ezvps does not rewrite `/etc/nftables.conf`, the
  iptables save files or `netfilter-persistent`, whose format and ownership differ per setup; it says so
  after every such change. ufw and firewalld (permanent) persist by themselves.
* iptables is the IPv4 `INPUT` chain only (`ip6tables` is not managed); nftables only the input chains
  that exist (an `ip` chain is IPv4 only, `inet` covers both).
* A rule that also matches an interface or a connection state counts as the port being allowed (the
  duplicate check looks at port, protocol, action and source only).
* firewalld rich rules are listed and removable, not created. Rules in zones that are neither the default
  nor active are not shown. `docker`'s chains and forward/NAT rules are not shown.
* `ufw` adds IPv4 and IPv6 rules; removing a rule removes only that one row (its IPv6 twin has its own ID).
* Disabled ufw / not-running firewalld: read-only. Enabling is left to the administrator.

### 6.10 Backup (PR 12, done)

Menu item 10 opens a submenu. Clean labels only:

```
 1) Create backup
 2) List backups
 3) Restore backup
 0) Back
```

`0` or EOF returns to the main menu; after each action "Press Enter to continue..."; invalid input
prints `Invalid choice: <input>`. Module key `backup` maps to `module_backup`; its helpers are prefixed
`ezb_`. Backup, Check For Updates and Uninstall (6.10-6.12) manage **ezvps itself and nothing else**: they
never install, update, restart or remove nginx, 3x-ui, Backpack, ctunnel, Lazyports or ezl2tp, and never
touch those tools' own configs, users, SSH settings or firewall rules.

#### Checks before every item (`ezb_preflight`)

1. Root, and a supported system (section 1.1, `require_supported_os`): otherwise the shared refusal
   message and nothing is changed.
2. The commands it uses exist (`cp mkdir mv rm rmdir mktemp date chmod cmp stat du`): otherwise the missing
   ones are named and nothing is changed.
3. Anything that writes (Create backup, Restore backup, Update ezvps, Uninstall) also needs a **writable
   backup directory**: `/var/backups/ezvps` is created if missing, set to mode 700, and a probe file is
   written and removed. If that fails, nothing is changed. List backups and Check for updates write
   nothing and therefore do not create the directory.

#### What a backup contains

A backup is a directory `/var/backups/ezvps/ezvps-backup.<UTC time>-<NN>/` (`YYYYMMDD-HHMMSS`, `NN` =
01, 02, ... for backups made in the same second), **mode 700**, with a `MANIFEST` (mode 600) and:

| Part | Source | Included in |
|------|--------|-------------|
| `bin/ezvps` | the ezvps script, `/usr/local/bin/ezvps` | every backup |
| `state/` | the ezvps state files, `/var/lib/ezvps` (`3x-ui.state`, `install.state`, ...) | every backup |
| `nginx-sites/<domain>.conf` | the **ezvps-made** sites in `/etc/nginx/conf.d`: regular files named `<domain>.conf` that carry the `# Managed by ezvps` marker and a matching `# ezvps:domain=` (hand-written files and symlinks are not included) | full backups |
| `certs/<domain>/...` | the certificate store `/etc/ssl/ezvps`, **including the private keys** (copied with their modes: directories 700, keys 600), if it exists | full backups |

`MANIFEST` records `format=1`, the creation time, the reason (`manual`, `pre-restore`, `pre-update`,
`pre-uninstall`), the scope (`full` or `core` = script and state only), and the installed ezvps version
and commit (`unknown` when not recorded). It holds no secret.

Not included, on purpose: the other tools' configs and data (3x-ui database, Backpack config, the tool
binaries), acme.sh's own home (`~/.acme.sh`), `nginx.conf`, hand-written nginx sites, users, SSH settings
and firewall rules. Those are each owned by their own tool; the module names this in its output.

**No secret is ever printed.** The private keys are copied byte for byte and never read, printed or
logged; the output names domains and file names only. Test fixtures never contain a private key.

#### 1) Create backup

Prints the plan, makes a **full** backup, and **verifies it on the file system**: every copied file is
compared byte for byte with its source, the directory mode is read back and must be 700. A failed or
unverified backup is discarded (only this run's own incomplete directory) with a message, and nothing
else is changed. On success it prints `Backup created and verified: <path>` and exactly what was included
(script, number of state files, the site file names, the certificate domains). Nothing is deleted or
overwritten: every backup is a new directory, and ezvps never deletes a backup.

#### 2) List backups

Read-only. Every `ezvps-backup.*` directory that has a valid name and a `MANIFEST` is listed, **newest
first** (the time in the name, then `NN`), numbered, with the **timestamp (UTC)**, the **size**
(`du -sb`), the **reason** and a **contents summary counted from the directory itself** (script, state
files, nginx sites, certificate domains), then its path. Incomplete or unrecognised `ezvps-backup.*`
entries are counted, not listed. Backups that other modules make in the same directory (`x-ui.*`,
`nginx-*`, `apt-*`, `cert-*`, ...) are not listed, and the output says so.

#### 3) Restore backup

1. The backups are listed first and one is chosen by number (empty = cancel; anything else is refused).
2. **The backup is validated before anything is changed.** Refused as a whole, with nothing changed, when
   it holds anything unexpected: an unknown format, a symlink anywhere, a site that is not an ezvps-made
   `<domain>.conf` for its own domain, a certificate entry that is not a domain directory of plain files,
   a state entry that is not a plain file, or an ezvps script that fails `bash -n` or does not print
   `ezvps <version>` for `--version`.
3. The plan lists what will be put back; **the exact word `YES` must be typed** (`yes`, `y`, `YES ` and
   ` YES` do not count; EOF is a no). Nothing is deleted by a restore: files that are not in the backup stay.
4. **The current state is backed up first** (a full backup, reason `pre-restore`); if that fails, nothing
   is restored.
5. Step 1, certificates then nginx sites: written atomically (temp file in the same directory + `mv`),
   modes kept (directories 700, `privkey.pem` 600). A hand-written file or a symlink with the same site name
   is **never overwritten** (named in the report). Sites are restored only when nginx and its `conf.d`
   exist. They are verified byte for byte, and **`nginx -t` must pass**; only then is nginx reloaded (and
   only if it is running). **A failing config test, or a copy that does not verify, rolls back everything
   step 1 wrote**: files it created are removed, files it replaced are put back from the pre-restore
   backup, the rollback is verified, `nginx -t` is run again, nginx is not reloaded, and the script and state
   files have not been touched yet.
6. Step 2, state files, then the ezvps script (atomic, mode 755): each is verified byte for byte, the
   script also by `bash -n` and `--version`. A script that does not verify is replaced by the pre-restore
   copy again.
7. The report says what was restored (each line backed by the verification above), what was skipped and why,
   and where the pre-restore backup is.

#### Known limits

* A restore does not remove what the backup does not contain (a site or certificate created after the
  backup stays); the pre-restore backup and the normal tools (Nginx > Remove site, Certificates > Remove
  certificate) cover that.
* Restoring certificates does not reload nginx unless sites were restored too; the report says so.
* The backup holds private keys: it is root-only (700/600) and ezvps never deletes it. Move or shred old
  backups yourself.

### 6.11 Check For Updates (PR 12, done)

Menu item 11 opens a submenu. Clean labels only:

```
 1) Check for updates
 2) Update ezvps
 0) Back
```

Module key `update` maps to `module_update`; helpers are prefixed `upd_`.

#### Where the latest version comes from, and the authentication

`install.sh` downloads nothing and has no credentials: it runs from a checkout the user cloned **with their
own authentication** (GitHub CLI login, SSH key, or a token typed at git's prompt). Check For Updates uses
exactly that method and no other: **`git` against the private repository the checkout came from**, so
nothing private is hardcoded and nothing is ever fetched from an anonymous or public URL (no `curl`, no
`wget`, no raw URL).

* `install.sh` records the checkout's `origin` as `source` in `install.state` (below), with any user name
  or token in an `https://` address **removed**. Only these forms are accepted, here and again by ezvps
  before every use: `https://host/path` (no credentials in it), `ssh://[user@]host[:port]/path` and
  `user@host:path`. `http://`, `git://`, `file://`, local paths, options (a leading `-`) and anything with
  spaces or control characters are refused, and a refused address is **never echoed back** (it may contain a
  token).
* If no valid source is recorded (an install made before this existed, or a copy that was not a git
  checkout), ezvps asks once for the repository address (placeholders `git@github.com:<owner>/ezvps.git`
  or `https://github.com/<owner>/ezvps.git`) and explains that git asks for credentials itself.
* The fetch is `git clone -q --depth 1 --branch main --single-branch -- <source> <temp dir>` (the only
  git network access besides the pinned ctunnel fetch, in `upd_fetch_latest`, with
  `-c protocol.allow=never -c protocol.https.allow=always -c protocol.ssh.allow=always`), into a private
  temp directory that is always removed. git's own prompts and messages reach the terminal.
* **`main` is deliberate here.** The pinning rule of principle 7 is for third-party downloads. This is the
  owner's own repository and "latest main" is the request, so instead of a pin the update is guarded by the
  checks below (candidate verified before anything changes, confirmation, backup, verification after,
  rollback).

#### The install record

`/var/lib/ezvps/install.state` (dir 700, file 600; plain `key=value`, read without `source`, no secret):
`version`, `commit`, `source`, `sha256` (of the installed script) and `installed` (UTC time).
`install.sh` writes it on every run (also when the script is already up to date, so re-running it gives an
old install a record), and Update ezvps rewrites it. `commit` is recorded **only** when `install.sh` ran from
a git checkout whose `ezvps` is tracked and identical to `HEAD`; otherwise it is empty (unknown). A failure
to write the record only warns.

#### 1) Check for updates

Read-only (nothing is written; no backup directory is created). It fetches `main` as above and prints:

```
Installed:  version 0.0.1-old, commit aaaaaaaaaaaa
Latest:     version 0.0.2-new, commit bbbbbbbbbbbb (main of <source>)
```

The installed **version** is read from the installed file (as text, never executed). The installed
**commit** counts as known only when `install.state` has a valid 40-hex commit **and** the installed
script still has the recorded `sha256`. Then:

* same commit: `Up to date: the installed commit is the latest main.`
* different commit: `Update available` (pointing to Update ezvps);
* **otherwise the commit is unknown, and ezvps says so and why** (no record, no commit in the record, the
  installed script differs from the one the record describes, record unreadable) and prints `Unknown:
  ezvps cannot tell whether this install is up to date, so it is NOT reported as current.` An old install
  without a record is therefore never shown as up to date; differing versions are noted.

Refusals, all with nothing changed: not root / unsupported system, `git` missing (the message says why git
is required and to install it with apt; ezvps does not install it), an unaccepted address, a failed fetch
(address or access wrong), a `main` without an `ezvps` script.

#### 2) Update ezvps

1. Same preflight (including a writable backup directory), `sha256sum` and `bash` present, and ezvps must
   be installed at `/usr/local/bin/ezvps` (else it says so and points to `install.sh`).
2. Fetch and show installed versus latest, as in Check.
3. **The candidate is verified before anything is touched**: `bash -n` must pass and `--version` must exit 0
   and print `ezvps <version>`. Otherwise it is refused, nothing is changed and nothing is offered.
4. If the installed script is already byte for byte the fetched one, nothing is replaced and nothing is
   asked; an unknown or stale install record is rewritten (and read back) so the next check is exact.
5. The plan (`version old -> new`, commit) is shown and **a yes is required** (default no, EOF is no).
6. **The current script and the ezvps state files are backed up first** (`core` backup, reason
   `pre-update`, under `/var/backups/ezvps`, path printed); if that fails nothing is changed.
7. The script is replaced atomically (temp file next to it, mode 755, `mv`). Tool configs, nginx sites,
   certificates, users and all other state are not touched; the install record is the only state file
   rewritten.
8. **Verified on the file system**: the installed file is byte for byte the fetched one, passes `bash -n`
   and prints `ezvps <new version>` for `--version`. **On any failure the previous script is put back from
   the backup, checked byte for byte, and the install record is left as it was;** the update is never
   reported as done.
9. The install record is rewritten (and read back), the other state files are compared with the backup, and
   the report says `Updated <path>: version old -> new, commit ...` plus what was verified. The running
   session keeps the old code; restart ezvps to use the new one.

### 6.12 Uninstall (PR 12, done)

Menu item 12 (module key `uninstall`, `module_uninstall`). It has no submenu: it shows the plan and asks.

1. The same preflight (root, supported system, writable backup directory). If neither the script nor a
   state file exists: `there is nothing to uninstall`.
2. The plan lists exactly what will be removed: **`/usr/local/bin/ezvps` and the ezvps state files**
   (`/var/lib/ezvps/*.state` and leftover `*.state.tmp.*`), and says what stays.
3. **The exact word `YES` must be typed** (anything else, including `yes`, `YES ` and EOF, changes nothing).
4. **A backup is made first** (`core`: script and state, reason `pre-uninstall`, mode 700, verified byte
   for byte) and its path is printed. If it fails, nothing is removed.
5. Only the script and the state files are removed (`rm -f -- <file>`); the state directory is removed only
   if it is then empty (`rmdir`), otherwise it stays and the output says so. Nothing else is ever removed:
   not nginx, 3x-ui, Backpack, ctunnel, Lazyports or ezl2tp, not their configs, nginx sites, certificates,
   acme.sh, users, SSH settings or firewall rules, and **never a backup**.
6. **Verified on the file system**: each target is checked to be gone, and anything that could not be
   removed is reported as an error. The report lists exactly what was removed and, for each of nginx,
   3x-ui, the certificate store, acme.sh, Backpack, the tool binaries and the backup directory, whether it
   is present and untouched (looked up at that moment, not assumed), and how to bring ezvps back (run
   `install.sh`, or copy `bin/ezvps` from the backup).
7. In the interactive menu a successful uninstall leaves the menu (`ezvps has been uninstalled; leaving the
   menu.`), since the script no longer exists on disk.

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
* **Records what it installed** in `/var/lib/ezvps/install.state` (dir 700, file 600): `version`,
  `commit` (only from a git checkout whose `ezvps` is tracked and identical to `HEAD`, else empty),
  `source` (the checkout's `origin`, user name and token removed from an `https://` address, and only
  an `https://`, `ssh://` or `user@host:path` address; else empty), `sha256` of the installed script and the
  time. Written on every run, also when the script is already up to date. A failure only warns. Check For
  Updates (6.11) reads it; `git` is used here only to read the local checkout, nothing is downloaded.
* Test overrides: `EZVPS_BIN_DIR`, `EZVPS_BACKUP_DIR`, `EZVPS_STATE_DIR`, `EZVPS_SOURCE`,
  `EZVPS_ALLOW_NONROOT=1`, `EZVPS_SKIP_OS_CHECK=1`.

## 7a. Test-only environment variables

Defaults are the real paths; none of these relax a check on a real server.

| Variable | Used by | Meaning |
|----------|---------|---------|
| `EZVPS_ALLOW_NONROOT=1` | ezvps, install.sh | skip the root check |
| `EZVPS_SKIP_OS_CHECK=1` | ezvps (3x-ui, Nginx, Certificates, Backpack, ctunnel, Lazyports, SSH and Users, Firewall, Backup, Check For Updates, Uninstall, L2TP), install.sh | skip the "supported system" check only. Detection still runs: L2TP is still gated by the ezl2tp list, and Nginx still picks the repository from the detected distro and codename and still refuses an unknown distro, an unlisted release or a codename mismatch (none gets a repository) |
| `EZVPS_OS_RELEASE` | ezvps (3x-ui, Nginx, Certificates, Backpack, ctunnel, Lazyports, SSH and Users, Firewall, Backup, Check For Updates, Uninstall, L2TP), install.sh | os-release file to read (default `/etc/os-release`) |
| `EZVPS_XUI_DIR` | ezvps (3x-ui) | panel install dir (default `/usr/local/x-ui`) |
| `EZVPS_XUI_DB_DIR` | ezvps (3x-ui) | panel database dir (default `/etc/x-ui`) |
| `EZVPS_STATE_DIR` | ezvps (3x-ui, Backup, Check For Updates, Uninstall), install.sh | state dir (default `/var/lib/ezvps`): `3x-ui.state`, `install.state` |
| `EZVPS_BIN_DIR` | ezvps (Backup, Check For Updates, Uninstall), install.sh | directory of the installed script (default `/usr/local/bin`); the script is `<dir>/ezvps` |
| `EZVPS_BACKUP_DIR` | ezvps (3x-ui, Nginx, Certificates, Backpack, ctunnel, Lazyports, SSH and Users, Firewall, Backup, Check For Updates, Uninstall), install.sh | backup dir (default `/var/backups/ezvps`) |
| `EZVPS_NGINX_DIR` | ezvps (Nginx, Backup, Uninstall) | nginx config dir (default `/etc/nginx`); Backup reads and Restore writes its `conf.d` |
| `EZVPS_APT_DIR` | ezvps (Nginx) | apt config dir for the nginx.org source and pin (default `/etc/apt`) |
| `EZVPS_KEYRING_DIR` | ezvps (Nginx) | where `nginx-archive-keyring.gpg` is stored (default `/usr/share/keyrings`) |
| `EZVPS_NGINX_HTTP_PORT` | ezvps (Nginx) | port used for the port-in-use check and the responds probe (default `80`; generated sites always listen on 80) |
| `EZVPS_IF_INET6_FILE` | ezvps (Nginx) | file whose existence means "kernel has IPv6" (default `/proc/net/if_inet6`) |
| `EZVPS_NGINX_WAIT_SECONDS` | ezvps (Nginx) | how long to wait for nginx to answer (default 15) |
| `EZVPS_XUI_WAIT_SECONDS` | ezvps (3x-ui) | how long to wait for the panel to answer (default 30) |
| `EZVPS_ACME_HOME` | ezvps (Certificates, Uninstall report) | acme.sh home (default `$HOME/.acme.sh`); Uninstall only reports whether it is present |
| `EZVPS_CERT_DIR` | ezvps (Nginx, Certificates, Backup) | certificate store, also the path written into HTTPS sites (default `/etc/ssl/ezvps`) |
| `EZVPS_PASSWD_FILE` / `EZVPS_GROUP_FILE` / `EZVPS_SHELLS_FILE` | ezvps (SSH and Users) | passwd, group and shells files that are read (defaults `/etc/passwd`, `/etc/group`, `/etc/shells`); the `useradd`/`usermod`/`userdel` stubs of the tests edit fake copies |
| `EZVPS_PROC_DIR` | ezvps (SSH and Users) | where `<pid>/status` and `self/loginuid` are read (default `/proc`) |
| `EZVPS_HOME_BASE` | ezvps (SSH and Users) | the only directory under which a home directory may be offered for removal (default `/home`) |
| `EZVPS_SSHD_CONFIG` | ezvps (SSH and Users, Firewall) | sshd configuration file that is read, backed up and rewritten (default `/etc/ssh/sshd_config`); the Firewall module only reads its `Port` lines, as a fallback, to find the SSH port |
| `EZVPS_SSH_WAIT_SECONDS` | ezvps (SSH and Users) | how long to wait for sshd to listen on a new port (default 10) |
| `EZVPS_TOOL_PREFIX` | ezvps (Backpack, ctunnel, Lazyports, Uninstall report) | install prefix of the tools (default `/usr/local`: binaries in `<prefix>/bin`, ctunnel's man page in `<prefix>/share/man/man1`; also passed to `make` as `PREFIX`) |
| `EZVPS_BACKPACK_CONF_DIR` | ezvps (Backpack) | Backpack's config directory, backed up before changes (default `/etc/backpack`) |
| `EZVPS_NO_PAUSE=1` | ezvps | do not wait for Enter |

## 8. Tests

* `tests/lint.sh`: `bash -n` + `shellcheck` on every script, plus a hygiene
  scan (no non-documentation IPs, key material or token patterns) and the
  download rules: `curl` only inside `xui_fetch_installer` / `xui_probe` /
  `ngx_fetch_key` / `acme_fetch_script` / `lc_fetch_installer`, git network access only in `lc_fetch_source` and `upd_fetch_latest`, no
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
  **Backpack, ctunnel and Lazyports** (`== Backpack, ctunnel and Lazyports lifecycle
  modules`) share one section, run against **fake binaries and fake installers**: a fake
  `backpack` (its `version` command, and a tiny menu that reads `8` Update / `9` Uninstall /
  `10` Exit from stdin and records that it was opened), fake official installers for Backpack
  and Lazyports (they record their arguments, whether they received terminal input and the
  environment, and write the fake binary; Lazyports' also appends a PATH line to `~/.bashrc`),
  a fake `git` (records the calls and answers `rev-parse` from a switch) and a fake `make` for
  ctunnel, stub `curl`, `sha256sum`, `uname`, `go`, `gcc`, `systemctl` and `apt-get`, and
  sandbox `PATH`s that each lack one command. Everything lives in per-scenario temp dirs
  (`EZVPS_TOOL_PREFIX`, `EZVPS_BACKPACK_CONF_DIR`, `EZVPS_BACKUP_DIR`, `HOME`). Covered, for the
  three tools unless noted: the exact submenu and its reachability from the main menu;
  install detection and confirmation (plan with URL/commit, pin and hash shown, `n` downloads
  and changes nothing, pinned URL fetched once with `--proto =https --tlsv1.2`, the installer
  gets no arguments, no environment switches and **no terminal input** so the menu input that
  follows survives and the tool is never opened, the binary is verified, only the way to open
  the tool is printed); already installed (said so, reinstall only on a yes, a yes at the plan
  can still stop it, config and binary backed up byte for byte into a 700 directory first, a
  second reinstall converges); failure paths (SHA-256 mismatch, download failure, installer
  failure, installer that installs nothing, missing `curl` offered and only installed after a
  yes, ctunnel: commit that does not verify, git failure, build failure with the log tail,
  missing build tools offered once and only after a yes, Lazyports: no Go, Go 1.19 refused,
  Go 1.22 warned); status (not installed; installed with version; Backpack's
  `backpack-*.service` units running and stopped, none, and no `systemctl`; ctunnel and
  Lazyports say no service is documented and never claim running/stopped; Lazyports says no
  version is reported; a ctunnel on `PATH` outside the prefix counts as installed); update
  (Backpack: declined, backup byte for byte, the tool's own menu opened, `Updated: old -> new`,
  `Version is unchanged`; ctunnel and Lazyports: the no-documented-update message, reinstall
  offered, declined changes nothing, accepted backs up and reinstalls, old and new version
  reported); uninstall (not installed, declined changes nothing, Backpack through its own menu
  with the verify step, leaving the menu without uninstalling is reported, ctunnel removes
  exactly the binary and man page and keeps `~/.passkey`, Lazyports removes both documented
  locations and keeps the shell startup file, a copy outside the documented paths is left
  alone, backups kept, secrets never printed); unsupported systems (all twelve rejected
  `os-release` fixtures, a missing file, and the five accepted ones, for Backpack; Ubuntu
  25.10 and Debian 11 for the others) and unsupported architectures (`armv7l`, `armv6l`,
  `i686`, `i386`, `s390x`, `ppc64le`, `riscv64`, `mips` rejected, `aarch64` accepted) change
  nothing and download nothing. Source rules: `curl` only in `lc_fetch_installer`, git network
  access only in `lc_fetch_source` with https only, the installer runs with `</dev/null`, no
  `read` in the lifecycle code outside the submenu, the yes/no helper and the parsers of the
  tools' own output, one shared submenu and three one-line wrappers, no unpinned installer URL.
  Each assertion was checked to fail when the behaviour it covers is broken (for example
  removing the `</dev/null`, the hash comparison, the backup, the architecture or OS check, the
  confirmations or the post-uninstall verification).
  **SSH and Users** (`== SSH and Users module`) runs against a **fake system** per scenario in a temp
  dir: fake `passwd` (system accounts, `nologin`/`false`/pseudo shells, an account with no home, a
  password hash in field 2, a primary group of `sudo`), `group`, `shells`, a fake `/proc`
  (`<pid>/status`, `self/loginuid`), a Debian-style `sshd_config` with an `Include` and a cloud-init
  style drop-in, and stubs that edit those files: `useradd`, `usermod`, `userdel`, `passwd` (prints a
  marker, reads nothing), `chown` (logs), `apt-get`, `systemctl`, `ss`, and an `sshd` whose `-t` fails on
  a bad directive (or only after ezvps has written its line) and whose `-T` prints a small effective
  configuration (Include, first value wins, `Port` cumulative). Sandbox `PATH`s each lack one command.
  Covered: the exact submenu and its reachability; **list** (login shell and home filter, pseudo shells,
  missing home, UID and sudo columns, sudo by group or primary group, root `n/a`, full list on request,
  a password hash never shown, no shells file, no OS check); **add** (with and without sudo, the exact
  `useradd`/`usermod -aG sudo` calls, sudo verified against the group file, `usermod` that does nothing or
  fails, password only after a yes and only through `passwd`, declined plan, nine invalid names, existing
  user, existing group, `useradd` failure, a missing sudo group with `apt-get` only after a yes, missing
  `useradd`, unsupported systems, all five supported systems, no backup for a new user); **delete**
  (root, another UID 0, the current user by `SUDO_USER` and by login uid, system accounts, unknown and
  invalid names, running processes by real or effective UID, no `/proc`, declined confirmation, no `-r` by
  default, `-r` only after the second yes, passwd and group backed up byte for byte, a home outside the
  home base, shared or symlinked, `userdel` failure); **SSH settings** (effective values shown, port change
  with the byte-for-byte backup, the line above the `Include`, mode kept, `sshd -t` before the restart,
  old `Port` lines disabled, one managed block after repeated changes, no-op re-run, invalid, busy and
  declined ports, a failing `sshd -t` after the change rolls back without a restart, an already broken
  config refused, a failing or repeatedly failing restart, a port that is not listening, socket
  activation, a drop-in that still adds a port, PermitRootLogin and PasswordAuthentication warnings and the
  stronger confirmations, the cloud-init drop-in beaten, a Match block left alone and warned about, the
  keyboard-interactive note, no `sshd`, no config file, unsupported systems, all five supported
  systems); **Add SSH key** (new file with modes 700/600 and `chown uid:gid`, append with a repaired
  newline and a byte-for-byte backup, duplicates, a private key refused (assembled at run time) and never
  echoed, PuTTY keys, ten kinds of invalid key, every accepted key type, unknown user, missing home,
  symlinked `.ssh` and `authorized_keys`, failing `chown`, root, unsupported systems). Source rules: no
  `/etc/shadow`, no download, no home removal other than `userdel -r`, `passwd` only as
  `passwd -- <name>`, no `read -s` besides the key prompt and the drain, no `sed`/`awk`/`grep`/`ssh-keygen`.
  Each assertion was checked to fail when the behaviour it covers is broken (a scripted mutation run
  removed, one at a time, each refusal, confirmation, backup, `sshd -t`, verification, rollback, `chown`,
  `chmod` and private-key check).
  **Firewall** (`== Firewall module`) runs against **fake backend commands** with file-backed state, so every
  change can be read back: a fake `ufw` (`status verbose`/`numbered` in ufw's column layout, IPv4 and IPv6 rows,
  `app list`/`app info` with its `Port:`/`Ports:` forms, `allow`, `--force delete`), `firewall-cmd` (runtime and
  permanent config per zone, services with `--info-service`, rich rules), `nft` (`-a list ruleset` with a set
  block, an input and a forward chain, handles, `insert rule`, `delete rule ... handle`), `iptables` (`-S INPUT`
  with a policy line, `-I`, `-D`, the real tool's `-m tcp` normalisation), `ss` (tcp and udp listeners with a
  process name) and `sshd` (`-T` ports). Switches make a backend fail, ignore an add, fail a permanent write,
  or change the rules between the listing and the removal. Sandbox `PATH`s hold bash, three coreutils and the
  chosen stubs only. Covered: **detection order** (all four present = ufw, no ufw = firewalld, then nftables,
  then iptables; the other backends' commands are never called; none = the clear message, no submenu, no
  command run, exit 0, also through the main menu); the exact submenu; **status** enabled and disabled for
  each backend with the default policy as reported; **list parsing** for each backend (ids, action, protocol,
  port, range, set, source, application profile and service ports, IPv6 rows, rich rules, other zones, forward
  chains and set definitions not mistaken for rules, ufw's order kept, nothing written); **allow** (port and
  protocol validation with 15 bad ports and 7 bad protocols, boundary ports, case and spaces, the exact
  command, the re-read after the change, the rule as the backend reports it, the saved listing and its modes,
  declined and EOF, **duplicate refusal** by port, range, set, multiport, application profile and service, not
  by another protocol, another source or another zone, idempotent second run, a deny rule warned about, a
  **port in use** warned with the process and address for tcp and udp and allowed after one yes, no `ss`, a
  backend failure, a rule the backend does not report afterwards, a disabled ufw/firewalld refused, firewalld's
  permanent write failing, several nftables input chains, none, `nft` failing); **remove** (the list first,
  exactly one delete call, invalid ids and `all` refused, declined and EOF, re-read afterwards, other rules
  untouched, a changed rule list refused, the backend failing); **SSH protection** (an allow on the SSH port,
  its IPv6 twin, the port from `sshd -T` and from `sshd_config` when there is no `sshd`, the port of the
  current session, a range covering it, the `OpenSSH` profile by ports and by name, the firewalld `ssh`
  service, a rule without port or protocol, a block rule not protected, the second question needed, one yes
  not enough, nothing deleted when declined); unsupported systems refused for changes but not for status/list,
  the five supported systems accepted. Source rules: the fixed backend order, no enable/disable/reset/flush/
  reload/policy/table/chain command, no `sed`/`awk`/`grep`/`curl`, every backend call through `fw_run` in the C
  locale, only the documented ufw subcommands, list and status never reach a changing function, and every
  change starts with the preflight. Each assertion was checked to fail when the behaviour it covers is broken
  (a scripted mutation run removed, one at a time, the SSH protection and its second confirmation, the duplicate
  check, the OS check, each confirmation, the backend order, the port and protocol validation, the re-read
  checks, the changed-rules check, the backup, the in-use warning, the disabled-firewall refusal, `--force`,
  the permanent firewalld write, the nftables/iptables insert position and the port-range, service and
  application-profile coverage).
  **Backup, Check For Updates and Uninstall** (`== Backup, Check For Updates and Uninstall`) run against **fake
  backup directories, fake installed versions (a fake `ezvps` with its `install.state`), fake main versions (a
  fake `ezvps` that is good, has a syntax error, fails or prints no `--version`) and a fake `git`** (it records
  every call and "clones" the fake main; `FAKE_GIT_FAIL=1` makes it fail), a fake `nginx` (`-t` fails on a
  `BROKEN_DIRECTIVE` site), a stub `systemctl`, and a `bash` wrapper whose only difference is that `bash -n`
  fails for one chosen path (that is how a script that passed before the install fails after it). Each scenario
  has its own tree of fake `/usr/local/bin`, `/var/lib/ezvps`, `/var/backups/ezvps`, nginx `conf.d`, certificate
  store (the "private key" is a plain text marker that must never appear in any output), 3x-ui, Backpack and
  tool files, snapshotted with checksums and modes before and after. The sandbox `PATH` holds only the stubs and
  a few coreutils; variants lack `git`, `nginx` or `cmp`. Covered: the exact submenus and dispatch (menu and CLI);
  **create** (mode 700 on the directory and every part, path printed, script/state/sites/certificates byte for
  byte, only ezvps-made regular files as sites, symlinks and hand-written sites left out, other tools' files left
  out, MANIFEST, key mode 600, nothing printed from a key, sources untouched, two backups, no sites/certs/state,
  unusable backup directory, unsupported system, all five supported systems, missing command); **list** (fake
  backups created out of order, newest first including the `-NN` tie-break, size, reason, contents summary,
  incomplete and foreign entries not listed but counted, read-only, no directory created); **restore** (the
  list first, wrong answers and numbers change nothing, `YES` only when exact, the pre-restore backup holds the
  *current* state and exists before anything is restored, script/state/site/certificate/key restored byte for byte
  with modes, nothing deleted, hand-written files and other tools untouched, `nginx -t` before one reload, a
  stopped nginx, a **failing config test rolls certificates and sites back byte for byte with modes and no
  reload**, a hand-written file with the same name kept, nginx missing, a script that fails after the copy put
  back, eleven kinds of tampered backup refused with no pre-restore backup); **check** (update available, up to
  date, no record, record without commit, edited script with the same commit, all reported as unknown rather
  than current; git flags and the exact clone; no git; failed fetch; main without a script; ssh and https
  sources; eleven refused addresses that are never echoed back, six accepted forms; unsupported system; no
  writable backup directory needed); **update** (declined/EOF, the backup before the replacement, old script in
  the backup, installed file byte for byte the fetched one, mode, `bash -n`, `--version`, new record with
  commit, source and sha256, other state files and tools untouched, a second run is a no-op, a candidate with
  a syntax error / failing `--version` / no version refused before anything changes, **rollback when the
  installed script fails its check afterwards** with the record unchanged, not installed, identical script with
  an unknown commit, unusable backup directory, unsupported system, no git, failed fetch); **uninstall** (seven
  wrong answers and EOF change nothing and make no backup, the backup before the removal with its path
  printed, the script and state files gone and checked, **nginx sites, certificates and the key, 3x-ui,
  Backpack, tool binaries, acme.sh, home, ezl2tp and every older backup byte for byte untouched**, a state
  directory with other files kept, leftover temp files, via the main menu, only state files left, nothing to
  uninstall, unusable backup directory, unsupported system, missing command); and **install.sh's install
  record** (commit from a clean checkout, user name/token removed from the origin, ssh origin kept, http origin
  and missing origin left out, a modified script records no commit, a non-git copy, an unwritable state
  directory only warns, re-run idempotent, and Check For Updates reading the record end to end). Source rules:
  git network access only in `lc_fetch_source` and `upd_fetch_latest`, no curl/wget/raw URL/`http://` in the
  new code, `rm -rf` only twice, Uninstall without any service, package or user command, the backup before the
  write in restore/update/uninstall, exact `IFS= read` confirmations, a preflight in every item, no key printed,
  no hardcoded repository. Each assertion was checked to fail when the behaviour it covers is broken (a scripted
  mutation run removed, one at a time, each confirmation, backup, verification, rollback, mode, listing order,
  address check, record check and untouched-tool guarantee).
  It touches nothing outside its temp dir and uses no network.
  `tests/lint.sh` additionally checks that the SSH and Users code never touches `/etc/shadow`, stores no key
  material and downloads nothing, and that the Firewall code never enables, disables, resets or flushes a
  firewall, reloads firewalld, changes a policy, zone, table or chain, uses `sed`/`awk`/`grep`/`curl`, or calls a
  backend outside `fw_run`, and that the detection order is ufw, firewalld, nftables, iptables.
  `tests/lint.sh` additionally checks that the OS allowlist block is identical
  in `ezvps` and `install.sh` and lists exactly the five supported systems, that
  the nginx.org suite is not hardcoded, that the repository URL is the stable
  one (never mainline), the key URL, the fingerprint pins and the priority-900
  pin are present, that `curl` is used only in the 3x-ui download/probe
  functions, `ngx_fetch_key`, `acme_fetch_script` and `lc_fetch_installer`, that the Backpack, ctunnel and Lazyports pins (repository, tag or full commit, SHA-256) are present and well formed and their installer URLs are built from the pin, that the installer runs with `</dev/null`, that git touches the network only in `lc_fetch_source` and `upd_fetch_latest` (https and ssh only), that the Backup, Check For Updates and Uninstall code downloads nothing, uses `rm -rf` only for this run's own discarded backup and the update temp directory, lets Uninstall remove nothing but the script and the state files, and never prints a private key, that the acme.sh pin (tag,
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
