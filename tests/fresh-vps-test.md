# Fresh VPS test (manual)

Run on a **throwaway VPS of each supported release** (Debian 12 `bookworm`,
Debian 13 `trixie`, Ubuntu 22.04 `jammy`, Ubuntu 24.04 `noble`, Ubuntu 26.04
`resolute`), as root, before merging changes that touch the installer or a
module. Where they differ the steps say so (Ubuntu: `nginx.org/packages/ubuntu`;
L2TP is Debian 13 only). Use fake data only; do not paste real IPs,
tokens or usernames into notes or issues. Placeholders: `<owner>`,
`192.0.2.10`, `example.com`, `testuser`.

Tick each box; note failures with the exact output.

## 0. Prerequisites

- [ ] `cat /etc/os-release` shows one of: Debian 12 (`ID=debian`,
      `VERSION_ID="12"`, `bookworm`), Debian 13 (`13`, `trixie`), Ubuntu 22.04
      (`ID=ubuntu`, `VERSION_ID="22.04"`, `jammy`), Ubuntu 24.04 (`24.04`,
      `noble`) or Ubuntu 26.04 (`26.04`, `resolute`); note which one this run is
- [ ] `id -u` prints `0`
- [ ] `git` is available (`git --version`); if not, `apt-get install -y git`
- [ ] `command -v ezvps` prints nothing (clean start)
- [ ] Note whether `command -v ezl2tp` finds anything (this decides section 3)

## 1. Fresh install

```bash
git clone <repo-url> ezvps && cd ezvps
bash tests/lint.sh        # optional here; needs shellcheck
bash tests/smoke-test.sh
bash install.sh
```

- [ ] smoke test: `0 failed`
- [ ] `install.sh` exits 0 and prints `Installed ezvps to /usr/local/bin/ezvps`
- [ ] `ls -l /usr/local/bin/ezvps` shows mode `-rwxr-xr-x`, owner root
- [ ] `ezvps --version` prints `ezvps 0.0.1-dev`
- [ ] `ezvps --help` prints usage

## 2. Re-run safety

```bash
bash install.sh
echo '# local edit' >> /usr/local/bin/ezvps
bash install.sh
ls /var/backups/ezvps/
```

- [ ] first re-run prints `already up to date` and creates no backup
- [ ] after the local edit, install.sh prints `Backed up existing ...`
- [ ] exactly one `ezvps.<timestamp>.<pid>` backup exists and contains `# local edit`
- [ ] `cmp ezvps /usr/local/bin/ezvps` reports no difference

## 3. L2TP

**3-other. Debian 12 and Ubuntu 22.04 / 24.04 / 26.04** (L2TP via ezl2tp is
Debian 13 only for now; do the Debian steps below on Debian 13 and only this
block on every other supported system)

- [ ] `ezvps` -> `1` prints `L2TP via ezl2tp is Debian 13 only for now (found
      <System> <version>, <codename>).` and `Nothing was changed.`, then the
      menu returns
- [ ] no `Launching ezl2tp...` and no git clone instructions, even if an
      `ezl2tp` command exists; nothing was installed (`command -v ezl2tp`
      unchanged)
- [ ] `ezvps l2tp` prints the same message and exits 0

**3a. ezl2tp NOT installed**

- [ ] `ezvps` -> `1` shows "ezl2tp is not installed" plus git clone instructions
- [ ] instructions mention the private repo and authentication; no raw download command
- [ ] after Enter, the menu is shown again; `0` exits with status 0

**3b. ezl2tp installed** (install it yourself via the git clone route; do not
script it from ezvps)

- [ ] `ezvps` -> `1` prints `Launching ezl2tp...` and ezl2tp's own menu opens
- [ ] leaving ezl2tp prints `Returned to ezvps.` and the ezvps menu returns
- [ ] re-run `bash install.sh`: output says `ezl2tp found; left untouched.`
      and `sha256sum "$(command -v ezl2tp)"` is the same before and after

## 4. Menu and not-yet-implemented modules

- [ ] menu lines match exactly (no description text):
      `L2TP, 3x-ui, Backpack, ctunnel, Nginx, Certificates, Lazyports,
      SSH and Users, Firewall, Backup, Check For Updates, Uninstall`, then `0) Exit`
- [ ] each of `10` to `12` prints `<Label> is not implemented yet.` and returns to
      the menu after Enter (`2` opens the 3x-ui submenu, section 5; `3`, `4` and `7`
      open the Backpack, ctunnel and Lazyports submenus, section 8; `5` opens the
      Nginx submenu, section 6; `6` opens the Certificates submenu, section 7; `8`
      opens the SSH and Users submenu, section 9; `9` opens the Firewall submenu, section 10)
- [ ] `abc`, `13`, empty input -> `Invalid choice`, menu continues
- [ ] `ezvps backup` (and `update`, `uninstall`) print the same message, exit 0
- [ ] `ezvps bogus` prints usage, exit 2
- [ ] Ctrl-D at the prompt exits cleanly

## 5. 3x-ui

Needs outbound HTTPS to github.com. Use a VPS where nothing listens on
port 3389 (`ss -ltn | grep :3389` prints nothing). Do not use real
credentials; the default password is a known value and the VPS is throwaway.

**5a. Submenu and prechecks**

- [ ] `ezvps` -> `2` shows exactly: `1) Install 3x-ui`, `2) Install with 3x-ui
      self installer`, `3) Status`, `4) Restart`, `5) Panel info`,
      `6) Change password`, `0) Back` (no description text)
- [ ] `Status`, `Restart`, `Panel info`, `Change password` before any install
      print `3x-ui is not installed.` and return to the submenu
- [ ] `0` returns to the main menu; invalid input prints `Invalid choice`
- [ ] on an unsupported host (for example Ubuntu 25.10 or Debian 11; optional,
      only on another throwaway VPS) the install options refuse with
      `needs a supported system: Debian 12 (bookworm), ...` and change nothing
