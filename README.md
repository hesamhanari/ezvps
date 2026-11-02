# ezvps

A bash TUI/CLI VPS manager for **Debian 13**, run as **root**. One script, no
extra dependencies.

> **Status: v0.0.1 in development.** **L2TP**, **3x-ui** and **Nginx** work so
> far. The other menu items (Backpack, ctunnel, Certificates, Lazyports, SSH
> and Users, Firewall, Backup, Check For Updates, Uninstall) are still pending:
> they print "not implemented yet" and return to the menu. They arrive in
> later releases, one module per PR. See [SPEC.md](SPEC.md).

## Install

```bash
git clone <repo-url> ezvps
cd ezvps
sudo bash install.sh
```

`install.sh` copies the script to `/usr/local/bin/ezvps`. It is safe to
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
  repository** (stable 1.30 or newer; never Debian's package, never mainline).
  It adds `https://nginx.org/packages/debian` for your Debian codename,
  downloads the signing key from `https://nginx.org/keys/nginx_signing.key`
  and checks it against pinned fingerprints, stores it in
  `/usr/share/keyrings/nginx-archive-keyring.gpg`, and pins origin `nginx.org`
  at priority 900 in `/etc/apt/preferences.d/99nginx` so upgrades stay on
  nginx.org stable. After the install `nginx -v` is checked and the install
  aborts if the version is below 1.30, a mainline build (such as 1.31) or still
  a Debian package. If a Debian nginx is installed, `/etc/nginx` is backed up,
  the Debian packages are purged and nginx.org stable is installed; ezvps sites
  are restored/moved to `conf.d` and the config is tested before any reload.
  Nothing is removed unless apt would really pick the nginx.org package. If
  nginx.org stable is already installed it is not reinstalled, only its status
  is shown. Port 80 is checked first and a conflicting service is reported.
* **Status** shows whether the service runs and whether `nginx -t` passes.
  **Restart** runs the config test first and never restarts or reloads a
  broken config.
* **List sites** shows the `*.conf` files in `/etc/nginx/conf.d` with their
  domain and, for sites created by ezvps, the upstream.
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

Sites are **HTTP only** for now. For HTTPS use the Certificates module once it
exists (a later release); the Nginx module does not touch certificates.

## Principles

Check before installing. Back up before overwriting. Idempotent re-runs. No
hardcoded secrets. No real IPs, secrets or usernames in this repo (tests use
fake data only).

## Development

```bash
bash tests/lint.sh          # bash -n + shellcheck + hygiene scan
bash tests/smoke-test.sh    # menu, L2TP stub, 3x-ui and Nginx against fakes, pending modules, installer
```

`tests/fresh-vps-test.md` is the manual checklist for a throwaway Debian 13
VPS. Contributor and agent rules are in [AGENTS.md](AGENTS.md).
