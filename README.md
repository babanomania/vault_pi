# vault_pi

> Your passwords. Your hardware. Your iPhone. No subscription, no cloud middleman, no compromises — and yes, the **official Bitwarden iOS app actually works**.

A one-command Ansible playbook that turns a $30 Raspberry Pi into a personal Bitwarden-compatible password vault. Set it up in a Sunday afternoon. Run it for years.

---

## Why self-host?

Password managers are the most sensitive software in your digital life. Cloud providers — even the good ones — eventually:

- Raise prices when you're locked in
- Get acquired by someone you didn't sign up with
- Suffer breaches (every major one has, at this point)
- Read your data when subpoenaed
- Lose your data when their startup folds

Self-hosting flips the equation. You run the same Bitwarden ecosystem you already know — same iOS / Android / browser / desktop apps — against a server in your own house. The only person with root on your vault is you.

This playbook does that, end-to-end, on a Raspberry Pi.

## What you get

- **Vaultwarden** (a fast, lightweight Bitwarden-compatible server in Rust) running in Docker
- **Nginx** in front of it, terminating TLS with a real Let's Encrypt certificate
- **Tailscale** giving your Pi a stable, encrypted address reachable from anywhere — your home, a coffee shop, the airport
- **Auto-updates** for the OS and the container images
- **Optional**: encrypted weekly backups to Dropbox via borg + rclone, with Telegram notifications
- **Optional**: an e-ink display on the Pi showing uptime

Compatible with: Bitwarden iOS, Android, browser extensions, desktop apps, CLI. Same vaults, same Sends, same organisations — just a different server URL.

## What it costs

| Item | One-time | Recurring |
|---|---|---|
| Raspberry Pi Zero 2W (or any Pi) | ~$15-30 | — |
| MicroSD card 32 GB | ~$8 | — |
| Power supply | ~$8 | — |
| Tailscale account | $0 | $0 (free tier covers 3 users, 100 devices) |
| Domain name | $0 | $0 (you use a `*.ts.net` subdomain) |
| Your time | a Sunday | ~10 min/year |

Total: **~$45 once, ~$0/year**. The Pi will outlast multiple Bitwarden subscription renewals.

## The iOS catch most guides ignore

Almost every "self-hosted Vaultwarden" guide on the internet tells you to install a self-signed certificate on your iPhone. They forget to mention: **the official Bitwarden iOS app will reject that cert anyway.**

Apple's URLSession (which security-sensitive apps like Bitwarden use) deliberately ignores user-installed CA roots, no matter how many trust toggles you flip. You'll spend hours setting it up only to get `errSSLNoRootCert` when you try to log in.

This playbook routes around the problem by giving your Pi a real publicly-trusted Let's Encrypt certificate via Tailscale. The iOS app sees a normal CA chain and just works. No profiles to install. No trust toggles. No hacks.

## What you need

Before you start, make sure you have:

