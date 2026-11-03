# ezvps

A bash TUI/CLI VPS manager for the **Debian and Ubuntu LTS families**, run as
**root**. One script, no extra dependencies.

## Supported systems

| System | Version | Codename | Status |
|--------|---------|----------|--------|
| Debian | 12 | `bookworm` | **supported** |
| Debian | 13 | `trixie` | **supported** |
| Ubuntu | 22.04 LTS | `jammy` | **supported** |
| Ubuntu | 24.04 LTS | `noble` | **supported** |
| Ubuntu | 26.04 LTS | `resolute` | **supported** |
| anything else | Ubuntu interim releases (23.10, 25.04, 25.10, 26.10, ...), Debian 11 and older, Debian testing/sid, other distros, derivatives | n/a | **rejected** |

Anything else is rejected by ezvps and by `install.sh` with one message that
lists the supported systems, and nothing is changed. The system is detected
from `/etc/os-release` (`ID`, `VERSION_ID`, `VERSION_CODENAME`; the file is
parsed, never sourced) against an exact allowlist, and **all three values must
agree**: Ubuntu 24.04 with codename `jammy` is rejected as a mismatch, not
accepted as Ubuntu. `ID_LIKE` is ignored, so derivatives such as Linux Mint are
rejected.

### Per module

| Module | Debian 12 | Debian 13 | Ubuntu 22.04 | Ubuntu 24.04 | Ubuntu 26.04 |
|--------|-----------|-----------|--------------|--------------|--------------|
| 3x-ui | yes | yes | yes | yes | yes |
| Nginx (nginx.org stable 1.30+) | yes (`packages/debian`, `bookworm`) | yes (`packages/debian`, `trixie`) | yes (`packages/ubuntu`, `jammy`) | yes (`packages/ubuntu`, `noble`) | yes (`packages/ubuntu`, `resolute`) |
| Certificates (acme.sh) | yes | yes | yes | yes | yes |
| Backpack, ctunnel, Lazyports (x86_64 and aarch64 only) | yes | yes | yes | yes | yes |
| Firewall (whichever of ufw, firewalld, nftables, iptables is present) | yes | yes | yes | yes | yes |
| Backup, Check For Updates, Uninstall (ezvps itself) | yes | yes | yes | yes | yes |
| L2TP | see below | yes | see below | see below | see below |

**L2TP is gated separately.** The L2TP menu item launches the separate ezl2tp
product, so it is available only where ezl2tp itself is supported, which is
currently **Debian 13 only**. ezvps does not port ezl2tp. On every other
system in the table the L2TP item prints a clear message, installs and
launches nothing, and returns to the menu.

> **Status: v0.0.1 in development. The panel is complete: all twelve menu items work.** **L2TP**, **3x-ui**,
> **Backpack**, **ctunnel**, **Nginx**, **Certificates**, **Lazyports**, **SSH and Users**, **Firewall**,
> **Backup**, **Check For Updates** and **Uninstall**. See [SPEC.md](SPEC.md).

## Install

```bash
git clone <repo-url> ezvps
cd ezvps
sudo bash install.sh
```

`install.sh` refuses any system that is not in the supported list above, then
copies the script to `/usr/local/bin/ezvps`. It is safe to
re-run: an identical install is left alone, a changed one is backed up to
`/var/backups/ezvps/` before being replaced. An existing ezl2tp install is
never touched. It also records what it installed (version, commit, the
repository the checkout came from, a checksum) in `/var/lib/ezvps/install.state`,
so Check For Updates can tell whether you are current.

## Use

```bash
sudo ezvps            # interactive menu
sudo ezvps l2tp       # jump straight to a module
ezvps --version
ezvps --help
```

Menu:

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

### L2TP

* **Debian 13 only for now**, because that is what ezl2tp supports. On Debian
  12 and on Ubuntu the module prints that L2TP via ezl2tp is Debian 13 only,
  changes nothing, does not launch or install ezl2tp, and returns to the menu.
