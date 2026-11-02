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
| L2TP | see below | yes | see below | see below | see below |

**L2TP is gated separately.** The L2TP menu item launches the separate ezl2tp
product, so it is available only where ezl2tp itself is supported, which is
currently **Debian 13 only**. ezvps does not port ezl2tp. On every other
system in the table the L2TP item prints a clear message, installs and
launches nothing, and returns to the menu.

> **Status: v0.0.1 in development.** **L2TP**, **3x-ui**, **Backpack**,
> **ctunnel**, **Nginx**, **Certificates** and **Lazyports** work so far. The other
> menu items (SSH and Users, Firewall, Backup, Check For Updates, Uninstall) are still pending:
> they print "not implemented yet" and return to the menu. They arrive in
> later releases, one module per PR. See [SPEC.md](SPEC.md).

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
never touched.

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

## Principles

Check before installing. Back up before overwriting. Idempotent re-runs. No
hardcoded secrets. No real IPs, secrets or usernames in this repo (tests use
fake data only).

## Development

```bash
bash tests/lint.sh          # bash -n + shellcheck + hygiene scan
bash tests/smoke-test.sh    # menu, L2TP stub, 3x-ui, Nginx, Certificates, Backpack/ctunnel/Lazyports against fakes, pending modules, installer
```

`tests/fresh-vps-test.md` is the manual checklist for a throwaway VPS on each
supported Debian and Ubuntu release. Contributor and agent rules are in [AGENTS.md](AGENTS.md).