- [ ] with port 3389 occupied (`python3 -m http.server 3389 &`) `Install 3x-ui`
      says `Port 3389 is already in use` and changes nothing; stop the listener
- [ ] on an image without curl (`command -v curl` empty) the install asks
      before `apt-get install curl`; answering `n` cancels cleanly

**5b. Default install**

- [ ] `1) Install 3x-ui` prints the project, tag `v3.11.0`, the URL
      `https://raw.githubusercontent.com/MHSanaei/3x-ui/v3.11.0/install.sh`
      and the sha256, then asks; answer `y`
- [ ] `Downloaded installer matches the pinned sha256.` appears; the upstream
      installer runs without asking anything
- [ ] output ends with `Verified: the panel answers on
      http://127.0.0.1:3389/xuipanel/ (HTTP 200)`
- [ ] the yellow `WARNING: CHANGE THE PANEL PASSWORD NOW` block is shown and
      mentions plain HTTP
- [ ] `systemctl is-active x-ui` prints `active`; `ss -ltn | grep :3389` shows the panel
- [ ] from your own machine, `http://<server-ip>:3389/xuipanel/` shows the
      3x-ui login page; `admin` / `Admin123` logs in
- [ ] `x-ui setting -show=true` (or `/usr/local/x-ui/x-ui setting -show=true`)
      reports port 3389, path `/xuipanel/` and `not secure with SSL`
- [ ] `cat /var/lib/ezvps/3x-ui.state` shows `mode=default`, `username=admin`,
      `password_default=1` and **no password**; `ls -ld /var/lib/ezvps` is 700
- [ ] no backup was made (`ls /var/backups/ezvps/` has no `x-ui.*`): nothing existed

**5c. Re-run and existing panel**

- [ ] `1) Install 3x-ui` again: prints `already has the ezvps default
      settings`, downloads nothing, creates no backup, still verifies and warns
- [ ] change the port in the panel UI (e.g. to 2053), then `1) Install 3x-ui`:
      `An existing 3x-ui panel was found` with its port; a backup
      `/var/backups/ezvps/x-ui.<timestamp>.<pid>/` (mode 700, contains `db/`)
      exists **before** the overwrite question; answer `n` -> panel still on 2053
- [ ] again, answer `y` -> panel back on 3389 / `xuipanel`; backup still holds the old db

**5d. Status, Restart, Panel info**

- [ ] `3) Status` shows service running, port 3389, path `/xuipanel/`,
      `no (plain HTTP)`, `Responds: yes (HTTP 200 ...)`, and the default-password nag
- [ ] `systemctl stop x-ui`, then `3) Status` shows `not running` and `Responds: NO`
- [ ] `4) Restart` brings it back and prints `Verified`; `journalctl -u x-ui`
      shows only the x-ui service restarting (`systemctl status xray` unaffected / n/a)
- [ ] `5) Panel info` shows URL, port 3389, path `/xuipanel/`, username `admin`,
      the default-password line and the warning

**5e. Change password**

- [ ] `6) Change password`: mismatched passwords, fewer than 8 characters and
      `Admin123` are each rejected with nothing changed (`admin`/`Admin123` still logs in)
- [ ] a good new password: backup created, panel restarted, `Verified` printed
- [ ] the new password does **not** appear in the terminal output, in
      `cat /var/lib/ezvps/3x-ui.state`, or in `grep -r '<new password>' /var/backups/ezvps /var/lib/ezvps`
      (the panel database stores only a hash)
- [ ] the old password no longer logs in; the new one does
- [ ] `5) Panel info` no longer shows the default-password line or warning
      (`password_default=0` in the state file)

**5f. Self installer** (use a fresh VPS, or remove 3x-ui first with its own
`x-ui uninstall`, then `rm -rf /var/lib/ezvps/3x-ui.state`)

- [ ] `2) Install with 3x-ui self installer` shows the same download details,
      asks, verifies the hash and prints `Launching the 3x-ui installer...`
- [ ] the upstream installer asks its own questions (port, SSL choice, ...);
      ezvps pre-answers nothing; answer them and note the credentials it prints
- [ ] on exit `Returned to ezvps.` and the Status block are shown; no
      default-password warning
- [ ] `5) Panel info` shows the port/path you chose and says the password is
      the one set during the self installer and is not stored by ezvps;
      `cat /var/lib/ezvps/3x-ui.state` has `mode=self` and no password
- [ ] Ctrl-C inside the upstream installer stops the installer but keeps ezvps running
- [ ] run it again over the existing panel: a backup including the `x-ui`
      binary exists before the installer starts

## 6. Nginx

Needs outbound HTTPS to the Debian/Ubuntu mirrors (apt) and to `nginx.org`. Start from an image where
`command -v nginx` prints nothing and nothing listens on port 80
(`ss -ltn | grep ':80 '` prints nothing). Use `example.com`-style placeholder
domains and a throwaway backend such as `python3 -m http.server 3000
--bind 127.0.0.1`; do not use real domains or paste real IPs into notes.

**6a. Submenu and detection**

- [ ] `ezvps` -> `5` shows exactly: `1) Install Nginx`, `2) Status`,
      `3) Restart`, `4) List sites`, `5) Add site`, `6) Remove site`,
      `0) Back` (no description text); `0` returns to the main menu
- [ ] before installing, items `2` to `6` print `Nginx is not installed.` and
      return to the submenu
- [ ] with another program on port 80 (`python3 -m http.server 80 &`),
      `1) Install Nginx` warns `Port 80 is already in use by another service`,
      shows the listener and asks before going on; answer `n`, nothing is
      installed; stop the listener

**6b. Install (nginx.org stable only)**

- [ ] `1) Install Nginx`: the plan names the `https://nginx.org/packages/debian`
      repository line with this system's codename (`bookworm` or `trixie`) or
      the `https://nginx.org/packages/ubuntu` line (`jammy`, `noble` or
      `resolute`), the key URL, the pin (`origin nginx.org,
      priority 900`) and says stable 1.30 or newer; answer `n` first: nothing
      is changed (`ls /etc/apt/sources.list.d/nginx.list` fails), then repeat
      with `y`
