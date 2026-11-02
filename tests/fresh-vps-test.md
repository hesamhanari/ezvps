# Fresh VPS test (manual)

Run on a **throwaway Debian 13 VPS**, as root, before merging changes that
touch the installer or a module. Use fake data only; do not paste real IPs,
tokens or usernames into notes or issues. Placeholders: `<owner>`,
`192.0.2.10`, `example.com`, `testuser`.

Tick each box; note failures with the exact output.

## 0. Prerequisites

- [ ] `cat /etc/os-release` shows Debian 13
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
- [ ] each of `3`, `4` and `6` to `12` prints `<Label> is not implemented yet.`
      and returns to the menu after Enter (`2` opens the 3x-ui submenu, section 5;
      `5` opens the Nginx submenu, section 6)
- [ ] `abc`, `13`, empty input -> `Invalid choice`, menu continues
- [ ] `ezvps backpack` (and the other pending keys) print the same message, exit 0
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
- [ ] on a non-Debian-13 host the install options refuse and change nothing
      (optional; only on a second throwaway VPS)
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

Needs outbound HTTPS to the Debian mirrors (apt). Start from an image where
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

**6b. Install**

- [ ] `1) Install Nginx` -> `y`: apt installs the `nginx` package;
      `systemctl is-enabled nginx` is `enabled`, `systemctl is-active nginx` is `active`
- [ ] output shows `Config test passes.` and `Verified: nginx answers on
      127.0.0.1:80 (HTTP 200)`, then the HTTP-only / Certificates note
- [ ] `curl -sI http://127.0.0.1/` shows the default Debian welcome page headers
- [ ] running `1) Install Nginx` again says `already installed ... Not
      reinstalling`, shows the status, and `apt` is not run (check
      `grep nginx /var/log/apt/history.log` shows a single install)

**6c. Status and Restart**

- [ ] `2) Status`: version, `nginx - running (boot: enabled)`, `Config test:
      passes`, `Responds: yes (HTTP 200 ...)`
- [ ] `3) Restart`: prints `Config test passes. Restarting nginx...` and
      `Verified`; `systemctl status nginx` shows a fresh start time
- [ ] break the config on purpose (`echo 'BROKEN_DIRECTIVE on;' >>
      /etc/nginx/sites-available/default`), then: `2) Status` shows `Config
      test: FAILS` with nginx's error; `3) Restart` says `nginx was NOT
      restarted or reloaded` and the nginx process id / start time is
      unchanged (`systemctl show -p MainPID,ActiveEnterTimestamp nginx`)
- [ ] remove the broken line again; `3) Restart` works

**6d. Add site**

- [ ] start the backend: `python3 -m http.server 3000 --bind 127.0.0.1 &`
- [ ] `5) Add site` with `Example.COM` and `127.0.0.1:3000`:
      `/etc/nginx/sites-available/example.com` exists with the `# Managed by
      ezvps` header and `# ezvps:domain=` / `# ezvps:upstream=` lines;
      `/etc/nginx/sites-enabled/example.com` is a symlink to it; output says
      `Config test passes.` and `nginx reloaded.`; no `ssl` or `443` anywhere in the file
- [ ] `curl -s -H 'Host: example.com' http://127.0.0.1/` returns the backend's
      directory listing (reverse proxy works); with the backend stopped it returns 502
- [ ] the message says the site is HTTP only and to use the Certificates
      module once it exists; no certificate was created (`ls /etc/letsencrypt` fails / empty)
- [ ] the same `5) Add site` again: `already exists with the same upstream ...
      Nothing to do`; no new file, no backup, no second reload (journal)
- [ ] `5) Add site` `example.com` with `127.0.0.1:4000`: asks before
      overwriting; `n` changes nothing; `y` backs up the old file to
      `/var/backups/ezvps/nginx-site-example.com.<timestamp>.<pid>` (contains
      the old upstream) and updates the site
- [ ] invalid input is rejected without changes: domain `localhost`, `bad_name.com`,
      `a b.com`; upstream `127.0.0.1` (no port), `127.0.0.1:99999`, `https://127.0.0.1:443`
- [ ] domain already served by a hand-made enabled file (create
      `/etc/nginx/sites-available/legacy` with `server_name taken.example.com;`
      and enable it): adding `taken.example.com` is refused
- [ ] failing test is rolled back: add a hand-made file with
      `BROKEN_DIRECTIVE on;` to `/etc/nginx/conf.d/zz.conf`, then `Add site`
      `new.example.com`: `config test FAILED`, `Rolled back`, no
      `sites-available/new.example.com`, nginx not reloaded; remove `zz.conf`
- [ ] `systemctl stop nginx`, `Add site` `idle.example.com`: file written,
      `nginx is not running, so nothing was reloaded`; `systemctl start nginx`

**6e. List and Remove**

- [ ] `4) List sites`: table with `example.com  example.com  127.0.0.1:4000
      ezvps`, `default ... not ezvps`, `legacy taken.example.com ... not ezvps`;
      `Available but not enabled:` lists any disabled site files
- [ ] `6) Remove site` with an unknown domain: `No site named ...`, nothing changed
- [ ] `6) Remove site` `example.com`, answer `n`: files remain, no backup
- [ ] `6) Remove site` `example.com`, answer `y`: backup
      `nginx-site-example.com.<timestamp>.<pid>` exists and matches the old
      file, both the file and symlink are gone, `Config test passes.`,
      `nginx reloaded.`, other sites untouched
- [ ] `6) Remove site` on the hand-made `legacy`-style domain warns `NOT
      created by ezvps` before asking
- [ ] clean up: remove `legacy`, `idle.example.com` and the other test sites, stop the backend

## 7. Non-root

- [ ] as a normal user: `ezvps` prints `ezvps must be run as root.`, exit 1
- [ ] as a normal user: `ezvps --version` still works

## 8. Cleanup (no uninstall module yet)

```bash
x-ui uninstall            # 3x-ui's own uninstaller, if you installed it
apt-get purge -y nginx    # if you installed nginx for this test
rm -f /usr/local/bin/ezvps
rm -rf /var/backups/ezvps /var/lib/ezvps
```

- [ ] ezl2tp (if present) still works after cleanup

Destroy the VPS when finished.
