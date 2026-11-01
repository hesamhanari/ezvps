# ezvps

A bash TUI/CLI VPS manager for **Debian 13**, run as **root**. One script, no
extra dependencies.

> **Status: v0.0.1 in development.** Only **L2TP** works so far. The other
> menu items print "not implemented yet" and return to the menu. They arrive
> in later releases, one module per PR. See [SPEC.md](SPEC.md).

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

## Principles

Check before installing. Back up before overwriting. Idempotent re-runs. No
hardcoded secrets. No real IPs, secrets or usernames in this repo (tests use
fake data only).

## Development

```bash
bash tests/lint.sh          # bash -n + shellcheck + hygiene scan
bash tests/smoke-test.sh    # menu, L2TP stub, not-yet-implemented paths, installer
```

`tests/fresh-vps-test.md` is the manual checklist for a throwaway Debian 13
VPS. Contributor and agent rules are in [AGENTS.md](AGENTS.md).