* If the `ezl2tp` command is installed, ezvps launches it and brings you
  back to the menu when it exits.
* If not, ezvps prints instructions to install it from its **private**
  repository with `git clone` and your own GitHub authentication, then
  returns to the menu. ezvps never downloads that repo anonymously and does
  not bundle the ezl2tp installer.

### 3x-ui

`ezvps` -> `2` opens a submenu:

```
 1) Install 3x-ui
 2) Install with 3x-ui self installer
 3) Status
 4) Restart
 5) Panel info
 6) Change password
 0) Back
```

* **Install 3x-ui** downloads the official [3x-ui](https://github.com/MHSanaei/3x-ui)
  installer at a **pinned release tag** (`v3.11.0`), shows the URL and its
  SHA-256, verifies the hash and asks before running it (nothing is piped into
  a shell). It then sets port `3389`, user `admin`, password `Admin123`, path
  `xuipanel` and no certificate with the panel's own settings command, and
  checks that the panel answers on that port and path. If a panel already
  exists, its config is backed up first and you are asked before its settings
  are overwritten.
* **Install with 3x-ui self installer** launches the same pinned official
  installer interactively; it asks its own questions and ezvps forces nothing.
* **Status**, **Restart** (only the `x-ui` service), **Panel info** and
  **Change password** (through the panel's own settings command, then a panel
  restart; the new password is never printed, logged or stored).

> **Change the password right after a default install.** `admin` / `Admin123`
> is a well-known default and the default panel runs on plain HTTP (no TLS).
> ezvps prints this warning after every default install: use
> `3x-ui -> Change password` immediately.

The exact source URL, pin and behaviour are in [SPEC.md](SPEC.md) section 6.2.

### Backpack, ctunnel and Lazyports

`ezvps` -> `3`, `4` and `7` open the same submenu for each tool:

```
 1) Install
 2) Status
 3) Update
 4) Uninstall
 0) Back
```

These three tools have **their own interface** (Backpack: an interactive CLI,
ctunnel: a command-line tunnel program, Lazyports: a terminal UI). ezvps manages
only their **lifecycle**. Tunnel setup, ports, tokens, setup links and every other
setting stay in the tool's own interface: ezvps never rebuilds them, never asks for
a tunnel token, setup link, password or key, and never prints, stores or logs one.
After an install it only tells you how to open the tool; it does not launch it.

The same rules apply to all three:

* **Install** is refused, with nothing changed, outside the five supported systems
  and outside `x86_64` / `aarch64`. If the tool is already installed it says so and
  does not reinstall unless you say yes. It shows the official source and the pin,
  asks, backs up any existing config and binary under `/var/backups/ezvps/`, and only
  then runs upstream's documented install. Installer scripts are downloaded to a
  temporary file, checked against a pinned SHA-256 and run with no terminal input
  (never piped into a shell).
* **Status** shows installed or not, the binary path, the version when the tool has a
  documented version command, and whether its services run when upstream documents
  any. Where there is no service it says so instead of inventing one.
* **Update** uses only the tool's documented update method, after a config backup, and
  reports the old and new version when the tool reports them. Where upstream documents
  no update command it says so and offers a reinstall from the documented source.
* **Uninstall** asks for confirmation, backs up the config, removes the tool through
  its documented method and then verifies the binary is gone. Backups are never deleted.

| Tool | Binary | Config backed up | Install (pinned) | Version | Services | Update | Uninstall |
|------|--------|------------------|------------------|---------|----------|--------|-----------|
| [Backpack](https://github.com/AminMGMT/BackPack) | `/usr/local/bin/backpack` | `/etc/backpack` | official `install.sh` at tag `v1.9.0` (SHA-256 checked); it downloads the latest release and verifies it against the release's `SHA256SUMS` | `backpack version` | `backpack-*.service` units (one per tunnel, plus monitor) | Backpack's own **Update** menu item (8): ezvps opens its menu for you to pick it | Backpack's own **Uninstall** menu item (9), same way |
| [ctunnel](https://github.com/alienrobotarmy/ctunnel) | `/usr/local/bin/ctunnel` (+ man page) | `~/.passkey` | upstream has no installer or releases: its documented `make; make install` on one pinned commit (fetched with git) | `ctunnel -v` | none documented | none documented: ezvps says so and offers a reinstall | what `make uninstall` removes: the binary and the man page |
| [Lazyports](https://github.com/v9mirza/lazyports) | `/usr/local/bin/lazyports` or `~/go/bin/lazyports` | none (`~/.bashrc` / `~/.zshrc`, which the installer may extend, are backed up) | official `install.sh` at one pinned commit (SHA-256 checked); needs Go 1.24+ and builds upstream's `main` with `go install` | none documented | none documented | none documented: ezvps says so and offers a reinstall | remove the binary, as upstream documents |

Config backups are byte-for-byte copies that ezvps never reads or prints; they can
contain a tunnel token or key, which is why `/var/backups/ezvps` is root-only. Details,
pins and limits are in [SPEC.md](SPEC.md) sections 6.5 to 6.7.

### Nginx

`ezvps` -> `5` opens a submenu:

```
 1) Install Nginx
 2) Status
 3) Restart
 4) List sites
 5) Add site
 6) Remove site
 0) Back
```

* **Install Nginx** installs nginx **only from the official nginx.org stable
  repository** (stable 1.30 or newer; never the Debian or Ubuntu package,
  never mainline). It adds `https://nginx.org/packages/debian` on Debian or
  `https://nginx.org/packages/ubuntu` on Ubuntu, with the detected codename as
  the suite (`bookworm` or `trixie`; `jammy`, `noble` or `resolute`),
  downloads the signing key from `https://nginx.org/keys/nginx_signing.key`
  and checks it against pinned fingerprints, stores it in
  `/usr/share/keyrings/nginx-archive-keyring.gpg`, and pins origin `nginx.org`
  at priority 900 in `/etc/apt/preferences.d/99nginx` so upgrades stay on
  nginx.org stable. After the install `nginx -v` is checked and the install
  aborts if the version is below 1.30, a mainline build (such as 1.31) or still
  a Debian/Ubuntu package. If a Debian or Ubuntu nginx is installed, `/etc/nginx`
  is backed up, those packages are purged and nginx.org stable is installed; ezvps sites
  are restored/moved to `conf.d` and the config is tested before any reload.
  Nothing is removed unless apt would really pick the nginx.org package. If
  nginx.org stable is already installed it is not reinstalled, only its status
  is shown. Port 80 is checked first and a conflicting service is reported.
* **Status** shows whether the service runs and whether `nginx -t` passes.
  **Restart** runs the config test first and never restarts or reloads a
  broken config.
* **List sites** shows every `*.conf` file in `/etc/nginx/conf.d` with its
  domain, its `proxy_pass` upstream when it has one (also for files not made by
  ezvps) and whether it was created by ezvps (`ezvps` / `not ezvps`). It only
  reads: a file ezvps did not make is never edited.
* **Add site** asks for a domain and an upstream `host:port` and writes
  `/etc/nginx/conf.d/<domain>.conf` (one file per domain; the domain is
  sanitised, only letters, digits, dot and hyphen are accepted). It reloads
  nginx only if `nginx -t` passes (otherwise the change is rolled back), never
  duplicates a site and asks before overwriting; the old file is backed up to
  `/var/backups/ezvps/` first. It also checks that `nginx.conf` includes
  `conf.d` (adding the include after a backup and a config test if not) and,
  if the nginx.org `default.conf` conflicts, asks before disabling it (backup,
  then renamed to `default.conf.disabled`, not deleted). **Remove site** asks for confirmation, backs the file
  up, deletes it and reloads only after a passing test.
* Sites made by an older ezvps in `sites-available`/`sites-enabled` are
  offered a **migration** to `conf.d` (backup, copy, config test, then the old
  files are removed). Declining leaves them alone with a warning that they
  are in the legacy layout.

Sites written by **Add site** are plain HTTP. For HTTPS use the Certificates
module (below), which can switch an ezvps site to HTTPS; the Nginx menu itself
never touches certificates.

**Site template.** Every site is one file with a `location /` that proxies to the
upstream (`proxy_http_version 1.1`, `client_max_body_size 64M`, the `Host`,
`X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Port`, `Upgrade`
and `Connection` headers, 60 s connect and 120 s read/send timeouts). `Connection`
comes from `$connection_upgrade`, not a fixed `"upgrade"`, so WebSocket upgrades
work and normal requests keep `Connection: close` semantics. Before the first such
site is written, ezvps makes sure `nginx.conf` has the standard `map $http_upgrade
$connection_upgrade` exactly once (backup of `nginx.conf` first, config test after,
rollback on failure; an existing map, even in another `conf.d` file, is never
duplicated).

### Certificates

`ezvps` -> `6` opens a submenu:

```
 1) Install acme.sh
 2) Issue certificate
 3) List certificates
 4) Renew certificates
 5) Remove certificate
 0) Back
```

Free Let's Encrypt certificates for **one domain at a time**, validated with
**HTTP-01 through nginx**. There is no wildcard or DNS-API issuance, and ezvps
never asks for or stores DNS provider credentials.

* **Install acme.sh** downloads the official
  [acme.sh](https://github.com/acmesh-official/acme.sh) script at the pinned release
  tag `3.1.6` from
  `https://raw.githubusercontent.com/acmesh-official/acme.sh/3.1.6/acme.sh`, checks its
  SHA-256, and installs it with its own `--install` (never `curl | sh`). If acme.sh is
  already installed it is not reinstalled. The install ends by checking that the
  `acme.sh` command works. Its daily renewal job goes into root's crontab (the old
  crontab is backed up first).
* **Issue certificate** asks for a domain, needs nginx installed and running with
  port 80 listening, and a server block that serves the domain (add the site with
  Nginx -> Add site first). It tells you that **the domain's DNS must point to this
  server** and asks for confirmation before it runs acme.sh. The certificate goes to
  `/etc/ssl/ezvps/<domain>/fullchain.pem` and `privkey.pem` (the key is mode 600,
  root only, and is never printed); an existing certificate for the domain is backed
  up to `/var/backups/ezvps/` first. If an **ezvps site** exists for the domain it
  offers to enable HTTPS: that one `conf.d` file is backed up and rewritten with a
  `listen 443 ssl` server block (`http2 on`, the stored certificate, the same proxy
  block) while the HTTP block becomes a `301` redirect to `https://$host$request_uri`;
  nginx is reloaded only if `nginx -t` passes, otherwise the file is restored. With no
  ezvps site the certificate is only stored and no site is created.
* **List certificates** shows each domain, its expiry date and whether it is used by
  an nginx site.
* **Renew certificates** runs `acme.sh --renew-all` and reloads nginx only if a
  certificate actually changed and the config test passes.
* **Remove certificate** asks for the domain and a confirmation, backs the certificate
  up, restores the plain HTTP proxy block of its ezvps site (site file backed up first,
  config test before the reload, rollback on failure) and removes the stored files; a
  site ezvps did not make that still uses the certificate stops the removal.

The pin, the HTTPS site layout and the details are in [SPEC.md](SPEC.md) section 6.4.

### SSH and Users

`ezvps` -> `8` opens a submenu:

```
 1) List users
 2) Add user
 3) Delete user
 4) SSH settings
 5) Add SSH key
 0) Back
```

* **List users** shows accounts that have a login shell and a home directory, one per row, with
  username, UID and whether the account has sudo access (member of the `sudo` group). Service
  accounts with a `nologin` or `false` shell are hidden unless you ask for the full list. Password
  hashes are never read or shown.
* **Add user** asks for a username (strictly validated; an existing user or group is refused),
  asks whether to grant sudo (adds the user to the `sudo` group only, and checks it worked), creates the
  account with a home directory, and only if you say yes runs the system's own `passwd` prompt. ezvps
  never sees, stores or prints a password.
* **Delete user** refuses `root`, any UID 0 account, the account you are logged in with, system
  accounts and any user that has running processes. It asks for confirmation, and removes the home
  directory only after a separate second confirmation (never by default).
* **SSH settings** changes only the **SSH port**, **PermitRootLogin** and **PasswordAuthentication**,
  one at a time. `sshd_config` is backed up to `/var/backups/ezvps/` first, `sshd -t` must pass
  before sshd is restarted, and the change is rolled back if the test fails, if the setting would not
  take effect (for example a `sshd_config.d` drop-in overrides it), or if sshd does not listen on the
  new port. It warns clearly before anything that can lock you out. The firewall is not changed: open a
  new port yourself before closing the old one, and test from a second terminal.
* **Add SSH key** asks for a user and a public key (typed without echo), refuses anything that is
  not a one-line OpenSSH public key (a private key is refused and never printed), and appends it to
  that user's `~/.ssh/authorized_keys` with mode 700/600 and the right owner. An existing file is
  backed up first and a key that is already there is not added twice.

Details, the exact refusals and the limits are in [SPEC.md](SPEC.md) section 6.8.

### Firewall

`ezvps` -> `9` opens a submenu:

```
 1) Show firewall status
 2) List rules
 3) Allow port
 4) Remove rule
 0) Back
```

ezvps uses the firewall that is **already on the server** and never installs one. The backend is the
first of these whose command exists, in this fixed order:

1. **ufw** (`ufw`)
2. **firewalld** (`firewall-cmd`)
3. **nftables** (`nft`)
4. **iptables** (`iptables`)

Only that backend's own documented commands are used. If none of the four exists, ezvps says so and
returns to the menu without changing anything.

* **Show firewall status** shows whether the backend is enabled or disabled and the default policy it
  reports. (nftables and iptables have no on/off switch: "enabled" means filtering rules or a restrictive
  default policy are loaded.)
* **List rules** is read-only. One rule per row in the backend's own order: ID, action, protocol, port or
  service, source, and the rule as the backend reports it. iptables shows the IPv4 `INPUT` chain and
  nftables its input chains; firewalld shows the ports, services and rich rules of the active zones.
* **Allow port** asks for a port (1-65535, digits only) and `tcp` or `udp`, refuses a port that is
  already allowed (also when a range, a service or an application profile covers it), warns before a port
  that something is already listening on (and still lets you continue after a yes), shows the exact
  command, asks, adds the rule through the backend, then **reads the rules back** and shows the result.
* **Remove rule** lists the rules with their IDs, asks for **one** ID, asks for confirmation and removes
  only that rule, then reads the rules back. It never removes all rules and never disables the firewall.
  A rule that keeps **SSH** reachable (the SSH port from `sshd`, or the port of your current SSH session)
  gets a separate warning and a second confirmation, because removing it can lock you out.

Changes need root and a supported system. A disabled ufw or a firewalld that is not running is not
changed (ezvps never enables or disables a firewall). Before a change, a text copy of the current rule
listing is saved to `/var/backups/ezvps/`. nftables and iptables changes apply to the running firewall
only: ezvps does not rewrite their saved configuration, so save them the way you usually do.

Details and limits are in [SPEC.md](SPEC.md) section 6.9.

### Backup, Check For Updates and Uninstall

These three manage **ezvps itself and nothing else**. They never install, update or remove nginx, 3x-ui,
Backpack, ctunnel, Lazyports or ezl2tp, and never touch those tools' own configs, users or SSH settings.
Each one checks first that you are root, that the system is supported, and (when it writes) that
`/var/backups/ezvps` is writable. After a backup, update, restore or uninstall, the result is checked on
the file system and reported from that, not from the copy command's success.

`ezvps` -> `10` opens the **Backup** submenu:

```
 1) Create backup
 2) List backups
 3) Restore backup
 0) Back
```

* **Create backup** makes `/var/backups/ezvps/ezvps-backup.<UTC time>-NN/` (mode 700) holding the ezvps
  script, the ezvps state files (`/var/lib/ezvps`), the **ezvps-made** nginx sites from `/etc/nginx/conf.d`
  (hand-written sites are not included) and the certificate store `/etc/ssl/ezvps` if present, **private
  keys included** (copied, mode 600, never printed). It lists exactly what went in, compares every file with
  its source, and prints the backup path. The other tools' own configs are not part of it.
* **List backups** shows each backup newest first with its UTC timestamp, size, reason and a summary of its
  contents.
* **Restore backup** lists the backups, asks which one, and requires typing `YES`. It checks the backup
  first, **backs up the current state**, then restores and verifies the files. If nginx sites are restored,
  `nginx -t` must pass before nginx is reloaded; a failing test rolls the certificates and sites back and
  nothing is reloaded. A restore never deletes anything that is not in the backup, and never overwrites a
  hand-written nginx site.

`ezvps` -> `11` opens **Check For Updates**:

```
 1) Check for updates
 2) Update ezvps
 0) Back
```

* The latest version is fetched with **`git` from the private ezvps repository your checkout came from**,
  using your own authentication (GitHub CLI login, SSH key, or a token typed at git's prompt), the same way you
  cloned it for `install.sh`. ezvps never uses an anonymous or public URL for it, and no repository address is
  hardcoded: `install.sh` records the checkout's `origin` (with any user name or token removed), and ezvps
  asks once if none is recorded.
* **Check for updates** compares the installed version and commit with the latest `main` and reports
  installed versus latest. An install with no recorded version or commit (for example one made before
  `install.sh` recorded it, or whose script was edited since) is reported as **unknown**, never as up to date.
* **Update ezvps** shows the plan, asks for a yes, backs up the current script and state, replaces
  `/usr/local/bin/ezvps` with the latest `main`, and checks the new script (`bash -n` and `--version`) before
  and after installing it. If the check after the install fails, the previous script is put back from the
  backup. Tool configs, sites, certificates, users and other state are not touched. Restart ezvps afterwards.

`ezvps` -> `12` is **Uninstall**. It lists what it will remove, requires typing `YES`, makes a backup first
and prints its path, then removes **only `/usr/local/bin/ezvps` and the ezvps state files**, checks that they
are gone, and reports what was removed and what was left untouched (nginx, 3x-ui, Backpack, ctunnel,
Lazyports, their configs, sites, certificates, users). **Backups are never deleted.** To bring ezvps back, run
`install.sh` again or copy `bin/ezvps` out of the backup.

Details are in [SPEC.md](SPEC.md) sections 6.10 to 6.12.

## Principles

Check before installing. Back up before overwriting. Idempotent re-runs. No
hardcoded secrets. No real IPs, secrets or usernames in this repo (tests use
fake data only).

## Development

```bash
bash tests/lint.sh          # bash -n + shellcheck + hygiene scan
bash tests/smoke-test.sh    # menu, L2TP stub, 3x-ui, Nginx, Certificates, Backpack/ctunnel/Lazyports, SSH and Users, Firewall, Backup/Update/Uninstall against fakes, installer
```

`tests/fresh-vps-test.md` is the manual checklist for a throwaway VPS on each
supported Debian and Ubuntu release. Contributor and agent rules are in [AGENTS.md](AGENTS.md).