- A Raspberry Pi (any model, 32-bit or 64-bit). Pi Zero 2W works fine for personal use.
- A microSD card, flashed with **Raspberry Pi OS (64-bit, Lite is fine, Trixie or later)**. Use Raspberry Pi Imager — it lets you preconfigure SSH, WiFi, and your username during the flash.
- A computer running macOS or Linux with [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) installed (`brew install ansible` or `apt install ansible`).
- A free [Tailscale](https://login.tailscale.com) account.
- Your Pi reachable over SSH with your key (`ssh pi@<pi-ip>` should work without a password).

## Setup, step by step

### 1. Clone this repo and copy the config templates

```bash
git clone https://github.com/babanomania/vault_pi.git
cd vault_pi
ansible-galaxy collection install -r requirements.yml
cp example.config.yml config.yml
cp example.inventory.ini inventory.ini
```

### 2. Set up Tailscale (5 minutes)

1. Sign up at [login.tailscale.com](https://login.tailscale.com) if you haven't already.
2. Go to [Admin → DNS](https://login.tailscale.com/admin/dns). Enable **MagicDNS** and **HTTPS Certificates**. (The HTTPS toggle is the one that matters — without it, your Pi can't get a real cert.)
3. Note your tailnet name — it's in the URL bar of the admin console, something like `tailnet-1234.ts.net`.
4. Go to [Admin → Keys](https://login.tailscale.com/admin/settings/keys). Click **Generate auth key**. Settings:
   - Reusable: **off**
   - Ephemeral: **off**
   - Expiration: 24 hours (we'll only use it once)
5. Copy the key (`tskey-auth-…`) — you'll paste it into `config.yml` next.

### 3. Edit `config.yml`

The defaults are sensible. The fields you must set:

```yaml
vaultwarden_fqdn: vaultwarden.tailnet-XXXX.ts.net    # use YOUR tailnet name
tailscale_authkey: "tskey-auth-..."                  # paste from step 2
vaultwarden_signups_allowed: "true"                  # leave true for first run, close after
system_timezone: Asia/Kolkata                        # or your timezone
pi_custom_password: <hashed>                         # see comment in the file
```

Edit `inventory.ini` to point at your Pi's IP:

```ini
[vault_pi]
192.168.1.50 ansible_user=pi
```

### 4. Run the playbook

```bash
ansible-playbook main.yml
```

On a Pi Zero 2W this takes 20-30 minutes — most of it is Docker pulling images. Walk away, come back to a working server.

### 5. Install Tailscale on your iPhone

1. App Store → Tailscale → install.
2. Open the app, sign in with the same account, toggle the VPN on.
3. iOS will ask permission to add a VPN configuration — allow.

### 6. Install the official Bitwarden iOS app

1. App Store → Bitwarden Password Manager → install.
2. Open it. On the login screen, tap **Logging in on:** at the top, choose **Self-hosted**.
3. Server URL: `https://vaultwarden.tailnet-XXXX.ts.net` (use yours).
4. **Create account** with your email and a strong master password.

That's it. You're using a self-hosted password manager from the official Bitwarden app.

### 7. Close signups (important)

After you've created your account, edit `config.yml`:

```yaml
vaultwarden_signups_allowed: "false"
```

Re-run `ansible-playbook main.yml`. Now nobody else on your tailnet can create an account on your server.

## Day-2 operations

### Browser, desktop, other devices

The same server URL works from any Bitwarden client — browser extensions, desktop apps, Android, CLI. All of them need to be on your tailnet (so you join those devices to Tailscale too) and point at the same `https://vaultwarden.tailnet-XXXX.ts.net`.

### Updating

```bash
ansible-playbook main.yml
```

Idempotent. Re-run any time. Watchtower also auto-updates your container images daily at 04:00 local time, but pinning the Vaultwarden version in `config.yml` keeps you in control of breaking changes.

### Backups

To enable encrypted weekly backups to Dropbox:

1. Set `ensure_backup: True` in `config.yml`.
2. Generate an [rclone Dropbox token](https://rclone.org/dropbox/) and paste into `rclone_token`.
3. (Optional) Create a Telegram bot and set `telegram_token` + `telegram_chatid` for completion notifications.
4. Re-run the playbook.

Backups run weekly via cron, encrypted with `borg_pass`. To restore, set `borg_restore: True` and re-run. (Or restore manually — `borg list` + `borg extract` on the Pi.)

### Certificate renewal

Tailscale's Let's Encrypt cert is valid for 90 days. The playbook installs a weekly cron job that refreshes it automatically. You won't need to think about it.

### Health check

```bash
ssh pi@<pi> 'docker ps'
```

You should see `nginx`, `vaultwarden`, and `watchtower` all up. If anything's restarting, `docker logs <name>` to see why.

### Switching servers

To move to a different Pi: flash a new SD card, copy your existing `config.yml`, generate a fresh Tailscale auth key, then `ansible-playbook main.yml`. To migrate the actual vault data, snapshot `~/containers/vw-data/` from the old Pi and drop it on the new one before the playbook runs (or use a borg backup).

## What this doesn't do

- **Doesn't expose your Pi to the public internet.** Access is via Tailscale only. This is the right call for a personal vault — there's no scenario where you need random strangers to be able to reach your password server.
- **Doesn't provide breach notifications for your saved passwords.** The web vault has this feature but it pings Bitwarden's API; you'd need to wire up your own. Open browser feature, not a server one.
- **Doesn't ship `ADMIN_TOKEN` configured.** The `/admin` panel is disabled by default. To enable it, generate an argon2 hash (`docker run --rm vaultwarden/server hash --preset=owasp5`) and set `vaultwarden_admin_token` in `config.yml`. Leaving it unset is the safer default.

## Troubleshooting

**"The certificate for this server is invalid"** on the iOS app — you're using `tls_provider: self_signed`. Switch to `tls_provider: tailscale` and re-run.

**"This is not a recognised Bitwarden server"** — usually one of two things:
1. You upgraded `vaultwarden_version` and the upstream JSON shape shifted. Roll back the pin.
2. The iOS app cached an old response. Force-quit and reopen.

**`apt update` hangs forever during playbook** — Pi OS Desktop's `packagekit` is racing for the dpkg lock. The playbook now masks it automatically, but if you flashed Pi OS Desktop before this fix, `sudo systemctl mask packagekit` once and re-run.

**Bitwarden app says "hostname not found"** — Tailscale isn't connected on the iPhone, or there's a typo in the server URL. Open the Tailscale app, ensure the toggle is ON, verify you can `https://<fqdn>` from Safari first.

## Acknowledgements

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden) by dani-garcia — the Rust Bitwarden-compatible server that makes this practical on a Pi.
- [Tailscale](https://tailscale.com) — for solving the "reachable from anywhere with a real TLS cert" problem so we don't have to.
- Original [babanomania/vault_pi](https://github.com/babanomania/vault_pi) skeleton — the security hardening + backup design.

## Contributing

If you hit something this playbook didn't handle cleanly on your hardware, open an issue. If you're an AI agent working on this codebase, read `AGENTS.md` first — there are several non-obvious constraints documented there.
