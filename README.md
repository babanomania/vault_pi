# vault_pi

Your password manager knows your bank logins, the email you use only for divorce attorneys, the WiFi password from that one Airbnb in 2019, and which streaming service you're sharing with a cousin you no longer speak to. It is, by a comfortable margin, the most sensitive piece of software you'll ever run.

So naturally, you pay a stranger in a building you've never visited an annual fee to look after it. They store it on hardware they don't own, in a country whose laws you might not have read, accessed by employees you can't name. When they get breached — and they will — you'll get a friendly email about how your security is their top priority.

There is a better way. Same Bitwarden iOS app, same Android app, same browser extensions, same vaults. Different server: a $30 Raspberry Pi under your TV, run by the only person who really cares about your passwords (you). This playbook gets you there in a Sunday afternoon.

---

A one-command Ansible playbook that turns a Raspberry Pi into a personal, self-hosted, Bitwarden-compatible password vault — fully working with the official iOS and Android apps, encrypted backups, and zero exposure to the public internet.

## What you get

- **Vaultwarden** — a lightweight Bitwarden-compatible server in Rust, running in Docker. Works with every official Bitwarden client (iOS, Android, browser extensions, desktop, CLI).
- **The official mobile apps actually log in** — because we get a real Let's Encrypt cert via Tailscale, not a self-signed one. Both iOS and Android's official apps refuse user-installed CA roots; this is the playbook that solves it.
- **Tailscale-only access** — your Pi is never exposed to the public internet. Reachable from your home, a coffee shop, the airport — anywhere you're on your tailnet. No port forwarding. No dynamic DNS.
- **Encrypted weekly backups to the cloud of your choice** — borg-encrypted snapshots of your vault to a Docker volume, then rclone-synced to **any of [rclone's 70+ supported backends](https://rclone.org/overview/)**: Dropbox, Google Drive, OneDrive, Backblaze B2, AWS S3 (and any S3-compatible service like MinIO, Wasabi, Cloudflare R2), SFTP to your own NAS, WebDAV to a Nextcloud, even a literal USB drive. Deduplication and compression mean a 50-vault history typically fits in ~5 MB.
- **Telegram notifications** — get a ping on every backup + sync, success or failure. Optional; degrades gracefully if you don't set it up.
- **Hardened OS** — SSH key-only (passwords disabled), root SSH denied, UFW default-deny incoming with explicit allow rules, fail2ban for SSH, 1 GB swap (Pi Zero 2W has 512 MB RAM and OOMs without it), `packagekit` masked (it races apt and tanks the SD card).
- **Auto-updates** — unattended-upgrades for the OS, Watchtower for container images. Daily, at 4 AM.
- **Docker secrets for every credential** — borg passphrase, Dropbox token, Telegram credentials, the optional admin token — all mounted as `/run/secrets/<name>` in the consuming containers. Never appear in `docker inspect`, env vars, or any host file outside `/etc/vault_pi_secrets/`.
- **Reproducible** — clone the repo, fill in `config.yml`, `ansible-playbook main.yml`. Land the same configuration on a new Pi in 25 minutes.
- **Optional e-ink status badge** — slot a Waveshare e-paper HAT onto the Pi's GPIO header and the playbook wires it up to display the Bitwarden logo and your vault's uptime, refreshing every hour. Pure homelab vanity. Costs $20. Draws ~0 amps at idle (e-ink keeps its last image with no power). Completely unnecessary, highly recommended.

## What it costs

| Item | One-time | Recurring |
|---|---|---|
| Raspberry Pi (any model; Zero 2W works fine) | $15–30 | — |
| 32 GB microSD card | $8 | — |
| Power supply | $8 | — |
| Tailscale account (free tier: 3 users, 100 devices) | $0 | $0 |
| Dropbox account (free tier: 2 GB; vault < 5 MB) | $0 | $0 |
| Domain name | $0 | $0 (use `*.ts.net` subdomain) |
| Your time | a Sunday | ~10 min/year |
| **Total** | **~$45** | **$0** |

Compare to Bitwarden Premium ($10/year per user) or LastPass Premium ($36/year). The Pi pays for itself somewhere between year one and year four, depending on which provider you're escaping.

## What you need

- A Raspberry Pi running **Raspberry Pi OS (64-bit, Lite is fine, Trixie or later)**. Flash with Raspberry Pi Imager — set username, SSH key, and WiFi credentials during the flash, not after.
- A computer running **macOS or Linux** with [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) installed (`brew install ansible` on Mac, `apt install ansible` on Debian/Ubuntu).
- SSH access to the Pi using your key (`ssh pi@<pi-ip>` should work with no password prompt).
- A free [Tailscale](https://login.tailscale.com) account.
- A free [Dropbox](https://www.dropbox.com) account (or any rclone-supported cloud — Google Drive, S3, Backblaze B2, etc.).
- *(Optional)* A Telegram account, for completion notifications.

## Setup

### 1. Clone and copy config templates

```bash
git clone https://github.com/babanomania/vault_pi.git
cd vault_pi
ansible-galaxy collection install -r requirements.yml
cp example.config.yml config.yml
cp example.inventory.ini inventory.ini
```

### 2. Configure Tailscale (5 minutes, one-time)

1. Sign up at [login.tailscale.com](https://login.tailscale.com).
2. Go to [Admin → DNS](https://login.tailscale.com/admin/dns). Enable **MagicDNS** and **HTTPS Certificates**. The HTTPS toggle is the critical one — without it, your Pi can't get a real cert.
3. Note your tailnet name from the admin URL (e.g. `tailnet-1234.ts.net`).
4. Generate a one-time auth key at [Admin → Keys](https://login.tailscale.com/admin/settings/keys). Settings: **Reusable: off**, **Ephemeral: off**, expiration **24 hours** (we'll only use it once). Copy the `tskey-auth-...` value.

### 3. Set up rclone for your cloud (3 minutes, one-time)

Pick any backend rclone supports — Dropbox, Google Drive, Backblaze B2, S3 (or any S3-compatible service: AWS, Wasabi, MinIO, Cloudflare R2), SFTP to a NAS you own, WebDAV to a Nextcloud, a USB drive. Anything that lets you put bytes somewhere not your Pi. The walkthrough below uses **Dropbox** because it's free, fast to set up, and the OAuth flow is the smoothest of the bunch — but the only thing that changes for other backends is the prompts inside `rclone config`.

On any computer (you'll uninstall it after):

```bash
brew install rclone   # or apt install rclone, or download from rclone.org
rclone config
```

Walk through the prompts: **n** (new remote) → name **`remote`** (this exact name — it's referenced in the playbook) → storage: pick your backend (`dropbox`, `b2`, `s3`, `sftp`, `webdav`, etc.) → fill in backend-specific credentials → **y** for auto config when prompted (opens browser if OAuth) → **y** to keep → **q** to quit.

Now extract the relevant section of the config:

```bash
cat ~/.config/rclone/rclone.conf
```

You'll get something like:

```ini
[remote]
type = dropbox
token = {"access_token":"...","refresh_token":"..."}
```

…or for a non-OAuth backend:

```ini
[remote]
type = b2
account = your-key-id
key = your-application-key
```

Both shapes work. We'll feed the contents into `config.yml` in the next step.

Once everything is on the Pi (after step 5), you can uninstall rclone and delete `~/.config/rclone/` to remove the local copy — the Pi has its own, mounted as a Docker secret.

### 4. Edit `config.yml`

Fill in the fields that don't have sensible defaults:

```yaml
vaultwarden_fqdn: vaultwarden.tailnet-XXXX.ts.net    # YOUR tailnet
tailscale_authkey: "tskey-auth-..."                  # from step 2
vaultwarden_signups_allowed: "true"                  # close after creating your account
system_timezone: Asia/Kolkata                        # or your timezone
borg_pass: "<a strong passphrase you'll never lose>"

# Paste the entire [remote] block from your rclone.conf (step 3) here.
# Works for any backend rclone supports.
rclone_config: |
  [remote]
  type = dropbox
  token = {"access_token":"...","refresh_token":"..."}

# Where on that remote to put the encrypted backup repo.
sync_remote_path: vaultwarden_backups

# Optional:
telegram_chatid: 1234567890                          # blank to disable
telegram_token: "1111:AAA..."                        # blank to disable
```

Examples of `rclone_config` for non-OAuth backends:

```yaml
# Backblaze B2 (cheap object storage, ~$0.005/GB/month)
rclone_config: |
  [remote]
  type = b2
  account = your-key-id
  key = your-application-key

# AWS S3 / S3-compatible (Wasabi, MinIO, Cloudflare R2)
rclone_config: |
  [remote]
  type = s3
  provider = AWS
  access_key_id = AKIA...
  secret_access_key = ...
  region = us-east-1
  endpoint =

# SFTP to a NAS you own
rclone_config: |
  [remote]
  type = sftp
  host = nas.lan
  user = backup
  key_file = /run/secrets/rclone_sftp_key

# Nextcloud / ownCloud via WebDAV
rclone_config: |
  [remote]
  type = webdav
  url = https://nextcloud.example.com/remote.php/dav/files/you/
  vendor = nextcloud
  user = you
  pass = <obscured password — generate via `rclone obscure '<plaintext>'`>
```

Edit `inventory.ini` to point at your Pi:

```ini
[vault_pi]
192.168.1.50 ansible_user=pi
```

### 5. Run the playbook

```bash
ansible-playbook main.yml
```

On a Pi Zero 2W this takes 20–30 minutes — most of it is Docker pulling images. Walk away, come back to a working server.

### 6. Install Tailscale on your phone

- **iPhone**: App Store → Tailscale → install → sign in with your account → enable VPN.
- **Android**: Play Store → Tailscale → install → sign in → enable VPN.

### 7. Install the Bitwarden app

- **iPhone**: App Store → "Bitwarden Password Manager" → install. On the login screen, tap **"Logging in on:"** → choose **Self-hosted** → enter `https://vaultwarden.tailnet-XXXX.ts.net`.
- **Android**: Play Store → "Bitwarden Password Manager" → install. Same flow — tap **"Logging in on:"** → **Self-hosted** → enter your URL.

Create your account with a strong master password. You're now using a self-hosted password manager from the official Bitwarden app.

### 8. Close signups

After your account is created, edit `config.yml`:

```yaml
vaultwarden_signups_allowed: "false"
```

Re-run `ansible-playbook main.yml`. Nobody else on your tailnet can register accounts now.

---

## Features in detail

Every feature below describes what the playbook does for you automatically vs. what you need to put into `config.yml`.

### Vaultwarden core

The actual password server. Bitwarden-compatible API, runs as a Docker container behind nginx.

**Automatic:**
- Pulls and pins a tested version (`vaultwarden_version: "1.36.0"` by default — bump deliberately).
- Sets `DOMAIN`, `ROCKET_PORT`, `WEBSOCKET_PORT`, `WEBSOCKET_ENABLED`, `TZ` env vars.
- Healthchecks every 30 seconds, restarts on failure.
- Mounts `vw-data/` as the persistent volume for the SQLite DB, attachments, sends, and JWT keys.

**You configure:**
- `vaultwarden_fqdn` — the public tailnet hostname clients hit.
- `vaultwarden_signups_allowed` — `"true"` long enough to make your account, then `"false"`.
- `system_timezone` — affects scheduled jobs, log timestamps, and password-change reminders.

### TLS via Tailscale

The technically interesting part — and the reason most "self-hosted Bitwarden" guides leave you with a broken iOS/Android app.

**Why this matters:** the official Bitwarden mobile apps (both iOS and Android) use OS-level networking libraries (Apple's URLSession on iOS, Android's NetworkSecurityConfig system) that, by default, **only trust certificate authorities in the OS root store**. Even when you install a custom CA on your phone and toggle every trust setting, security-sensitive apps like Bitwarden intentionally ignore those user CAs as a hardening measure.

- On iOS the error is `errSSLNoRootCert` (NSURLErrorDomain code `-1202`): *"The certificate for this server is invalid."*
- On Android the app simply refuses to validate the chain and returns a generic SSL error.

The fix is the same on both platforms: get a certificate from a CA that's already in the system trust store. Tailscale's `*.ts.net` hostnames are eligible for Let's Encrypt certs via `tailscale cert`, which both iOS and Android trust natively. No profiles to install on your phone. No trust toggles. No drama.

**Automatic:**
- Installs Tailscale on the Pi via the official apt repo (using modern `signed-by=` keyring, not the deprecated `apt-key`).
- Joins the Pi to your tailnet using your one-time auth key.
- Verifies the resulting tailnet FQDN matches `vaultwarden_fqdn`.
- Fetches a Let's Encrypt cert via `tailscale cert` and places it where nginx can read it.
- Installs a weekly cron job (`/etc/cron.d/vaultwarden-tailscale-cert`, Mondays at 04:00) to renew the cert. LE certs are 90 days; the renewal job is idempotent and only re-fetches when within the renewal window.
- Configures nginx with TLS 1.2/1.3 only, modern cipher suites, HSTS, and the `sub_filter` workaround for the Bitwarden mobile clients' server-name validation.

**You configure:**
- `tls_provider: tailscale` (default; the alternative `self_signed` is documented but doesn't work with mobile apps).
- `tailscale_authkey` — one-time use, paste from the Tailscale admin console.
- `vaultwarden_fqdn` — must match the FQDN Tailscale assigns (`<tailscale_hostname>.<your-tailnet>.ts.net`).
- `tailscale_hostname` — what name to register in the tailnet (default: `vaultwarden`).

### Encrypted backups + offsite sync

A dedicated backup-runner container that captures consistent snapshots of `vw-data` and ships them to your cloud of choice, with credentials managed as Docker secrets.

**You're not locked into Dropbox.** The `rclone_config` field in `config.yml` accepts the entire `[remote]` block from any rclone backend — Dropbox, Google Drive, OneDrive, Backblaze B2, AWS S3, S3-compatible services (Wasabi, MinIO, Cloudflare R2), SFTP to a NAS you own, WebDAV to a Nextcloud, even local filesystem if you bind-mount an external drive. Borg encrypts everything client-side before rclone touches it, so even providers you wouldn't normally trust with sensitive data see only encrypted chunks. See the [rclone supported backends list](https://rclone.org/overview/) for the full menu.

**Automatic:**
- Builds the `backup-runner` Docker image on the Pi (Alpine + borg + rclone + sqlite + curl + bash + tini).
- Provisions a named Docker volume (`borg_repo`) for the local borg repository.
- Installs `/etc/cron.d/vault_pi_backup`:
  - **Saturday 23:00** — `docker compose run --rm backup-runner backup`
    - Takes a consistent SQLite snapshot via the online `.backup` API (no need to stop vaultwarden)
    - Creates a new borg archive with zstd,3 compression
    - Prunes per the 7-daily / 4-weekly / 3-monthly retention policy
    - Compacts the repo to reclaim freed space
  - **Sunday 23:00** — `docker compose run --rm backup-runner sync`
    - rclone-syncs the local borg repo to your configured cloud remote
    - Uses bandwidth limits tuned for Pi Zero 2W (8 MiB/s default)
- Sends a Telegram notification on each completion (if configured).
- Logs everything to `/var/log/vault_pi_backup.log` with weekly rotation × 8.
- All credentials (borg passphrase, rclone config, Telegram token, chat ID) live in `/etc/vault_pi_secrets/` at `0600 root:root`, mounted into the container as `/run/secrets/<name>`. Never appear in env vars or `docker inspect`.

**You configure:**
- `ensure_backup: True` — gates the whole feature.
- `borg_pass` — borg encryption passphrase. **Save this somewhere safe.** Losing it makes your backups permanently undecryptable.
- `rclone_config` — multi-line YAML block, contents pasted from `rclone config` (any backend). The remote inside must be named `[remote]`.
- `sync_remote_path` (default `vaultwarden_backups`) — folder name on the cloud remote.

**Manual one-off runs:**

```bash
ssh pi@<pi> 'cd ~/containers && docker compose --profile backup run --rm backup-runner <cmd>'
```

Where `<cmd>` is one of: `backup`, `sync`, `restore [archive]`, `sync-restore`, `list`, `info`, `shell` (for ad-hoc debugging).

### Telegram notifications

Optional pings to Telegram on every backup and sync.

**Automatic:**
- Backup-runner reads `/run/secrets/telegram_token` and `/run/secrets/telegram_chatid` at runtime.
- Sends a formatted message via `https://api.telegram.org/bot<TOKEN>/sendMessage` on every backup, sync, restore, or sync-restore — success or failure.
- Detects missing/empty secret files and silently no-ops (no false-positive failures if you haven't set it up).
- Wraps the curl in `--max-time 15` and `|| true` so a Telegram outage never breaks your actual backup.

**You configure:**
- Create a Telegram bot via [@BotFather](https://t.me/BotFather) — it gives you a token like `1111:AAA...`.
- Get your chat ID from [@userinfobot](https://t.me/userinfobot) — message it once, it replies with your numeric ID.
- Set `telegram_token` and `telegram_chatid` in `config.yml`. Re-run the playbook to materialise the secrets and you're set.

To disable: blank out the values and re-run; the runner detects empty files and no-ops.

### Hardened OS

Defaults you want from a server holding your passwords.

**Automatic:**
- Rotates the `pi` user password to the hashed value in `config.yml`.
- Disables root SSH (`PermitRootLogin no`).
- Disables password authentication and PAM (`PasswordAuthentication no`, `UsePAM no`, `ChallengeResponseAuthentication no`).
- Installs UFW with default-deny incoming, default-allow outgoing.
- Opens SSH (rate-limited) and ports 80 + 443 before enabling UFW (so re-running the playbook never accidentally locks itself out).
- Installs fail2ban with a stock `sshd` jail (10-minute ban after 3 failed attempts in 10 minutes).
- Provisions a 1 GB `dphys-swapfile` — Pi Zero 2W has 512 MB RAM and apt + Docker installs reliably OOM the kernel without swap.
- Installs log2ram to keep `/var/log` in RAM, reducing SD card wear.
- Masks `packagekit.service` — Pi OS Desktop's GUI updater races Ansible for the dpkg lock and on a Pi Zero 2W the contention can wedge apt for 15+ minutes.

**You configure:**
- `pi_custom_password` — generate the hash with `mkpasswd --method=sha-512`, paste the `$6$...` blob. The plaintext stays out of the repo.

### Auto-updates

Two-layer freshness: OS packages and container images.

**Automatic (when `ensure_autoupdate: True`):**
- Configures `unattended-upgrades` for security updates only (no random package upgrades that might require restart).
- Sets `Unattended-Upgrade::Automatic-Reboot "false"` — server reboots are your call, not apt's.
- Watchtower runs in its own container on a daily 04:00 schedule, pulling new versions of `vaultwarden:<pinned>`, `nginx:alpine`, and (recursively) itself.
- Uses `nickfedor/watchtower` (the actively maintained community fork). The original `containrrr/watchtower` ships an outdated Docker client and restart-loops on current engines.

**You configure:**
- `ensure_autoupdate: True | False` — the master switch.
- `vaultwarden_version` in `config.yml` — pinned tag. **Don't unpin to `:latest`** — the nginx sub_filter that fixes mobile-app compat does literal string matching against vaultwarden's JSON response, and an unexpected upstream change can silently break iOS/Android logins. Bump deliberately, test, commit.

### Admin panel (optional, off by default)

Vaultwarden ships an `/admin` web panel for server management — user/org management, server config, diagnostics, invitations.

**Automatic when enabled:**
- Vaultwarden's `ADMIN_TOKEN_FILE` env var points at `/run/secrets/admin_token` (Docker secret).
- The argon2id hash sits in `/etc/vault_pi_secrets/admin_token` at `0600 root:root`, never in env vars or `docker inspect` output.
- When `vaultwarden_admin_token` is empty (default), the secret file is deleted and the env var unset — Vaultwarden serves a static "disabled" page at `/admin`.

**You configure (if you want it):**
- Generate an argon2id hash: `docker run --rm vaultwarden/server hash --preset=owasp5`
- Paste the full `$argon2id$v=19$m=...$...` blob into `vaultwarden_admin_token`.
- Re-run the playbook.
- Visit `https://<your-fqdn>/admin`, enter the plaintext passphrase (the one you typed into the hash command).

For a one-person setup the everyday value is small — most things are doable from the regular vault UI. Enable it temporarily when you need to send invites or change mail config, disable it again after.

### E-ink status badge (optional, off by default)

A small e-paper display physically attached to the Pi, showing the Bitwarden logo and your server's current uptime. There is no operational reason to add this. It will not make your backups any safer. It will, however, sit on your shelf looking like the most over-engineered "system status: nominal" sign in your house.

Compatible with the [Waveshare e-Paper HAT series](https://www.waveshare.com/wiki/E-Paper_HAT) (most personal builds use the 2.13" or 2.7" version — both around $20 on AliExpress / Amazon).

**Automatic when enabled:**
- Enables the SPI interface on the Pi (required for talking to the display over the GPIO header).
- Clones Waveshare's official [e-Paper driver library](https://github.com/waveshare/e-Paper) and installs the Python module.
- Ships the `show-label` rendering scripts to the Pi — these compose the Bitwarden logo + current uptime string into a 1-bit bitmap and push it to the display.
- Cron job at `:00` of every hour refreshes the displayed uptime.
- On reboot, the display is wiped clean so a stale "uptime: 42 days" doesn't haunt your shelf after a power outage.

**You configure:**
- Hardware: physically seat the Waveshare HAT onto the Pi's GPIO header before booting. The Pi Zero 2W's 40-pin header is fully compatible. (If you're using a Pi 4 or 5, no changes needed — same header layout.)
- `ensure_display: True` in `config.yml` — gates the whole feature. Default is `False`.

**Verifying it's working:**

After the playbook completes, the display should refresh within an hour (or on the next reboot). To force an immediate refresh without waiting for cron:

```bash
ssh pi@<pi> 'sudo bash /home/pi/display-lib/show-label/do_refresh.sh'
```

If nothing happens, check `dmesg | grep spi` on the Pi for SPI bus errors, and confirm the HAT is fully seated on the header.

---

## Day-2 operations

### Updating

```bash
ansible-playbook main.yml
```

Fully idempotent. Re-run any time. The OS gets security patches via `unattended-upgrades` daily; container images get refreshed by Watchtower daily; everything else is rolled in when you re-run the playbook.

### Disaster recovery (SD card failed, Pi stolen, house burned down)

The whole point of this setup is that it survives the loss of the Pi. Here's the full path back when you only have your Dropbox and your wits.

#### Before disaster strikes: what to write down

These three pieces of information are **not** stored on your Pi and **not** in your Dropbox backup. If you lose them, your vault is unrecoverable even though the encrypted data still exists. Write them down somewhere physical (a notebook in a drawer, a paper copy in a safe deposit box) the moment your setup is working:

1. **Your borg passphrase** (`borg_pass` in `config.yml`). This is the encryption key for every backup. Lose it and your Dropbox folder is a pile of unreadable noise. This is the single most important thing to record.
2. **Your Tailscale account email + auth method**. You need to be able to log back into [login.tailscale.com](https://login.tailscale.com) on a new device.
3. **Your vault master password**. You already know this. But knowing it matters more than ever in recovery — the playbook can resurrect the encrypted data, but only your master password decrypts the actual passwords inside.

Optional but useful:
- Your **Dropbox account credentials** (or whichever cloud you sync to).
- The **Git repo URL** if you've forked vault_pi to a private repo with your own modifications.

#### Step 1 — Get a new Pi running

1. Get any Raspberry Pi + microSD card. Flash Raspberry Pi OS (64-bit Lite) via Raspberry Pi Imager. Set:
   - **Username**: `pi`
   - **SSH key**: your public key (same one you've been using, or a fresh one — both work)
   - **WiFi**: your network credentials
2. Boot. Verify `ssh pi@<new-pi-ip>` works from your laptop without a password prompt. That's all the OS setup needed.

#### Step 2 — Restore your repo + config

```bash
git clone https://github.com/<you>/vault_pi.git
cd vault_pi
ansible-galaxy collection install -r requirements.yml
cp example.config.yml config.yml
cp example.inventory.ini inventory.ini
```

Now reconstruct `config.yml`. Most fields are easy (timezone, paths, etc. match the example). The ones that matter:

- `borg_pass` — paste the passphrase you wrote down above. **This must match exactly.**
- `rclone_config` — re-generate via `rclone config` on your laptop using the same backend + the same account you backed up to. The contents of the new `[remote]` block will look similar to the old one (OAuth backends issue new tokens; key-based backends like B2 / S3 will be identical). Either way, the existing `vaultwarden_backups/` folder on the remote is intact and the new config will see it.
- `tailscale_authkey` — generate a fresh one-time key in the Tailscale admin console.
- `vaultwarden_fqdn` — see step 3 below. Choose carefully.

Update `inventory.ini` to point at the new Pi's IP.

#### Step 3 — Reclaim your tailnet hostname

This is the step most people miss. Your devices (phone, laptop, etc.) all have the **old** Pi's URL configured in their Bitwarden app — `https://vaultwarden.tailnet-XXXX.ts.net`. You want the new Pi to take that same hostname so you don't have to reconfigure every client.

Two paths:

**Path A — preserve the old hostname (recommended):**

1. Go to [Tailscale admin → Machines](https://login.tailscale.com/admin/machines).
2. Find the **old** `vaultwarden` machine. Click the `...` menu → **Remove**. Confirm.
3. In your new `config.yml`, keep `vaultwarden_fqdn` and `tailscale_hostname` exactly the same as before. When the playbook runs `tailscale up --hostname=vaultwarden`, Tailscale will assign the now-vacant `vaultwarden.tailnet-XXXX.ts.net` to the new Pi.
4. Your phone and laptop will keep working without any reconfiguration once the new Pi is online.

**Path B — use a new hostname:**

If you've forgotten the old hostname or want a fresh start, pick a new `tailscale_hostname` (e.g. `vaultwarden2`). Set `vaultwarden_fqdn` to match. You'll need to update the server URL in every Bitwarden client afterward.

#### Step 4 — Run the playbook in restore mode

In `config.yml`, set:

```yaml
rclone_restore: True
borg_restore: True
```

Then:

```bash
ansible-playbook main.yml
```

This does the normal setup (Docker, Tailscale, TLS cert, containers) **and** at the end of the backup-runner setup it:

1. `sync-restore` — pulls your entire borg repo back from Dropbox into the local `borg_repo` Docker volume.
2. `restore latest` — extracts the most recent archive into `/restore/snapshot` inside the backup-runner container.

When the playbook finishes, the encrypted vault data is restored but not yet promoted into vaultwarden.

#### Step 5 — Promote the restored data into Vaultwarden

```bash
ssh pi@<new-pi>
cd ~/containers
docker compose stop vaultwarden
docker cp backup-runner:/restore/snapshot/. ./vw-data/
sudo chown -R pi:pi vw-data
docker compose start vaultwarden
docker logs -f vaultwarden   # watch it come up; Ctrl-C when you see "Rocket has launched"
```

#### Step 6 — Smoke test

From your phone or laptop (Tailscale connected), open the Bitwarden app. Log in with your master password.

You should see:
- All your vault items.
- All your folders and organisations.
- Your existing sessions on this device still valid (we restored `rsa_key.pem` so JWT signatures verify against the same key as before).

If you see your old data, the restore worked. If you see a blank vault and you're sure you're hitting the right server URL, something went wrong — start with `docker logs vaultwarden` for clues.

#### Step 7 — Clean up

Flip the restore flags back so they don't fire on every future playbook run:

```yaml
rclone_restore: False
borg_restore: False
```

Re-run the playbook one more time to apply. Future cron-driven backups will continue normally, adding new archives to the existing borg repo.

#### What if I forgot to write down the borg passphrase?

The encrypted repo on Dropbox is mathematically unrecoverable without the passphrase. There is no recovery service, no support line, no override. This is the standard tradeoff of "you, and only you, control your data." Save it somewhere now if you haven't.

If you discover this gap before disaster strikes, you can rotate the passphrase (`borg key change-passphrase` inside the backup-runner shell), then immediately write the new value down.

#### What if the Pi is dead but the SD card is intact?

You don't need this whole flow. Get a replacement Pi of any model, plug the same SD card in, power on. Tailscale, vaultwarden, nginx, and the backup-runner all auto-start via `restart: unless-stopped`. The hostname stays the same. Done.

### Switching to a different Pi voluntarily

This is the easy case — your old Pi still works and you're upgrading or relocating. The smoother path is:

1. On the old Pi: run a final backup manually so nothing recent is lost: `docker compose --profile backup run --rm backup-runner backup && docker compose --profile backup run --rm backup-runner sync`.
2. On the new Pi: follow the disaster-recovery flow from step 1 above, including reclaiming the tailnet hostname (path A) so your clients don't notice the swap.
3. Once the new Pi is verified working, you can wipe the old SD card.

### Adding more devices

For each new phone, laptop, or tablet:

1. Install Tailscale on it, sign into your account.
2. Install Bitwarden, point at the same `https://<your-fqdn>` URL.
3. Log in with your master password.

Up to 100 devices on the Tailscale free tier.

### Rotating credentials

All credentials are in `config.yml`. To rotate any of them: change the value, re-run the playbook. The secrets task re-renders the corresponding file in `/etc/vault_pi_secrets/` and the next `docker compose run` picks up the new value.

For the borg passphrase specifically, you need to additionally tell borg about the change:

```bash
ssh pi@<pi> 'cd ~/containers && docker compose --profile backup run --rm backup-runner shell'
borg key change-passphrase /repo
exit
```

Then update `borg_pass` in `config.yml` and re-run the playbook.

---

## Troubleshooting

**"The certificate for this server is invalid" on the iOS or Android Bitwarden app** — you're using `tls_provider: self_signed`. Switch to `tls_provider: tailscale` and re-run.

**"This is not a recognised Bitwarden server"** — two likely causes:

1. You upgraded `vaultwarden_version` and upstream changed the `/api/config` JSON shape, breaking the nginx sub_filter. Roll back the pin.
2. The app cached an old response. Force-quit and reopen.

**"Hostname not found" / "Could not connect"** — Tailscale isn't connected on your phone, or there's a typo in the server URL. Open the Tailscale app, ensure the VPN toggle is ON, then verify the URL by opening it in Safari/Chrome first.

**`apt update` hangs forever during playbook** — Pi OS Desktop's `packagekit` is racing for the dpkg lock. The playbook now masks it automatically, but if you flashed Pi OS Desktop before this fix shipped, `sudo systemctl mask packagekit` once and re-run.

**Backup runs but never appears on Dropbox** — check `/var/log/vault_pi_backup.log` on the Pi. Most common causes: expired Dropbox token (regenerate via `rclone config`, paste into `config.yml`, re-run playbook) or the cron job isn't running as a user in the docker group (`groups pi` should include `docker`).

**Telegram notifications not arriving** — try `ssh pi@<pi> 'cd ~/containers && docker compose --profile backup run --rm backup-runner backup'` and watch the output. If the notify call fails, you'll see it. Common cause: wrong chat ID (try with quotes, or send your bot a `/start` message first to initialise the chat).

**Watchtower restart-looping with "Docker API client version is too old"** — you somehow ended up on `containrrr/watchtower:latest` instead of `nickfedor/watchtower:latest`. Re-run the playbook (which renders the right image into compose), or `docker compose pull && docker compose up -d`.

---

## What this doesn't do

- **Doesn't expose your Pi to the public internet.** Access is via Tailscale only. This is the right call for a personal vault — there's no scenario where random strangers should be able to reach your password server.
- **Doesn't enable two-factor authentication on the vault by default.** Set it up inside the Bitwarden app or web vault once you've created your account (Settings → Two-step Login).
- **Doesn't send breach notifications for saved passwords.** That's a browser-extension feature; happens client-side. Available to self-hosted users at no extra cost.

---

## Acknowledgements

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden) by dani-garcia — the Rust Bitwarden-compatible server that makes this practical on a Pi.
- [Tailscale](https://tailscale.com) — for solving the "reachable from anywhere with a real TLS cert" problem so we don't have to.
- [borgbackup](https://www.borgbackup.org) and [rclone](https://rclone.org) — the backup-and-sync workhorses.
- [nickfedor/watchtower](https://github.com/nickfedor/watchtower) — actively maintained community fork of the abandoned containrrr/watchtower.
- Original [babanomania/vault_pi](https://github.com/babanomania/vault_pi) skeleton — the security hardening + backup design that this evolved from.

## Contributing

If you hit something this playbook didn't handle cleanly on your hardware, open an issue with the relevant log output. If you're an AI agent working on this codebase, read `AGENTS.md` first — there are several non-obvious constraints documented there.

---

## P.S.

You spent a Sunday building something a ten-dollar-a-year subscription would have done for you, sort of. By any reasonable cost-benefit calculation, this was a waste of time. By the math that actually matters — you understand it, you control it, you can fix it at 3 AM without filing a ticket — it absolutely wasn't.

Welcome to the cottage industry of one. Your password manager has joined your homelab, somewhere between the Pi-hole nobody has touched since 2022 and the network printer that mostly works. The Pi will outlast at least one password manager startup, two CEO changes at Dropbox, and an indeterminate number of your other side projects. By the time the SD card finally fails — and it will, because all SD cards do — you'll have forgotten how this stack worked, and re-learning will count as a hobby.

May your backups run on Saturdays, your tokens never expire, your tailnet stay friendly, and your master password never get typed into a phishing page. That last one is still on you. Even self-hosting has its limits.