- [ ] the key fingerprints are listed as `matches the pinned nginx.org key`;
      `/usr/share/keyrings/nginx-archive-keyring.gpg` exists
      (`gpg --show-keys /usr/share/keyrings/nginx-archive-keyring.gpg` shows
      the same fingerprints)
- [ ] `cat /etc/apt/sources.list.d/nginx.list` is exactly `deb
      [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg]
      https://nginx.org/packages/debian <codename> nginx` on Debian, or `...
      https://nginx.org/packages/ubuntu <codename> nginx` on Ubuntu, where
      `<codename>` is this system's own (no `mainline`);
      `cat /etc/apt/preferences.d/99nginx` has `Package: *`, `Pin: origin
      nginx.org`, `Pin-Priority: 900`
- [ ] `apt-cache policy nginx` shows candidate `1.30.x-1~<codename>` or newer
      stable (even minor), with the nginx.org
      source above the distribution's own
- [ ] output shows `Version check passes: nginx/1.30.x (nginx.org stable)`;
      `nginx -v` agrees; `dpkg-query -W -f='${Version}\n' nginx` ends in
      `~<codename>`; `systemctl is-enabled nginx` is `enabled`, `systemctl
      is-active nginx` is `active`
- [ ] output shows `Config test passes.` and `Verified: nginx answers on
      127.0.0.1:80 (HTTP 200)`, then the HTTP-only / Certificates note
- [ ] `curl -sI http://127.0.0.1/` shows the nginx.org welcome page headers;
      `/etc/nginx/conf.d/default.conf` exists, and `/etc/nginx/sites-enabled`
      does not
- [ ] running `1) Install Nginx` again says `already installed ... Not
      reinstalling`, shows the status, downloads no key and runs no `apt`
      (`grep -c 'Commandline: apt-get install' /var/log/apt/history.log`
      did not grow)
- [ ] `apt-get upgrade` never offers a Debian/Ubuntu `nginx` (`apt-cache policy
      nginx`: nginx.org stays the candidate)
- [ ] mainline refusal: add `deb https://nginx.org/packages/mainline/debian
      <codename> nginx` (Ubuntu: `.../mainline/ubuntu <codename> nginx`) to a file in `/etc/apt/sources.list.d/` on a *fresh*
      image: `1) Install Nginx` says `MAINLINE source is configured in ...` and
      changes nothing; remove the file

**6b2. Replacing a Debian or Ubuntu nginx** (use a throwaway image: this removes a package)

- [ ] on a fresh image `apt-get install -y nginx` (the distribution's package,
      version `1.26.x-...+deb13...` on Debian, `1.24.x-...ubuntu...` on Ubuntu); create an old-layout ezvps site and a hand-written
      one: write `/etc/nginx/sites-available/old.example.com` with the `# Managed by ezvps`
      / `# ezvps:domain=old.example.com` / `# ezvps:upstream=127.0.0.1:3000`
      header and a `server { listen 80; server_name old.example.com; ... }`,
      enable it with a symlink in `sites-enabled`, and add a hand-written
      `/etc/nginx/conf.d/hand.conf` (`server_name hand.example.com;`)
- [ ] `1) Install Nginx`: the plan says an nginx package that is not from
      nginx.org will be REPLACED and lists the packages to purge; `y`
- [ ] `/var/backups/ezvps/nginx-etc.<timestamp>.<pid>/` exists and contains the
      old `nginx.conf`, `sites-available/old.example.com` and `conf.d/hand.conf`,
      and was created before `apt-get purge` ran (see `/var/log/apt/history.log`
      timestamps / the terminal order)
- [ ] afterwards `dpkg -l | grep nginx` shows only the nginx.org `nginx`
      (`~<codename>`), `nginx -v` is stable 1.30+, and the pin exists
- [ ] `/etc/nginx/conf.d/old.example.com.conf` exists (moved, with the
      marker), the `sites-enabled` symlink and the `sites-available` file for it
      are gone; `nginx -t` passes and the log shows the reload came after the
      config test
- [ ] the hand-written `conf.d/hand.conf` is either still there or, if it was
      removed by the purge, listed under `Not restored automatically` with the
      backup path (it is never silently lost: it is in the backup)

**6c. Status and Restart**

- [ ] `2) Status`: version, `nginx - running (boot: enabled)`, `Config test:
      passes`, `Responds: yes (HTTP 200 ...)`
- [ ] `3) Restart`: prints `Config test passes. Restarting nginx...` and
      `Verified`; `systemctl status nginx` shows a fresh start time
