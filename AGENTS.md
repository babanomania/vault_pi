# AGENTS.md — guide for AI agents working on this repo

This is an Ansible playbook that turns a Raspberry Pi into a hardened, self-hosted Vaultwarden server compatible with the **official Bitwarden iOS app**. Most of the non-obvious code exists to satisfy two strict Bitwarden client behaviours. Read this file before changing TLS, nginx, or compose.

## Architecture in one paragraph

`ansible-playbook main.yml` runs four plays against the Pi: server hardening → backups (optional) → e-ink display (optional) → containers. The containers play renders `docker-compose.yml` and `nginx.conf` from Jinja templates, provisions a TLS cert (via Tailscale or self-signed), and brings up vaultwarden + nginx + watchtower. nginx terminates TLS and proxies to vaultwarden. Tailscale gives us a publicly-trusted Let's Encrypt cert that iOS will accept.

## The two iOS-app rules that drive most of the code

1. **Apple URLSession refuses user-installed CA roots** in security-sensitive apps. A self-signed Root CA the user installs on their iPhone *will not* work with the Bitwarden native app, even when iOS Settings shows it as trusted. Error code is `errSSLNoRootCert` (-9813) / `NSURLErrorDomain` -1202. The only fix is a cert from a CA in iOS's system trust store — hence Tailscale + Let's Encrypt.

2. **Bitwarden iOS app validates `server.name` in `/api/config`** and hard-rejects anything other than `"Bitwarden"`. Vaultwarden self-identifies as `"Vaultwarden"` by design (upstream maintainer refuses to mask). We rewrite the JSON in nginx with `sub_filter`. **Do not remove this filter.**

## Hard rules — don't do these

- **Don't unpin `vaultwarden_version`.** The nginx `sub_filter` uses literal string match on the JSON. If upstream changes whitespace, key order, or quoting, the filter silently stops matching and the iOS app starts rejecting again. Bump deliberately and re-test the app.
- **Don't switch watchtower back to `containrrr/watchtower`.** That image ships an ancient Docker client (API 1.25); current Docker engines need ≥1.40. You get a silent restart loop that pegs the Pi's SD card I/O until load avg hits ~10 and the whole playbook wedges. We use `nickfedor/watchtower` (community fork).
- **Don't remove the `packagekit` mask from `tasks/pre.yml`.** Pi OS Desktop's GUI updater races Ansible for the dpkg lock. On a Pi Zero 2W (slow SD, 512 MB RAM, swap on SD) the contention is catastrophic — `apt update` wedges for 15+ minutes.
- **Don't use `apt_key`.** Debian 13 (Trixie) removed `apt-key`. Use the modern pattern: `get_url` the key into `/etc/apt/keyrings/`, then `signed-by=<path>` in the `.list` file. See `tasks/security/log2ram.yml`, `tasks/containers/docker.yml`, `tasks/security/tailscale.yml`.
- **Don't add `req_extensions = v3_server` to `[req]` in `generate-certificate.sh.j2`.** The `authorityKeyIdentifier` ext requires an issuer cert in context — OpenSSL 3.x fails the CSR step. Extensions belong on the *signing* step (`openssl x509 -req -extensions ... -extfile ...`).
- **Don't run openssl with stdin open in scripts.** The script `exec </dev/null` is intentional. OpenSSL 3.x will silently prompt under some conditions and hang for 20+ minutes (we hit this).
- **Don't use `state: latest` for apt installs or `:latest` for images you depend on.** This codebase already burned multiple hours when upstream changed shape. Pin versions, bump deliberately.

## Soft rules — strongly preferred

- Every apt install should have `retries: 3, delay: 15, until: result is succeeded`. The Pi WiFi flakes.
- Every `get_url` for a binary > 1 MB should set `timeout: 300`. Default 10 s is far too short for Pi WiFi.
- New playbook tasks should pass `ansible-playbook main.yml --syntax-check` before commit.
- Idempotency is non-negotiable. Test a change by running the playbook twice — second run should report `changed=0` (or only the things you intentionally re-triggered).
- Templates use `{{ vaultwarden_fqdn }}` — derived once in `config.yml`. Don't hardcode hostnames.
- New env vars that contain secrets (`ADMIN_TOKEN`, auth keys) belong in `config.yml` (gitignored), never `example.config.yml`.

## Secret handling

All runtime credentials flow through Docker secrets, never plain env vars or files in user home dirs:

1. **`config.yml`** holds the plaintext value (gitignored).
2. **`tasks/security/secrets.yml`** materialises it as `/etc/vault_pi_secrets/<name>` (root:root 0600) — `no_log: true` on each task so Ansible doesn't echo the value.
3. **`docker-compose.yml.j2`** declares top-level `secrets:` with `file:` source pointing at that path, and lists the secret under the consuming service's `secrets:` block.
4. The container reads from `/run/secrets/<name>` — for processes that only accept env vars (e.g. Vaultwarden's `ADMIN_TOKEN`), use the `<NAME>_FILE` env-var convention if the app supports it (Vaultwarden, postgres, mariadb, redis-stack, etc. all do).
5. **Never** embed a secret in a CMD/ENTRYPOINT argv or any `environment:` block in compose — it leaks via `docker inspect`.

When adding a new secret:
- Pick a snake_case name matching the secret filename.
- Add to `tasks/security/secrets.yml` with `no_log: true` and a `when:` gating it to its feature flag.
- Add to `docker-compose.yml.j2` under both top-level `secrets:` (with the Jinja conditional) AND the service's `secrets:` list.
- Plumb into the container via `<NAME>_FILE=/run/secrets/<name>` or directly read the file in scripts.

The backup-runner is the canonical example — borg passphrase, rclone.conf, telegram token+chatid all flow through `/run/secrets/`.

## Conventions

| Concept | How it's expressed |
|---|---|
| Feature flags | Booleans in `config.yml` with `ensure_*` prefix, gated by `when:` on the play or task |
| TLS source | `tls_provider: tailscale \| self_signed`, branched in templates and tasks |
| Idempotency check on cert | `creates:` arg on `command:` task pointing at the cert file path |
| Restarting docker stack | `notify: docker restart` → single canonical handler in `handlers/docker_restart.yml` |
| Removing helper files post-task | `notify: remove generate-certificate` → handler with `file: state=absent` |
| Where binary keys live | `/etc/apt/keyrings/<vendor>.gpg` referenced via `signed-by=` |
| Where TLS certs live | `/home/pi/containers/nginx-data/certs/` (bind-mounted into nginx container at `/etc/nginx/conf.d/certs`) |
| Pi user | `ansible_user` (currently `pi`); password rotated via `pi_custom_password` hash |

## File map (what changes when)

- `main.yml` — play orchestration. Add new task imports here.
- `tasks/pre.yml` — runs before every play. Add things that must precede apt (swap, packagekit mask).
- `tasks/security/*.yml` — hardening + Tailscale + secrets materialisation.
- `tasks/security/secrets.yml` — writes plaintext from `config.yml` into `/etc/vault_pi_secrets/`. `no_log: true` on every task.
- `tasks/containers/containers.yml` — TLS provisioning + template rendering. Branches on `tls_provider`.
- `tasks/containers/docker.yml` — Docker engine + Compose plugin install.
- `tasks/backups/scheduling.yml` — ships backup-runner image source to Pi, builds it, installs `/etc/cron.d/vault_pi_backup` + logrotate policy. Handles one-shot `borg_restore` / `rclone_restore` flags.
- `tasks/post.yml` — cleanup + reboot.
- `handlers/` — restart logic. Triggered via `notify:`.
- `data/containers/docker-compose.yml.j2` — vaultwarden + nginx + watchtower + backup-runner compose. Top-level `secrets:` block is Jinja-conditional to avoid empty YAML.
- `data/containers/nginx-data/nginx.conf.j2` — TLS, sub_filter, WebSocket. Jinja-branched on `tls_provider`.
- `data/generate-certificate.sh.j2` — self-signed CA + leaf, executed on the Pi. iOS-compliant flags.
- `data/backup-runner/` — Alpine-based container image source: `Dockerfile` + `scripts/` (entrypoint dispatcher, backup, sync, restore, sync_restore, notify). Synced to Pi, built via `docker compose build`.
- `data/secrets/rclone.conf.j2` — full rclone config rendered into the secrets dir (NOT into the runner image — secrets must stay out of images).
- `config.yml` — user config (gitignored). Source of truth for all runtime variables.
- `example.config.yml` — template for new deployments. Mirrors structure of `config.yml`, no secrets.

## Test workflow

1. `ansible-playbook main.yml --syntax-check`
2. `ansible-playbook main.yml --list-tasks` — confirm new tasks show up
3. `ansible-playbook main.yml` — first run lands changes
4. `ansible-playbook main.yml` — second run must report `changed=0`
5. From your Mac: `curl -I https://<fqdn>/` should return 301 (HTTP→HTTPS) or 200 (direct HTTPS). `openssl s_client -connect <fqdn>:443 -showcerts </dev/null | openssl x509 -noout -issuer -dates -ext subjectAltName,extendedKeyUsage` — verify SAN, EKU=serverAuth, validity ≤ 90 days (tailscale) or 398 (self-signed).
6. From the iPhone Bitwarden app: change server URL, log in. If it errors, capture the error blob from the app's diagnostics screen and check it against `kCFNetworkCFStreamSSLErrorOriginalValue` codes.

## Gotchas observed during development

- **Pi Zero 2W's WiFi chip** flakes under sustained download. `get_url` retries + 5-min timeout are mandatory.
- **`download.docker.com` from Pi** intermittently fails to fetch optional sub-packages (`docker-ce-rootless-extras`, `docker-compose-plugin`, `docker-model-plugin`). We avoid `get.docker.com/install.sh` entirely; install only `docker-ce docker-ce-cli containerd.io` directly via apt.
- **mDNS resolution from the Mac** sometimes returns IPv6 link-local first, which UFW drops. `ansible.cfg` has `ssh_args = -4 …` to force v4.
- **The `tailscale up --hostname=X` parameter** is sticky once joined; changing it on a reauthenticated Pi requires `tailscale logout` first.
- **The `Server` SSID has a literal trailing space** in this user's home network. Quoting matters in `nmcli connect`.
- **Borg restore from an existing repo** isn't currently a playbook task. It was done ad-hoc — see project memory.