- [ ] break the config on purpose (`echo 'BROKEN_DIRECTIVE on;' >>
      /etc/nginx/conf.d/zz.conf`), then: `2) Status` shows `Config
      test: FAILS` with nginx's error; `3) Restart` says `nginx was NOT
      restarted or reloaded` and the nginx process id / start time is
      unchanged (`systemctl show -p MainPID,ActiveEnterTimestamp nginx`)
- [ ] remove the broken line again (delete `conf.d/zz.conf`); `3) Restart` works

**6d. Add site** (sites live in `/etc/nginx/conf.d/<domain>.conf`)

- [ ] start the backend: `python3 -m http.server 3000 --bind 127.0.0.1 &`
- [ ] `grep -n 'conf.d' /etc/nginx/nginx.conf` shows the stock
      `include /etc/nginx/conf.d/*.conf;` inside `http { }`
- [ ] `5) Add site` with `Example.COM` and `127.0.0.1:3000`:
      `/etc/nginx/conf.d/example.com.conf` exists with the `# Managed by
      ezvps` header and `# ezvps:domain=` / `# ezvps:upstream=` lines; nothing
      new in `sites-available` or `sites-enabled`; output says `Config test
      passes.` and `nginx reloaded.`; no `ssl` or `443` anywhere in the file.
      The nginx.org `default.conf` listens on port 80, so ezvps first warns
      that it may conflict and asks: answer `y` once, check that
      `/etc/nginx/conf.d/default.conf` is gone, `default.conf.disabled` exists
      with the original content, and
      `/var/backups/ezvps/nginx-default-conf.*` exists
- [ ] `curl -s -H 'Host: example.com' http://127.0.0.1/` returns the backend's
      directory listing (reverse proxy works); with the backend stopped it returns 502
- [ ] the message says the site is HTTP only and to use Certificates -> Issue
      certificate for HTTPS; no certificate was created (`/etc/ssl/ezvps` does not exist yet)
- [ ] site template: `cat /etc/nginx/conf.d/example.com.conf` has
      `client_max_body_size 64M;`, `proxy_http_version 1.1;`, the headers `Host`,
      `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Port`, `Upgrade`,
      `Connection $connection_upgrade` (no literal `"upgrade"`), and
      `proxy_connect_timeout 60s;` / `proxy_read_timeout 120s;` / `proxy_send_timeout 120s;`
- [ ] connection map: `/etc/nginx/nginx.conf` now has
      `map $http_upgrade $connection_upgrade {` exactly once inside `http { }`
      (`grep -c 'map \$http_upgrade' /etc/nginx/nginx.conf` prints `1`), a backup
      `/var/backups/ezvps/nginx.conf-map.<timestamp>.<pid>` equals the old file, and
      `nginx -t` passes; adding a second site does not add the map or a backup again
- [ ] WebSocket headers: with a backend that prints request headers, a normal
      `curl --http1.1 -H 'Host: example.com' http://127.0.0.1/` shows `Connection: close`,
      and adding `-H 'Upgrade: websocket' -H 'Connection: Upgrade'` shows
      `Connection: upgrade`
- [ ] the same `5) Add site` again: `already exists with the same upstream ...
      Nothing to do`; no new file, no backup, no second reload (journal)
- [ ] `5) Add site` `example.com` with `127.0.0.1:4000`: asks before
      overwriting; `n` changes nothing; `y` backs up the old file to
      `/var/backups/ezvps/nginx-site-example.com.<timestamp>.<pid>` (contains
      the old upstream) and updates the site
- [ ] invalid input is rejected without changes: domains `localhost`,
      `bad_name.com`, `a b.com`, `../etc/passwd`, `a/b.example.com` (the last
      two say `contains a path separator`; no `*.conf` appears outside
      `conf.d`); upstreams `127.0.0.1` (no port), `127.0.0.1:99999`, `https://127.0.0.1:443`
- [ ] domain already served by a hand-made file (create
      `/etc/nginx/conf.d/legacy.conf` with `server_name taken.example.com;`):
      adding `taken.example.com` is refused
- [ ] failing test is rolled back: add a hand-made file with
      `BROKEN_DIRECTIVE on;` to `/etc/nginx/conf.d/zz.conf`, then `Add site`
      `new.example.com`: `config test FAILED`, `Rolled back`, no
      `conf.d/new.example.com.conf`, nginx not reloaded (journal shows no
      reload); remove `zz.conf`
- [ ] missing include: comment out the `include /etc/nginx/conf.d/*.conf;`
      line in `/etc/nginx/nginx.conf`, then `Add site` `inc.example.com`:
      ezvps reports the missing include, backs up `nginx.conf` to
      `/var/backups/ezvps/nginx.conf.<timestamp>.<pid>`, adds the line inside
      the `http` block (once), `nginx -t` passes and the site works
- [ ] `systemctl stop nginx`, `Add site` `idle.example.com`: file written,
      `nginx is not running, so nothing was reloaded`; `systemctl start nginx`

**6e. List and Remove**

- [ ] `4) List sites`: table of `conf.d/*.conf` with `example.com.conf
      example.com 127.0.0.1:4000 ezvps` and `default.conf localhost - not ezvps`
      (until disabled) and `legacy.conf taken.example.com - not ezvps`;
      `sites-enabled` entries are not listed
- [ ] List sites shows the upstream of a file ezvps did not make: add
      `/etc/nginx/conf.d/hand.conf` with `server_name hand.example.com;` and
      `location / { proxy_pass http://127.0.0.1:8080; }` and check the row
      `hand.conf hand.example.com 127.0.0.1:8080 not ezvps`; `sha256sum` of every
      file in `conf.d` is the same before and after (List never edits)
- [ ] `6) Remove site` with an unknown domain: `No site named ...`, nothing changed
- [ ] `6) Remove site` `example.com`, answer `n`: file remains, no backup
- [ ] `6) Remove site` `example.com`, answer `y`: backup
      `nginx-site-example.com.<timestamp>.<pid>` exists and matches the old
      file, the file is gone, `Config test passes.`, `nginx reloaded.`, other
      sites untouched, and nothing in `sites-enabled` was deleted
- [ ] `6) Remove site` on the hand-made `legacy` domain warns `NOT created by
      ezvps` before asking
- [ ] clean up: remove `legacy.conf`, `idle.example.com` and the other test
      sites, stop the backend

**6f. Migration from the legacy layout**

- [ ] create a legacy ezvps site by hand:
      `printf '%s\n' '# Managed by ezvps (Nginx module). fixture' '# ezvps:domain=old.example.com' '# ezvps:upstream=127.0.0.1:3000' 'server {' '    listen 80;' '    server_name old.example.com;' '    location / { proxy_pass http://127.0.0.1:3000; }' '}' > /etc/nginx/sites-available/old.example.com`
      and `ln -s /etc/nginx/sites-available/old.example.com /etc/nginx/sites-enabled/old.example.com`;
      also a hand-written enabled site `hand.example.com` and a disabled ezvps-style one
- [ ] `4) List sites`, answer `n`: files unchanged, warning that the site is
      still in the legacy layout; no backup, no reload
- [ ] `4) List sites` again, answer `y`: backups
      `nginx-legacy-old.example.com.*` (file) and `...enabled.*` (symlink) in
      `/var/backups/ezvps`, `conf.d/old.example.com.conf` identical to the
      original, the `sites-enabled` symlink and the `sites-available` file are
      gone, `nginx -t` passes, nginx reloaded; the hand-written site and the
      disabled one are untouched (the disabled one is named in the warning)
- [ ] the migrated site now appears in the table and works with `curl -H 'Host: old.example.com' http://127.0.0.1/`
- [ ] clean up: remove the test sites and backups

## 7. Certificates

Needs outbound HTTPS to raw.githubusercontent.com, acme-v02.api.letsencrypt.org
and nginx.org, **a real domain whose A record points at this VPS** (use a
throwaway name you control, never one in production), and ports 80 and 443 open
to the internet. Let's Encrypt rate limits apply: do not repeat Issue more often
than needed. nginx (section 6) must be installed and running, and the domain must
be served by an nginx site, for example `5) Add site` in the Nginx submenu with the
test domain and a backend on `127.0.0.1:3000` (`python3 -m http.server 3000`).

**7a. Submenu**
- [ ] `ezvps` -> `6` shows exactly: `1) Install acme.sh`, `2) Issue certificate`,
      `3) List certificates`, `4) Renew certificates`, `5) Remove certificate`,
      `0) Back`; `abc` prints `Invalid choice: abc`; Ctrl-D exits cleanly
- [ ] with acme.sh not installed, `2`, `3` (empty list is fine), `4` and `5` do not
      fail: `2` and `4` say `Choose 'Install acme.sh' first.`

**7b. Install acme.sh**
- [ ] `1) Install acme.sh`: the plan shows
      `https://raw.githubusercontent.com/acmesh-official/acme.sh/3.1.6/acme.sh`,
      the pinned sha256 `c7d68b021cfd6380ea83a82962abde5b484779fee0b97d38681dfa1396bbc8d7`
      and the home `/root/.acme.sh`; answering `n` changes nothing (`ls /root/.acme.sh` fails)
- [ ] `y`: `Downloaded acme.sh matches the pinned sha256.`, then
      `Verified: the acme.sh command works (v3.1.6, /root/.acme.sh/acme.sh)`;
      `crontab -l` has one `acme.sh --cron` line; your shell profile (`~/.bashrc`)
      was not modified; if root already had a crontab it is saved in
      `/var/backups/ezvps/crontab-root.*` (mode 600)
- [ ] `1) Install acme.sh` again: `already installed ... Not reinstalling.` and no download
- [ ] on an image without `crontab` (`apt-get purge -y cron` first): the plan warns it
      installs WITHOUT the renewal job and `acme.sh --install ... --nocron` is used

**7c. Issue certificate**
- [ ] with nginx stopped (`systemctl stop nginx`): refused, `nginx is not running`;
      start it again
- [ ] a domain no nginx site serves is refused (`No nginx server block serves ...`),
      and `*.example.com`, `a.example.com,b.example.com` and `a b` are rejected
- [ ] `2) Issue certificate` with the test domain: the output says the DNS record
      must point to THIS server, mentions port 80, and states that no DNS provider
      credentials are asked for; answer `n`: nothing changes (no
      `/etc/ssl/ezvps`, no acme.sh run)
- [ ] answer `y`: acme.sh succeeds, then
      `ls -l /etc/ssl/ezvps/<domain>` shows `fullchain.pem` (644) and `privkey.pem`
      (600), `stat -c %a /etc/ssl/ezvps /etc/ssl/ezvps/<domain>` prints `700 700`;
      the expiry is shown; **no private key text appears anywhere in the output**
- [ ] `grep -c 'ACME_NGINX_START' /etc/nginx/conf.d/*.conf` prints 0 everywhere
      (acme.sh put the file back) and `nginx -t` passes
- [ ] the HTTPS offer names the site; answer `y`: `/var/backups/ezvps/nginx-site-<domain>.*`
      holds the old plain file, `conf.d/<domain>.conf` now has `# ezvps:https=on`, a
      `listen 80` block whose `location /` is `return 301 https://$host$request_uri;`,
      and a `listen 443 ssl;` block with `http2 on;`, `ssl_certificate
      /etc/ssl/ezvps/<domain>/fullchain.pem;`, `ssl_certificate_key
      /etc/ssl/ezvps/<domain>/privkey.pem;` and the proxy location; no `4443`, no `stream`
- [ ] `curl -sI http://<domain>/x` is `301` with `Location: https://<domain>/x`;
      `curl -s https://<domain>/` returns the backend with a valid certificate (no `-k`);
      `curl -sI --http2 https://<domain>/` reports `HTTP/2 200`
- [ ] the same `2) Issue certificate` again: the existing certificate is mentioned and
      backed up to `/var/backups/ezvps/cert-<domain>.*` (its `privkey.pem` is still
      mode 600), acme.sh says it is not due, `HTTPS is already enabled` and nginx reloads
- [ ] a hand-written site: create `/etc/nginx/conf.d/other.conf` with
      `server_name other.example.org;` (a second name you control), issue for it: the
      certificate is stored, `There is no ezvps nginx site ...`, `other.conf` is unchanged
- [ ] failing config test during the HTTPS offer rolls back: put
      `BROKEN_DIRECTIVE on;` in `/etc/nginx/conf.d/zz.conf` before answering `y` to a
      fresh offer, then check `config test FAILED`, `Rolled back`, the site file equal
      to the backup and nginx not reloaded; remove `zz.conf`

**7d. List, Renew, Remove**
- [ ] `3) List certificates`: one row per certificate with the expiry date,
      `(N days left)` and `yes (<domain>.conf)` for the site; read-only
- [ ] `4) Renew certificates`: acme.sh reports the certificate is not due,
      `No certificate was renewed ... nginx was not reloaded.` and the journal shows no
      reload; (to see a real renewal: `/root/.acme.sh/acme.sh --renew -d <domain> --force`
      works too, then `4)` on the next day)
- [ ] `5) Remove certificate` with an unknown domain: `No certificate for ...`; with the
      test domain answering `n`: nothing changes
- [ ] `5) Remove certificate`, `y`: backups `cert-<domain>.*` (key mode 600) and
      `nginx-site-<domain>.*` (the HTTPS version) exist, `conf.d/<domain>.conf` is the
      plain HTTP proxy again (no `ssl`, no `443`, no `https=on`), `/etc/ssl/ezvps/<domain>`
      is gone, `acme.sh will no longer renew`, `nginx -t` passes and nginx reloaded;
      `curl -s http://<domain>/` reaches the backend over HTTP again
- [ ] with `other.conf` (hand-written) using a stored certificate through
      `ssl_certificate /etc/ssl/ezvps/<domain>/fullchain.pem;`, Remove refuses and names
      that file; nothing changes
- [ ] clean up: remove the test sites, `rm -rf /root/.acme.sh` if you want acme.sh gone
      (`crontab -e` to drop its line), and `/etc/ssl/ezvps`

## 8. Backpack, ctunnel and Lazyports

Needs outbound HTTPS to github.com and raw.githubusercontent.com (Backpack's
installer also downloads its release from GitHub). Do this on a throwaway VPS,
**once per supported release and once per architecture you care about**
(`x86_64`, `aarch64`). Use fake or throwaway values only: ezvps never asks for a
tunnel token, setup link, password or key, so do not type any into ezvps. All
tunnel setup in this section happens inside each tool's own interface.

**8a. Submenus (all three)**
- [ ] `ezvps` -> `3`, `4`, `7` each show exactly `1) Install`, `2) Status`,
      `3) Update`, `4) Uninstall`, `0) Back` under the tool's name; `abc` prints
      `Invalid choice: abc`; Ctrl-D exits cleanly
- [ ] with the tool not installed, `Status`, `Update` and `Uninstall` each say it is
      not installed and change nothing

**8b. Unsupported systems and architectures** (use a spare VM or a copy of
`/etc/os-release` via `EZVPS_OS_RELEASE`; do not edit the real file)
- [ ] on Ubuntu 25.10, Debian 11 or a derivative, `Install` of each tool prints the
      `needs a supported system` message and changes nothing (no download, no file)
- [ ] on an `armv7l` or `i686` machine, `Install` prints
      `does not support architecture '...' (supported: x86_64, aarch64)`

**8c. Backpack**
- [ ] `Install` shows the project, the installer URL
      `https://raw.githubusercontent.com/AminMGMT/BackPack/v1.9.0/install.sh`, the tag,
      the expected SHA-256 and what the installer does; answering `n` downloads and
      changes nothing
- [ ] answering `y` installs `/usr/local/bin/backpack`, `/etc/backpack` and
      `/root/BackPack`; **Backpack's menu does not open**; ezvps prints only
      `To open Backpack: run: backpack` and the version (`backpack version`)
- [ ] `Install` again: it says Backpack is already installed and asks before
      reinstalling; `n` changes nothing
- [ ] open Backpack yourself (`backpack`), create a throwaway tunnel with fake values
      (for example a TCP tunnel to `192.0.2.10`), exit; `Status` now lists
      `backpack-<name>.service` with its state (`systemctl list-units 'backpack-*'`
      agrees); ezvps never showed the tunnel token
- [ ] `Update`: ezvps backs up `/etc/backpack` to `/var/backups/ezvps/backpack-1-backpack.*`
      (`diff -r` against `/etc/backpack`), opens Backpack's menu; choose `8` (Update),
      then exit; ezvps reports the version before and after (`Version is unchanged` if
      it was already the latest)
- [ ] `Uninstall`: `n` changes nothing; `y` backs up `/etc/backpack`, opens Backpack's
      menu; choose `9` (Uninstall) and confirm Backpack's own prompt; ezvps then prints
      `Verified: the backpack binary is gone.`, `command -v backpack` prints nothing
      and the backup is still in `/var/backups/ezvps/`. Leaving Backpack's menu with
      `10` instead makes ezvps say Backpack is still present

**8d. ctunnel**
- [ ] `Install` plan shows `https://github.com/alienrobotarmy/ctunnel.git`, the pinned
      commit and that upstream has no installer or release; with `git`, `make` or
      `gcc` missing it offers `apt-get install git make gcc libssl-dev zlib1g-dev`
      and installs nothing on `n`
- [ ] after `y`: `/usr/local/bin/ctunnel` and `/usr/local/share/man/man1/ctunnel.1`
      exist, `Version:` shows the `ctunnel 0.8 ...` line from `ctunnel -v`, nothing was
      started (`pgrep ctunnel` prints nothing)
- [ ] `Status`: installed, version, and the text that no service is documented (it
      never says running or stopped)
- [ ] create `~/.passkey` the way ctunnel does (run ctunnel once by hand with fake
      values) and `Update`: ezvps says there is **no documented update command**,
      offers a reinstall, backs up the binary and `~/.passkey` to
      `/var/backups/ezvps/ctunnel-*` (`cmp` against the originals), reinstalls and
      reports the version before and after; `~/.passkey` is untouched
- [ ] `Uninstall`: `n` changes nothing; `y` backs up, removes the binary and the man
      page, prints `Verified: the ctunnel binary is gone.`; `~/.passkey` and the
      backups remain

**8e. Lazyports**
- [ ] `Install` without Go prints that Go 1.24+ is needed and changes nothing; with Go
      1.24+ the plan shows the installer URL at the pinned commit, its SHA-256, the
      `go install ...@main` note (the built code is **not** pinned) and the shell-file
      note
- [ ] after `y`: `lazyports` exists in `/usr/local/bin` (and `~/go/bin`), `~/.bashrc`
      was backed up to `/var/backups/ezvps/lazyports-1-bashrc.*` before the installer
      appended its PATH line; ezvps prints only `To open Lazyports: run: lazyports`
      and `Version: not reported`; Lazyports itself did not start
- [ ] `Status`: installed, binary path(s), no version, no service
- [ ] `Update`: says there is no documented update command and offers a reinstall;
      `n` changes nothing; `y` backs up and reinstalls
- [ ] `Uninstall`: `y` removes `/usr/local/bin/lazyports` and `~/go/bin/lazyports`,
      verifies they are gone, leaves `~/.bashrc` (and its PATH line) alone

## 9. SSH and Users

Do this on a throwaway VPS **with a second terminal already logged in as root or a sudo
user**, so a mistake cannot lock you out. Use throwaway names (`testuser`, `testadmin`) and
a throwaway key pair made for this test (`ssh-keygen -t ed25519 -f /tmp/ezvps-test-key`);
never paste a real private key anywhere. Run it **once per supported release**.

**9a. Submenu and List users**
- [ ] `ezvps` -> `8` shows exactly `1) List users`, `2) Add user`, `3) Delete user`,
      `4) SSH settings`, `5) Add SSH key`, `0) Back`; `abc` prints `Invalid choice: abc`
- [ ] `List users`: `root` and your login accounts appear with UID and sudo (`yes`/`no`/`n/a`);
      `www-data`, `daemon`, `sshd`, `sync` do not; compare with
      `awk -F: '$7 !~ /(nologin|false)$/ {print $1, $3, $7}' /etc/passwd`; answering `y` to the
      full-list question shows the service accounts; no password hash anywhere in the output

**9b. Add user**
- [ ] `Add user` with `Bad Name`, `1abc`, `UPPER`, `a;b`, `../x`, an existing user such as
      `root` and an existing group name: each refused, `getent passwd` unchanged
- [ ] `testuser`, sudo `n`, create `y`, password `n`: `Created user: testuser (UID ...)`,
      `sudo : no`, `password : not set (password login is locked)`; `id testuser` shows no `sudo`
      group; `ls -ld /home/testuser` exists; `ls /var/backups/ezvps` has no new file
- [ ] `testadmin`, sudo `y`, password `y`: the **system's own** `New password:` prompt appears (ezvps
      prints nothing about the password); `id testadmin` lists `sudo`; `su - testadmin -c 'sudo -n true'`
      or `sudo -l -U testadmin` confirms sudo; the summary says `sudo : yes`
- [ ] on a Debian image without the `sudo` package: asking for sudo says the package is not
      installed and offers `apt-get install -y -q sudo`; `n` offers to create the user without sudo

**9c. Add SSH key**
- [ ] `Add SSH key` for `testuser` with the throwaway public key (`cat /tmp/ezvps-test-key.pub`): the
      key is typed without echo, only the type and comment are shown, `ls -ld ~testuser/.ssh` is
      `drwx------ testuser testuser` and `authorized_keys` is `-rw------- testuser testuser`
- [ ] the same key again: `already in ... Nothing to do`, no backup; a second, different key: appended,
      the old file is in `/var/backups/ezvps/authorized_keys-testuser.*` (`diff` against the original)
- [ ] paste the **private** throwaway key file (`cat /tmp/ezvps-test-key`, first line only is read):
      `looks like a PRIVATE key`, nothing written, the key text never printed back
- [ ] garbage text, `ssh-rsa notbase64`, a key with `command="..."` in front: refused, nothing written
- [ ] from a second terminal: `ssh -i /tmp/ezvps-test-key testuser@<server>` works
- [ ] replace `~testuser/.ssh` with a symlink to another directory: `Add SSH key` refuses and writes nothing
      through it (restore the directory afterwards)

**9d. SSH settings** (keep the second terminal open the whole time)
- [ ] the screen shows the effective Port, PermitRootLogin, PasswordAuthentication; compare with
      `sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication) '`
- [ ] `SSH port`: `abc`, `80`, `65536` and a port that `ss -ltn` shows in use are refused; `2222`: warnings
      (firewall, second terminal), `y`; a backup `/var/backups/ezvps/sshd_config.*` equals the previous file
      (`diff`); `sshd -T | grep ^port` and `ss -ltn` show only 2222; **a new connection on 2222 works**
      (allow the port in your firewall first); then change it back to `22`
- [ ] on Ubuntu 22.10+ (`systemctl is-active ssh.socket` is `active`): the port change also restarts
      `ssh.socket` and is verified; if sshd keeps the old port the module says so, restores the backup
      and names `ssh.socket`
- [ ] with a drop-in such as `/etc/ssh/sshd_config.d/50-cloud-init.conf` that has `PasswordAuthentication
      yes`: `PasswordAuthentication` -> `no` writes the line at the **top** of `sshd_config`, the effective
      value becomes `no` (`sshd -T`), and the drop-in is untouched
- [ ] `PasswordAuthentication` -> `no` on a server with no key installed: the stronger warning and the second
      question appear; `n` changes nothing. With a key: the warning to test a key login; after `y`,
      `ssh -o PreferredAuthentications=password testuser@<server>` is refused and the key login still works
- [ ] `PermitRootLogin` -> `no`: the lock-out warning; `ssh root@<server>` is refused afterwards, your open
      sessions stay alive; set it back to `prohibit-password`
- [ ] a deliberately broken config (`echo 'BROKEN_DIRECTIVE yes' >> /etc/ssh/sshd_config`): every setting
      refuses with the `sshd -t` error and changes nothing; remove the line afterwards
- [ ] repeat each change twice: the second run says it is already set, makes no backup and does not restart
      sshd; `grep -c 'ezvps:managed' /etc/ssh/sshd_config` shows one block per setting
- [ ] `sshd -t` still passes and `systemctl is-active ssh` is `active` at the end

**9e. Delete user**
- [ ] `root`, `toor` (a UID 0 account if you made one), the account you are logged in as (also after
      `sudo -i`/`su`), `www-data`, an unknown name: each refused, nothing changed
- [ ] `sudo -u testuser sleep 300 &` then `Delete user` -> `testuser`: refused with the PID list, **no
      override prompt**; after `pkill -u testuser` the delete is accepted
- [ ] `n` at the first confirmation changes nothing; `y` then `n` at the home question: `getent passwd
      testuser` is empty, `/home/testuser` still exists, `/var/backups/ezvps/users-passwd.*` and
      `users-group.*` exist
- [ ] a second throwaway user with `y` and `y`: the home directory is gone
- [ ] an account whose home is outside `/home` (for example `useradd -d /srv/x -m shared1`): the home
      question is not asked and the directory is kept

## 10. Firewall

Do this on a throwaway VPS **with console access** (the provider's web console), because a wrong firewall
change can lock you out of SSH. Keep a second SSH session open throughout. Which backend runs depends on
what is installed; repeat the checklist for each backend you can set up (ufw, firewalld, nftables, iptables),
and never install one just to test unless you mean to.

**10a. Detection and the menu**
- [ ] `ezvps` -> `9` shows exactly `1) Show firewall status`, `2) List rules`, `3) Allow port`,
      `4) Remove rule`, `0) Back`, and the line `Backend: <name>`
- [ ] the backend named is the first present of `ufw`, `firewalld`, `nftables`, `iptables`
      (`command -v ufw firewall-cmd nft iptables`); e.g. with ufw installed it is ufw even if `nft` exists
- [ ] on an image with none of the four commands: `No firewall backend found (looked for, in this order: ...)`
      and `Nothing was changed.`, back at the main menu, no submenu; `ezvps firewall` does the same, exit 0
- [ ] an unsupported system file (`EZVPS_OS_RELEASE` is test-only; on a real server just confirm Allow port /
      Remove rule print the supported-systems message on an unlisted release) changes nothing, while
      Show firewall status and List rules still work

**10b. Show firewall status and List rules (read-only)**
- [ ] status matches the backend: `ufw status verbose` (Status line and `Default:` line), `firewall-cmd
      --state` and the default zone, `nft list ruleset` (input chain `policy`), `iptables -S INPUT` (`-P INPUT`)
- [ ] a disabled ufw (`ufw disable`, then re-enable it afterwards with your own command) is reported as
      `disabled`; a stopped firewalld is `disabled` with `not running`
- [ ] List rules shows the same rules, in the same order, as the backend's own listing
      (`ufw status numbered`, `firewall-cmd --list-all`, `nft -a list ruleset`, `iptables -S INPUT`), with the
      right ID (ufw/iptables number, nftables handle), action, protocol, port or service and source
- [ ] running List rules several times changes nothing (`ufw status numbered` / `nft list ruleset` /
      `iptables-save` before and after are identical)

**10c. Allow port**
- [ ] invalid ports `0`, `65536`, `080`, `8x`, `-1`, `80:90`, `80,443`, empty; invalid protocols `icmp`,
      `both`, empty: each refused, nothing changes
- [ ] `8080` / `tcp` on a free port: the exact command is shown, one confirmation, the rule appears in the
      backend's own listing (and the re-read list shown by ezvps), a copy of the previous listing exists in
      `/var/backups/ezvps/firewall-<backend>.*` (mode 600); `n` at the confirmation changes nothing
- [ ] from a second machine, the port is reachable once a service listens on it (`nc -l 8080` on the server,
      `nc -vz <server> 8080` from outside)
- [ ] the same port again: refused as already allowed, no second rule
- [ ] a port already allowed through a range or a service/profile (for example `443` when `Nginx Full` or the
      firewalld `https` service is on) is refused
- [ ] a port something already listens on (for example `ss -ltn` shows 80 with nginx running): the warning names
      the process and address, and one yes still adds the rule
- [ ] ufw: both the IPv4 and IPv6 rows appear; firewalld: the rule is in the default zone, both in
      `firewall-cmd --list-ports` and `firewall-cmd --permanent --list-ports`
- [ ] nftables / iptables: the rule is first in the input chain, and the note says it is lost at reboot
      unless you save the ruleset yourself

**10d. Remove rule**
- [ ] the list is shown first; an unknown ID, `abc`, `all`, empty: nothing is removed
- [ ] removing the `8080/tcp` rule from 10c: asked once, only that rule disappears (compare the listing before
      and after), the firewall stays enabled, the other rules are untouched, the re-read list is shown
- [ ] `n` at the confirmation removes nothing
- [ ] removing the rule that allows **SSH** (port 22, or your `Port`): the `WARNING: rule N allows SSH ...`
      with the lock-out text, then a **second** question; `n` there removes nothing; only test `y` from a
      session you can recover with the provider's console
- [ ] over SSH on a non-default port: the rule for the port you are connected on is protected even if
      `sshd -T` is not readable (`SSH_CONNECTION` is used)
- [ ] a source-only allow (for example from one address with no port) or an established-connections rule
      (nftables/iptables) gets the "no port or protocol restriction" SSH warning
- [ ] there is no way to remove several rules in one run and no `disable`/`reset`/`flush` anywhere in the
      backend's own history (`journalctl`, `ufw status` still `active`)

## 11. Non-root

- [ ] as a normal user: `ezvps` prints `ezvps must be run as root.`, exit 1
- [ ] as a normal user: `ezvps --version` still works

## 12. Cleanup (no uninstall module yet)

```bash
x-ui uninstall            # 3x-ui's own uninstaller, if you installed it
# Backpack / ctunnel / Lazyports: use each submenu's Uninstall (section 8)
apt-get purge -y nginx    # if you installed nginx for this test
rm -f /usr/local/bin/ezvps
rm -rf /var/backups/ezvps /var/lib/ezvps
rm -rf /root/.acme.sh /etc/ssl/ezvps   # if you installed acme.sh / issued certificates
userdel testuser; userdel testadmin    # the throwaway accounts from section 9 (add -r to drop their homes)
# Firewall (section 10): remove the test rules you added (ezvps Remove rule, or the backend's own command)
rm -f /tmp/ezvps-test-key /tmp/ezvps-test-key.pub
```

- [ ] ezl2tp (if present) still works after cleanup

Destroy the VPS when finished.
