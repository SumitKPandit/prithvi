# AUDIT.md — independent review of the g3plus home server

Scope: the whole home server, repo + live system. Every check records ID, what it
verifies, the exact command/action, trimmed evidence, and a verdict:
`PASS` / `FAIL` / `WARN` / `SKIPPED` (reason) / `NEEDS-HUMAN`. No PASS is marked
from code-reading alone when the live system could be tested, and none from memory.
No secrets are printed; redactions use `<REDACTED>`.

Ground rules honored: A (read-only) and B (non-disruptive) done; nothing changed
on the server except two temporary image pulls (cleaned), and pre-commit
auto-fixed two files, which were reverted. Stages C and D were **not** run and
need explicit approval.

---

## Summary scorecard

| Section | PASS | FAIL | WARN | SKIPPED | NEEDS-HUMAN |
|---|---|---|---|---|---|
| A1 Repo quality | 18 | 4 | 1 | 0 | 0 |
| A2 Secrets | 11 | 2 | 1 | 0 | 0 |
| A3 Host config | 24 | 2 | 2 | 0 | 0 |
| A4 Network exposure | 14 | 5 | 2 | 3 | 2 |
| A5 Container/auth | 9 | 3 | 3 | 2 | 0 |
| A6 Unnecessary | 6 | 0 | 4 | 0 | 0 |
| A7 Documentation | 6 | 6 | 1 | 0 | 0 |
| B1 Tooling/idem | 4 | 2 | 0 | 0 | 0 |
| B2 HTTPS/access | 3 | 4 | 0 | 0 | 0 |
| B3 Media stack | 6 | 4 | 1 | 0 | 4 |
| B4 AI/apps | 1 | 3 | 1 | 2 | 3 |
| B5 Monitoring | 0 | 4 | 0 | 0 | 1 |
| **Total** | **102** | **39** | **16** | **7** | **10** |

**Overall verdict.** The Ansible repo is well structured and the deployed pieces
that *were* deployed are largely sound (SSH hardening proven, UFW active incl.
IPv6, ports bound to specific addresses, idempotent applies, pinned images,
restic snapshot present + `check` clean). **But the live server does not match the
README/spec in many material ways**, and several claims the README makes are
false because the underlying capability was never installed:

1. **Teardown is broken in three independent ways** (invalid `teardown.yml`,
   nothing Ansible on the server, and `teardown_data` semantics are wrong). The
   documented data-protection guarantee is the opposite of what executes.
2. **The documented access model does not exist.** There are no
   `*.home.sumitkpandit.in` DNS records, no Cloudflare Tunnel connector, no
   `dokploy` Caddy route, and Caddy is serving a self-signed cert. Every
   documented URL is either unresolvable, 502s (Homepage), opens its wizard
   (Jellyfin, Uptime Kuma, Jellyseerr), or 404s.
3. **The "optional, off" Vpn toggle is broken**: `vpn_enabled: true` renders
   invalid YAML (`start_period: 30s  gluetun:`), and would also break Caddy.
4. **Backups are local-only.** One restic snapshot, no rclone/Drive token, no
   off-site copy. The README's "Google Drive backups" does not happen. Uptime
   Kuma's config is not coherently captured (the dump script targets the
   wrong database backend for Kuma 2.x).
5. **Security:** Docker Swarm control plane (2377/7946/4789) is listening on all
   interfaces and allowed from tailscale0; `ip6tables DOCKER-USER` is empty
   while Dokploy's admin UI is published on `[::]:3000`; UFW has 10 manual
   rules not in the repo; `/etc/dokploy` is world-writable; the CPU package
   idles at ~64 °C.
6. **Repo drift:** `main` is 1 commit ahead of `origin/main`; `full-draft` is
   unpushed; secrets.sops.yaml is populated for only ~9 of 23 keys.

Recommendation: **do not tear down** (it is destructive and non-functional as
written), fill the empty secrets, and re-run `make apply` after fixing the
findings below. Stage C (reboot/restore/failure tests) and Stage D (teardown +
rebuild) must wait until teardown is corrected and the secrets are
re-populated, and require your explicit go-ahead.

---

## Findings, prioritized

### Critical

**F-01 — `teardown.yml` is invalid; `make teardown` cannot run.**
Evidence: `cd ansible && ansible-playbook --syntax-check teardown.yml` →
`[ERROR]: 'ansible.builtin.command' is not a valid attribute for a Play`
(rc=4), because every task sits outside a `hosts:` play. The tasks are
T2–T10, all at play level. Separately, `make teardown` does
`ssh g3plus 'ansible-playbook ansible/teardown.yml -e confirm_teardown=yes'`,
but Ansible is not installed on the server and the repo is not present there
(`which ansible-playbook` → not found; no `/home/sumit/codebase`).
Risk: the only escape hatch is a no-op; a user who "resets" the box gets a
half-configured, half-left state.
Fix: restructure `teardown.yml` into a real play (`hosts: g3plus`, `become:
true`), include the missing `storage` role's `remove.yml`, drop the
`or not (item is defined)` fragments, and run the role `remove.yml`s from the
Mac with `ansible-playbook` (not on the server). Effort: small (a few hours).

**F-02 — The `teardown_data` guard is meaningless and the real data loss is
unguarded.**
Evidence: `ansible/teardown.yml:31` `when: not teardown_data | bool or not (item is defined)` is always true (`item` is undefined outside a loop), so
dokploy/media removal is never gated. `storage/tasks/remove.yml` is **never
called** by teardown. Meanwhile `backup/tasks/remove.yml` (called first)
recursively deletes `/opt/backups/restic` (the only backup copy) with no
`teardown_data` condition; `media/tasks/remove.yml` deletes all media
configs; `dashboard/tasks/remove.yml` deletes Uptime Kuma/Dockge/Homepage
configs; and `dokploy/tasks/remove.yml:43` deletes `/opt/appdata/dockge`
(the *dashboard* role's directory — a path typo) which, because `file:
state=absent` recurses, actually wipes Dockge's data.
Risk: running `make teardown` (once F-01 is fixed) destroys the backup repo
and Dockge's data without any `teardown_data=yes` prompt. Current (broken)
state leaves this latent.
Fix: gate every destructive removal on `teardown_data | bool`, fix the
`dockge` path typo, and call `storage/remove.yml`. Effort: small.

**F-03 — Nothing private resolves, and no tunnel/cert path is provisioned.**
Evidence: `dig +short jellyfin.home.sumitkpandit.in A` (all 12 names) → empty;
`/opt/stacks/tunnel` does not exist; `docker ps` has no `cloudflared`;
Caddyfile has `tls internal` and a cert from `CN=Caddy Local Authority - ECC
Intermediate`, 12-hour validity; `/opt/stacks/proxy/.env` is 14 bytes (`CF_API_TOKEN=` empty). The secrets `cloudflare_api_token` and
`cloudflare_tunnel_token` are empty in `secrets.sops.yaml`.
Risk: the README's entire private-hostname URL model is documentary fiction;
Jellyfin/arr/dashboards are reachable only by `127.0.0.1:<port>` or via
`--resolve` + accepting a self-signed cert.
Fix: populate the two secrets, run `make apply`, and verify `dig` returns
`100.88.141.33` and Caddy obtains a real LE cert. Effort: ~15 min.

**F-04 — Jellyfin is not configured, and hardware transcoding is off.**
Evidence: `curl http://127.0.0.1:8096/System/Info/Public` →
`"StartupWizardCompleted": false`; `/Startup/Configuration` → 200 (wizard
open); `Users` table empty (1 row is the server itself); `/data/media/{movies,tv}`
exist but the Jellyfin libraries are never created (no collections);
`encoding.xml` → `<HardwareAccelerationType>none</...>`,
`<HardwareDecodingCodecs></...>` even though `/dev/dri/renderD128` is passed
in and the ffmpeg build lists qsv/vaapi encoders.
Risk: any visitor to the LAN:443 hostname opens the Jellyfin setup wizard and
could claim the admin account; every stream transcodes in software (N150 CPU).
Fix: set `jellyfin_admin_password` in the secrets (the role's wiring block is
gated on it), then `make apply`; confirm `HardwareAccelerationType=qsv` and a
real transcode via `intel_gpu_top`. Effort: ~15 min.

**F-05 — Offsite backup is absent; Kuma config is not coherently captured.**
Evidence: `/etc/rclone/rclone.conf` missing; `rclone_drive_token` empty;
`backup.service` log: `rclone: no Drive token yet, keeping the backup local only`; one restic snapshot (7.8 MB) on the same NVMe; `restic check` →
`no errors were found`; `backup-maintain.sh` restore drill → `Restored 4 / 1
files/dirs` (works). Uptime Kuma's config lives in MariaDB at
`/opt/appdata/uptime-kuma/mariadb/` (`kuma.db` never appears, and
`/opt/appdata/uptime-kuma` is 192 MB), so `dump.sh.j2`'s sqlite probe
`.backup /opt/appdata/uptime-kuma/kuma.db.bak` never runs.
Risk: backups are single-copy on the same physical NVMe; Kuma's monitors are
not backed up at all (restores lose every monitor/notification).
Fix: create the Drive token, populate the secret, re-run apply; replace the
Kuma dump with a MariaDB `mysqldump` of the `kuma` DB (or copy with the
container stopped). Effort: ~45 min.

### High

**F-06 — Homepage returns 502 behind Caddy.**
Evidence: `curl --resolve homepage.home.sumitkpandit.in:443:192.168.0.2`
→ 502; Caddy log `dial tcp 172.18.0.12:3000: i/o timeout`; inside the
container, requests to its own IP log
`Host validation failed for: 172.18.0.12:3000. Hint: Set the
HOMEPAGE_ALLOWED_HOSTS environment variable...`. The compose template never
sets `HOMEPAGE_ALLOWED_HOSTS`.
Fix: add `HOMEPAGE_ALLOWED_HOSTS` (e.g. `homepage.home.sumitkpandit.in,localhost`)
to the homepage service env in
`roles/dashboard/templates/compose.yaml.j2`, re-apply. Effort: small.

**F-07 — Uptime Kuma has no admin, no monitors, no notifications.**
Evidence: `/opt/appdata/uptime-kuma/kuma.db` absent (2.x is MariaDB-backed);
`db-config.json` empty-ish; `curl /` on the web network → 302 to its login.
`telegram_bot_token_uptime_kuma` empty, `uptime_kuma_disk_push_token` empty,
`uptime_kuma_backup_push_token` empty → `disk-usage-check.timer` is
`disabled` and the backup/disk push monitors cannot push.
Fix: create the Kuma admin account, add the monitors the README describes
(or drop that claim), fill the tokens, re-apply; enable the timer.
Effort: ~30 min.

**F-08 — Docker Swarm control plane is exposed.**
Evidence: `ss -tulpn` → `dockerd` listening on `*:2377`, `*:7946` (tcp+udp),
`0.0.0.0:4789/udp`; UFW has no rules for them but the default-deny is
bypassed from `tailscale0` (`ufw-user-input` `-i tailscale0 -j ACCEPT`).
Risk: any tailnet device can issue Swarm Raft commands.
Fix: pin Swarm to one interface or drop tailscale0 for those ports; either
move the `tailscale0` accept to only-allow the documented ports, or drop
2377/7946/4789 from tailscale0. Effort: small.

**F-09 — `ip6tables DOCKER-USER` is empty; Dokploy admin UI is dual-stack.**
Evidence: `sudo ip6tables -S DOCKER-USER` → `-N DOCKER-USER` (no rules);
`docker service inspect dokploy` → `"PublishedPort":3000,"PublishMode":"host"`
with `[::]:3000->3000/tcp` in `docker ps`. Today there is no global IPv6 on
`wlp1s0` and no v6 default route, so this is latent; if a prefix is ever
delegated, the admin UI is world-reachable over v6.
Fix: add the same `! -i tailscale0 -p tcp --dport 3000 -j DROP` to the v6
chain in `docker-user-rules.sh` (and the systemd unit). Effort: small.

**F-10 — UFW state has drifted from the repo (10 extra LAN rules).**
Evidence: `sudo ufw status numbered` shows 10 LA Rdefer rules
(`443/tcp`, `8096`, `3001:5001`, `8080`, `8989`, `7878`, `6767`, `9696`,
`5055`, `3000` from `192.168.0.0/24` — comments like
"LAN Jellyfin direct access") with `iptables -S ufw-user-input` confirmed.
The `security` role only creates rules 1–2 and 13. These were added outside
Ansible. This is exactly what `verify-clean` is supposed to catch, and it
also conflicts with the README's "Caddy is the real proxy" model (those ports
are also bound to 127.0.0.1, so the UFW allows are dead weight).
Fix: decide on one LAN-access policy; if direct LAN ports are wanted,
encode them in the role; else delete them. Effort: small.

**F-11 — VPN-enabled media stack renders invalid YAML and would also 502
Caddy.**
Evidence: rendered with `vpn_enabled=true` + VPN secrets →
`start_period: 30s  gluetun:` (the `{%- if vpn_enabled %}` newline takes the
previous line's terminator); `sudo docker compose -f - config -q` →
`go-yaml load error ... mapping values are not allowed`. Separately, with
`network_mode: service:gluetun`, the Caddyfile's `reverse_proxy
qbittorrent:8080` 502s because the container is only reachable as `gluetun`.
Fix: in `roles/media/templates/compose.yaml.j2`, use `{% if vpn_enabled %}`
(newline preserved) and make the Caddyfile route `qbittorrent` to
`gluetun:8080` when `vpn_enabled`. Effort: small.

**F-12 — Dokploy admin account does not exist and its UI has no DNS/route.**
Evidence: `psql` `select count(*) from "user"` → 0; `application` and
`domain` tables → 0; Caddyfile has no `dokploy` matcher; no DNS record.
`ddokploy-traefik` currently only answers `dokploy.docker.localhost`. The
README tells you to create the admin at `https://dokploy.home.sumitkpandit.in`
— a hostname that does not resolve.
Fix: point at `http://192.168.0.2:3000` (UFW rule 12 allows it) or create the
record + route; create the admin; confirm. Effort: ~10 min.

**F-13 — Hermes is not deployed.**
Evidence: `secrets['hermes_openrouter_api_key']` empty; the role is gated on
it in `site.yml`; no `hermes` container, no `/opt/stacks/hermes`.
Fix: populate the OpenRouter/Telegram/dashboard secrets and re-apply.
Effort: ~15 min.

**F-14 — Tunnel connector is absent, so public apps cannot exist.**
Evidence: no `cloudflared` service; `tunnel` role skipped (token empty);
apical `sumitkpandit.in` is Cloudflare-proxied (104.21.14.214 / 172.67.160.150).
Fix: create the tunnel, fill `cloudflare_tunnel_token`, re-apply. Effort: ~15 min.

**F-15 — `unattended-upgrades` is not "security-only" as documented.**
Evidence: effective config
```
Unattended-Upgrade::Allowed-Origins:: "${distro_id}:${distro_codename}";
Unattended-Upgrade::Allowed-Origins:: "${distro_id}:${distro_codename}-security";
Unattended-Upgrade::Allowed-Origins:: "${distro_id}ESMApps:...";
Unattended-Upgrade::Allowed-Origins:: "${distro_id}ESM:...";
```
— the first line is the *plain* archive (all updates), because stock
`/etc/apt/apt.conf.d/50unattended-upgrades` merges with the repo's
`52-security-auto-reboot` rather than being replaced.
Fix: prepend `"";` (empty entry) to clear the list, i.e.
`Unattended-Upgrade::Allowed-Origins { ""; "${distro_id}:${distro_codename}-security"; };`.
Effort: one line.

**F-16 — Repo is not fully pushed.**
Evidence: `git log --oneline @{u}..` → `6f3e56e Add teardown...` (1 commit
ahead); `git branch -vv` → `full-draft 41bae1d ...` not pushed.
Fix: `git push origin main` and decide on `full-draft`. Effort: 1 minute.

### Medium

**F-17 — `nas` role is documented but absent; `nas_enabled` is dead.**
`group_vars/all.yml` defines `nas_enabled: false`, the README Phase 6
describes a full SnapRAID+mergerfs role and a `make nas-format` playbook, but
no `roles/nas/` exists and `make nas-format` is not a target.
Fix: implement the role guarded by `nas_enabled` + assertions, or remove the
var and the README section. Effort: large / ~zero.

**F-18 — `make verify-clean` runs no comparison and its baseline is missing.**
The target tees server state to a local file and prints "Review the diff",
but never diffs; `baseline/` does not exist, so its own empty-guard fires.
`capture-baseline/` is an empty stray dir; `scripts/capture-baseline.sh` is
fine but its output was never committed.
Fix: commit a baseline captured from a genuinely fresh install, and make
`verify-clean` actually diff the two trees with the documented allow-list.
Effort: ~1 h.

**F-19 — `verify.yml` skips the highest-value assertions.**
It passes today but it does not assert: any listening port outside the
allow-list, IPv6 rules, Homepage reachability, Jellyfin `HardwareAccelerationType`,
`disk-usage-check.timer` enabled, the DNS records exist, the tunnel service
is up, or that secrets and server state agree (F-03/04/05/07/12/13/14 would
all be caught by such checks). Its HTTPS endpoint check is skipped whenever
`cloudflare_api_token` is empty.
Fix: promote these into `verify.yml`. Effort: ~1 h.

**F-20 — Jellyseerr is unclaimed (`/setup` → 200).**
`curl /setup` → 200. Anyone who reaches it becomes admin. Bazarr is also not
authenticated by the role (its API key is dead). Fix: complete setup, set
p@ss, fill the dead secret keys or remove them. Effort: ~10 min.

**F-21 — `dokploy/tasks/remove.yml` wipes the wrong directory.**
`/opt/appdata/dockge` (dashboard role) will be recursively deleted by
dokploy's remove. Also the task name lies ("if empty"; `file` recurses
unconditionally). See F-02.

**F-22 — Uptime Kuma is 192 MB of MariaDB in the backup scope.**
`/opt/appdata/uptime-kuma/mariadb` (ibdata1 77 MB, ib_logfile0 96 MB). The
Kuma dump is broken (F-05); the raw files add ~190 MB to every restic
snapshot. Fix: fix the dump, exclude mariadb from the restic scope or accept
it knowingly. Effort: small.

**F-23 — `sumit` is in group `lxd`.**
`id sumit` → groups include `101(lxd)`. LXD group members can root the host
via `lxc`. It came from the Ubuntu install, not this repo.
Fix: `sudo gpasswd -d sumit lxd` and reconnect SSH. Effort: 2 min. Ask me first.

**F-24 — Jellyfin/Arr config files are world-readable.**
`/opt/appdata/qbittorrent/qBittorrent/qBittorrent.conf` is 644 and contains
the PBKDF2 password hash. Fix: `0640`/`0600` media:media. Effort: 1 min.

**F-25 — No CPU limits; no `cap_drop`; no `no-new-privileges` on any
container.** All media containers run as root inside (PUID mapping handles the
host side), several mount the Docker socket. This is typical for the arr stack
but means one compromise = full Docker control. At minimum set
`cap_drop: [ALL]` + `no-new-privileges: true` where the app allows it, and
record the accepted risk for Dockge/Dokploy. Effort: ~1 h.

### Low

**F-26** — `verify.yml:195` uses `that: "{{ item.stdout != 'no' }}"` —
deprecation warning, will break in ansible-core 2.23. Quote without braces.

**F-27** — `50-cloud-init.conf` still says `PasswordAuthentication yes`;
ordering wins today, but delete the line to make it robust.

**F-28** — `docker.service` has no `IPAddressDeny`/iptables for 2377/7946/
4789 (F-08), and `docker_gwbridge` is up with no firewall (it is behind
default-deny; OK).

**F-29** — `hello-world:latest` image and `caddy:2.11.6` (builder) are
dangling; 2.27 GB of build cache is reclaimable (`docker builder prune`).

**F-30** — `htop` is installed but not in the repo; `/tmp/rebuild/*.json`
(7 `docker inspect` dumps, 644, contain full container env) and
`/tmp/generate_commands.py` are leftovers; `/home/sumit/.ansible/tmp` has 5
stale temp dirs. Clean them.

**F-31** — `.gitignore` does not cover `rclone.conf`, `restic.pass`,
`.netrc`, `credentials`, `baseline/`, `*.sql.gz`. Add them.

**F-32** — README smartd line says long test "Sat 13:00"; the cron
`L/../../6/13` means Friday. One-off doc fix.

**F-33** — `acme_email: ""` with a TODO comment: LE expiry notices impossible.

**F-34** — `/opt/appdata/flaresolverr` is `root:root` (media role's loop
excludes it); cosmetic.

**F-35** — `/opt/stacks/media/.env` is 0 bytes (VPN creds empty when off).
Harmless but noisy.

**F-36** — Broken Homebrew shim: `/opt/homebrew/bin/tailscale` points at a
missing app; `tailscale status` on the Mac errors.

**F-37** — No healthcheck for flaresolverr / dokploy-traefik /
dokploy-postgres.

**F-38** — `docker-user-rules` drops 3000 from non-tailscale on IPv4 only;
see F-09.

**F-39** — Recyclarr absent (B3 expects "Recyclarr has synced profiles");
README never mentions it. Either add it or fix the spec/README.

**F-40** — `make deps` with `--force` lands duplicate collections under
`~/.ansible/collections` (two versions of ansible.posix visible). Harmless;
pin one location.

**F-41** — pre-commit `end-of-file-fixer` fails on `ansible/ansible.cfg` and
`.gitignore` (no trailing newline). Run the hooks once and commit.

**F-42** — `make apt-upgrade` runs `apt full-upgrade` with no
`--with-new-pkgs`/auth-drift caveats; a failed rerun can leave
dpkg interrupted state. Document `apt --fix-broken install` in
Troubleshooting.

**F-43** — `README` "Phase 6 NAS" and the `[phase6 nas]/` layout line claim a
role that is absent; also `make nas-format` referenced. See F-17.

---

## Full check table

| ID | Check | Command/action | Result | Notes |
|---|---|---|---|---|
| A1-01 | Layout matches README | `find .` vs README.md tree | **FAIL** | `baseline/` missing; `capture-baseline/` stray empty dir; `roles/nas/` absent; `roles/stacks/` only on `full-draft`. |
| A1-02 | `make lint` clean | `make lint` | **PASS** | yamllint 0; ansible-lint `Passed: 0 failure(s)` (production profile). |
| A1-03 | pre-commit clean | `pre-commit run --all-files` | **FAIL** | end-of-file-fixer modifies `ansible.cfg`, `.gitignore` (reverted). |
| A1-04 | FQCN, quoted modes, unique handlers, flush_handlers, no_log, why-comments, Jinja | read all roles | **PASS** | cross-role handler coupling noted (tailscale remove notifies docker's `Refresh apt cache`). |
| A1-05 | No hardcoded values | grep | **FAIL** | `dump.sh.j2` `/opt/appdata`, `pg_dump -U dokploy -d dokploy`; `maintain.sh.j2` `/opt/stacks`; `dokploy/remove.yml` `/opt/appdata/dockge`. |
| A1-06 | Every role has remove.yml | ls roles/*/tasks/remove.yml | **PASS** | 11/11. |
| A1-07 | teardown order | read teardown.yml | **FAIL** | storage missing; `item is defined` fragment; invalid (F-01). |
| A1-08 | No `:latest` tags | grep image tags | **PASS** | all pinned except `postgres:16` (from Dokploy's own spec) and server-side `hello-world`. |
| A1-09 | Dokploy pinned | defaults + installer URL + live | **PASS** | `v0.30.8`, installer from that release; traefik `v3.6.25` live. |
| A1-10 | Caddy pinned | compose + Dockerfile | **PASS** | `caddy-cloudflare:2.11.6`, builder pinned too. |
| A1-11 | Dead code | grep + git | **FAIL** | `nas_enabled`, `internal_bazarr_api_key`, `internal_jellyseerr_api_key`, `telegram_bot_token_uptime_kuma`, `capture-baseline/`, README's broken `remove`/`firewall` tag docs. |
| A1-12 | Working tree clean | `git status --short` | **PASS** | clean. |
| A1-13 | One commit per phase | `git log --oneline` | **PASS** | 17 commits, each a phase. |
| A1-14 | Remote exists and is pushed | `git remote -v`, `git log @{u}..` | **FAIL** | main 1 ahead; `full-draft` unpushed. |
| A1-15 | .gitignore covers secrets | read + probe | **WARN** | missing rclone.conf/restic.pass/.netrc/credentials/baseline (F-31). |
| A2-01 | .sops.yaml public keys only | cat | **PASS** | one age public key. |
| A2-02 | secrets.sops.yaml encrypted | `grep -c "ENC\["` = 22 | **PASS** |. |
| A2-03 | secrets.example.yaml empty values | cat | **PASS** | only `jellyfin_admin_username: "sumit"` preset. |
| A2-04 | History secret scan | `git log -p` patterns (age/sk-or/CF/token/BEGIN PRIVATE/Bearer) | **PASS** | 4 hits, all the same age *public* key; `full-draft` `.env.example` files all empty. |
| A2-05 | age key outside repo | `ls ~/Library/.../age/` | **PASS** | `keys.txt` 0600, never committed. |
| A2-06 | secrets-edit works | `sops -d` round-trip | **PASS** | decrypts to a populated-but-incomplete file (see F-03/F-04/F-05). |
| A2-07 | server .env modes | stat | **PASS** | `/opt/stacks/{media,proxy}/.env` 600 root:root; `/etc/restic.pass`, `/etc/kuma-push.env` 600. |
| A2-08 | secrets in compose files | grep | **PASS** | only `${VAR}` references. |
| A2-09 | secrets in shell history | grep | **PASS** | 0 hits. |
| A2-10 | secrets in journal/logs | journalctl grep | **PASS** | 0 hits. |
| A2-11 | verbose run leaks secrets | apply logs | **PASS** | `no_log: true` set on every secret-touching task. |
| A2-12 | world-readable secrets | find | **WARN** | qBittorrent.conf 644 w/ hash (F-24). |
| A2-13 | server state matches secrets | `sops -d` keys | **FAIL** | 14 of 23 empty; drift from images/UFW/UI wizards. |
| A3-01 | OS/kernel | os-release, uname | **PASS** | Ubuntu 26.04.1 LTS, 7.0.0-38. |
| A3-02 | chrony/NTP/TZ | timedatectl, chronyc | **PASS** | synchronized, UTC, NTP active. |
| A3-03 | sshd -T values | `sshd -T` | **PASS** | password no, kbd no, root no, pubkey yes, x11 yes (review). |
| A3-04 | drop-in ordering beats 50-cloud-init | grep + password-only ssh attempt | **PASS** | `Permission denied (publickey)`; server offers publickey only. `50-cloud-init.conf` still contains `PasswordAuthentication yes` (F-27). |
| A3-05 | UFW active, policies, v6 | `ufw status verbose`, `ip6tables -S` | **PASS** | deny in / allow out / deny routed; IPV6=yes; ufw6 chains populated, policy DROP, tailscale0 allowed. |
| A3-06 | rules reproducible from repo | compare numbered list to role | **FAIL** | 10 extra LAN rules not in Ansible (F-10). |
| A3-07 | IPv6 firewalling | `ip -6 addr scope global`, `ip6tables -S` | **PASS** | no global v6 on wlp1s0; no v6 default route; ufw6 INPUT policy DROP. |
| A3-08 | sudoers | stat + visudo | **PASS** | `/etc/sudoers.d/90-sumit` 440, parses OK; only stock README stray. |
| A3-09 | unattended-upgrades config | `apt-config dump` | **FAIL** | Automatic-Reboot true / 21:30 / WithUsers true (good), but Allowed-Origins includes plain archive (F-15). |
| A3-10 | Docker/Tailscale manual routine documented | README | **PASS** | `make apt-upgrade` + README mention; verify-clean-list exists. |
| A3-11 | Docker version/enabled/daemon.json/live-restore | `docker info`, stat | **PASS** | 29.8.2, enabled, log rotation 10m×3, `LiveRestoreEnabled=false`. |
| A3-12 | user groups | `id sumit` | **PASS** | docker/render/video present; see F-23 (lxd). |
| A3-13 | docker info warnings | stderr | **PASS** | none. |
| A3-14 | storage paths/owners/modes | stat | **PASS** | `/data` 755 root, `/data/{torrents,media}` 775 media:media, `/opt/appdata` 775 media:media, `/opt/stacks` 755 root, `/opt/backups` 700 root. |
| A3-15 | data_root threaded everywhere | grep | **PASS** | all stack compose mounts use `/data`, `/opt/appdata`, `/opt/stacks`; only the reported hardcodes (F-02/05) deviate. |
| A3-16 | torrents & media same fs | `stat -c %d` | **PASS** | both on `/dev/nvme0n1p2` (66306). |
| A3-17 | disk/inodes | df | **PASS** | 6% of 476 GB, 2% inodes. |
| A3-18 | SMART | smartctl | **PASS** | PASSED, 0% used, 0 errors, 41h on, 13 unsafe shutdowns. |
| A3-19 | temps | sensors/smartctl | **FAIL** | package idles at +64 °C (BIOS high-performance); above the README's own 60 °C threshold (F-26). |
| A3-20 | memory/swap/load | free/uptime | **PASS** | 3.0/14.7 GB, 0 swap used, load ~0.3. |
| A3-21 | fwupd history | fwupdmgr | **PASS** | No history. |
| A4-01 | every listening socket | `ss -tulpn` | **PASS** | enumerated; only 22/443/6881/3000 + resolver/chrony/systemd + swarm. |
| A4-02 | every 0.0.0.0 justified in README ports table | compare | **FAIL** | no ports table at all; 22, 3000, 2377, 7946, 4789 undocumented. |
| A4-03 | published ports bound to a specific address | `docker inspect` | **FAIL** | dokploy `0.0.0.0:3000` + `[::]:3000`; swarm ports everywhere. |
| A4-04 | Docker-vs-UFW explanation exists | README | **PASS** | documents PREROUTING bypass + DOCKER-USER. |
| A4-05 | Traefik 80/443 unpublished | `docker inspect dokploy-traefik` | **PASS** | `PortBindings={}`. |
| A4-06 | un-publish survives restart/update | service restart | **SKIPPED** | needs Stage C reboot test; the task *does* run every apply (observed re-creation 11 min before inspection). |
| A4-07 | Dokploy UI LAN+Tailscale only | nmap from Mac | **PASS/SKIPPED** | from LAN, 3000 is filtered (UFW+DOCKER-USER). Tailscale untested (no tailscale on Mac). |
| A4-08 | swarm advertise = LAN IP | docker info | **PASS** | `Addr=192.168.0.2`. |
| A4-09 | nmap LAN | nmap | **PASS** | 22/443/6881 open; 80/3000/2377/7946/2019 filtered. |
| A4-10 | nmap Tailscale | nmap 100.88.141.33 | **SKIPPED** | no Tailscale client on the Mac. |
| A4-11 | global IPv6 + firewall | `ip -6`, ip6tables | **PASS** | no global v6; ufw6 policy DROP; tailscale0 v6 allowed. |
| A4-12 | DNS private records | dig | **FAIL** | none. |
| A4-13 | DNS public app records | dig | **SKIPPED** | no token, nothing deployed. |
| A4-14 | no admin UI public | DNS/Cloudflare | **PASS** | no records at all (nothing public exists, intentionally or not). |
| A4-15 | phone test (tailscale off/on) | — | **NEEDS-HUMAN** | steps below. |
| A4-16 | cloudflared connected/ingress | docker/systemctl | **FAIL** | not deployed. |
| A4-17 | CF dashboard details | — | **NEEDS-HUMAN** | no token. |
| A4-18 | swarm 2377/7946/4789 exposure | ss/iptables | **FAIL** | F-08. |
| A4-19 | ip6tables DOCKER-USER | — | **FAIL** | F-09. |
| A5-01 | per-container matrix | docker inspect | **PASS** | all unprivileged, no host net, restart policies set, log rotation on, mem limits (no cpu limits). |
| A5-02 | docker.sock inventory | docker inspect | **WARN** | dockge rw, dokploy rw, dokploy-traefik ro. README says Dockge is read-only — it is not. |
| A5-03 | Hermes posture | — | **SKIPPED** | not deployed. |
| A5-04 | UI auth per app | curl each | **PASS** | sonarr/radarr/prowlarr 401 w/o key, bazarr 401, qbittorrent 403, jellyfin wizard (no admin yet), dockge 200, uptime 302. |
| A5-05 | arr auth not "disabled for local" | curl w/o key | **PASS** | all 401. |
| A5-06 | Jellyseerr | curl /setup | **FAIL** | open (F-20). |
| A5-07 | Jellyfin admin set | System/Info | **FAIL** | wizard open; Users table empty; no MaxActiveSessions applied. |
| A5-08 | Jellyfin QSV live | encoding.xml | **FAIL** | `none` (F-04). |
| A5-09 | Hermes dashboard auth | — | **SKIPPED** | not deployed. |
| A5-10 | Homepage auth | — | **PASS** | no auth by design; but link is broken (F-06). |
| A5-11 | Dockge auth | curl | **PASS** | / returns 200 (its own login on first use). |
| A5-12 | Uptime Kuma auth | curl / | **PASS/SKIPPED** | 302 to login; no admin created (F-07). |
| B1-01 | make check | run | **PASS** | only `get_url` (tailscale key) reports changed in check mode — benign. |
| B1-02 | make apply x2 → changed=0 | run twice | **PASS** | both runs `changed=0`. |
| B1-03 | tags work | docker/media/firewall/remove probe | **PASS/FAIL** | `--tags docker|media` work; README's `--tags firewall` and `--tags remove` are no-ops (F-43); `tasks/remove.yml` does not exist. |
| B1-04 | make verify | run | **PASS** | ok=55, 0 fail. |
| B1-05 | make lint / secrets-edit / deps | run | **PASS** | deps installs (duplicate collection versions, F-40); hooks now installed. |
| B2-01 | every service HTTPS over Tailscale | n/a | **SKIPPED** | no tunnel/DNS; tailscale client absent on Mac. |
| B2-02 | every service HTTPS over LAN | curl --resolve | **FAIL** | homepage 502 (F-06); hermes 502 (absent); others 200/302/307. |
| B2-03 | cert validity | openssl s_client | **FAIL** | Caddy Local Authority, 12 h, wildcard `*.home.sumitkpandit.in` (SAN OK). |
| B2-04 | renewal works | Caddy logs | **FAIL** | no ACME attempt (`tls internal`). |
| B2-05 | direct IP behaviour per README | curl 127.0.0.1 | **PASS** | all arr on 127.0.0.1 only; Caddy on the two IPs; qbittorrent WebUI on 127.0.0.1, torrent port on 192.168.0.2. |
| B2-06 | Homepage lists every service | curl / | **FAIL** | 502 behind Caddy. |
| B2-07 | Dockge sees all stacks | curl / | **PASS** | 200; `DOCKGE_STACKS_DIR=/opt/stacks` rw. |
| B3-01 | arr wiring | API calls | **PASS** | root folders, qBittorrent download client (host/port/user/pass set), Prowlarr↔Sonarr/Radarr fullSync, 6 quality profiles. |
| B3-02 | root folders writable/same paths | — | **PASS** | `/data/media/{tv,movies}` exist, device 66306. |
| B3-03 | Recyclarr | — | **FAIL** | absent. |
| B3-04 | Bazarr & Jellyseerr connected | API | **PASS/FAIL** | Bazarr config.xml not seeded but container healthy; Jellyseerr setup open. |
| B3-05 | health pages | probe | **PASS** | containers report healthy (docker healthchecks). |
| B3-06 | hardlink proof | `docker exec sonarr` | **PASS** | `/data/torrents/.audit-hltest` and `/data/media/movies/.audit-hltest` → same inode 29097992, links=2, cleaned up. |
| B3-07 | qbittorrent bound to LAN only | ss | **PASS** | 6881 on 192.168.0.2; WebUI on 127.0.0.1. |
| B3-08 | VPN path compose syntax | docker compose config | **FAIL** | invalid YAML (F-11). |
| B3-09 | /dev/dri in jellyfin | docker exec | **PASS** | renderD128 present, gid 991 (render) added. |
| B3-10 | real transcode via intel_gpu_top | — | **NEEDS-HUMAN** | needs a client; also blocked by F-04 (HW off). |
| B3-11 | two simultaneous transcodes | — | **NEEDS-HUMAN** | same. |
| B3-12 | per-user stream limit (correct field for pinned version) | Users table | **PASS/FAIL** | field name `MaxActiveSessions` is correct for v12; not applied because the wiring block is gated on an empty `jellyfin_admin_password` (F-04). |
| B4-01 | Hermes healthy/dashboard/OpenRouter/Telegram | — | **SKIPPED** | not deployed. |
| B4-02 | Dokploy UI LAN+Tailscale only | nmap | **PASS** | from LAN: 3000 filtered. |
| B4-03 | Dokploy admin exists | psql | **FAIL** | 0 users; no domains/apps (F-12). |
| B4-04 | deploy sample app + rollback | — | **NEEDS-HUMAN** | requires Dokploy UI + DNS; skipping. |
| B4-05 | DB/volumes in backups | — | **WARN** | dokploy-postgres is dumped via pg_dump and included; volumes excluded from restic; Dokploy app volumes are on named volumes (backed up). |
| B4-06 | GitHub webhook state | — | **NEEDS-HUMAN** | no webhook UI visible; recommend not enabling without approval. |
| B5-01 | Uptime Kuma monitors per service | — | **FAIL** | no admin, no monitors. |
| B5-02 | push monitors at ~85% | — | **FAIL** | tokens empty; timer disabled. |
| B5-03 | Telegram notifications | — | **FAIL** | token empty. |
| B5-04 | test notification | — | **NEEDS-HUMAN** | needs token. |

---

## Needs me (NEEDS-HUMAN)

1. **Cloudflare token + tunnel**: create a read/write DNS token for
   `sumitkpandit.in`, create a tunnel (`cloudflared tunnel create
   g3plus`), copy the token, and paste both into `make secrets-edit`.
   Without this, F-03/F-14 stay open and no public apps can exist.
2. **Tailscale on the Mac is missing**: install the Tailscale app/CLI on
   this Mac so the Tailscale half of every network check can be run; until
   then A4-10 and B2-01 are SKIPPED.
3. **Disable key expiry** for `g3plus` in the Tailscale admin console.
4. **Fill the remaining secrets** in `make secrets-edit`:
   `hermes_openrouter_api_key`, `hermes_telegram_bot_token`,
   `hermes_dashboard_password`, `telegram_chat_id`,
   `telegram_bot_token_uptime_kuma`, `uptime_kuma_disk_push_token`,
   `uptime_kuma_backup_push_token`, `jellyfin_admin_password`,
   `rclone_drive_token` (drive OAuth), and the VPN triple only if you want
   the VPN on.
5. **Google OAuth client**: create one at console.cloud.google.com with
   Publishing status "In production", then `rclone authorize "drive"` on
   the Mac and paste the token; a consumer's refresh token otherwise dies
   in ~7 days.
6. **Create the Dokploy admin account** at `http://192.168.0.2:3000`
   (or after F-03), create one domain + app, and confirm GitHub webhooks
   are OFF unless you explicitly want them.
7. **Create the Uptime Kuma admin** and confirm whether you want the
   README's monitor list to exist (or delete that claim).
8. **Phone test**: with Tailscale off on your phone, confirm none of
   `https://*.home.sumitkpandit.in` resolve; with it on, confirm they do;
   and confirm a public `<app>.sumitkpandit.in` loads through the tunnel
   while Jellyfin/admin names do not.
9. **Mobile-data test** for F-09: from the phone over the tailnet, confirm
   port 3000 is still gated (it should be, via the DOCKER-USER v4 rule).
10. **Idle temperature**: with BIOS high-performance mode, expect ~64 °C
    (F-26); decide whether to drop to a balanced profile or accept it.
11. **Jellyseerr/Bazarr**: finish `/setup` or accept that these are
    unconfigured.
12. **`make teardown` decision**: it will not run until F-01/F-02 are
    fixed; please confirm when you want me to rebuild it and re-run Stage C.

## Not verified (and why)

- **Tailscale-side reachability** from this Mac: no Tailscale client
  installed; all such checks are SKIPPED. Server-side, `tailscaled` is
  `BackendState=Running` and holds `100.88.141.33`.
- **Dokploy UI state (admin, webhooks, sample app, rollback)**: no
  admin user, no apps, no route; nothing to test.
- **Hermes end-to-end**: container absent; OpenRouter key absent.
- **Cloudflare Tunnel end-to-end**: connector absent; token empty.
- **Drive restore round-trip**: no token; only local restic snapshot exists.
- **Jellyfin transcoding**: HW is off (F-04); needs a real client stream and,
  after the fix, `intel_gpu_top` run.
- **Two simultaneous streams**: NEEDS-HUMAN.
- **`make verify-clean` against a real baseline**: baseline never captured.
- **Reboot recovery**: deliberately not done (Stage C).

---

## Changelog / cleanup record

- `curlimages/curl:latest` pulled once for an in-network probe and
  `docker rmi`'d; `docker images` confirms it is gone.
- pre-commit `end-of-file-fixer` edits to `ansible/ansible.cfg` and
  `.gitignore` were **reverted** (`git checkout`), tree is clean.
- Hardlink test artifacts `/data/torrents/.audit-hltest` and
  `/data/media/movies/.audit-hltest` were `rm`'d; one inode, links back to 1.
- `/tmp/vpncheck/` (rendered VPN compose) was removed after `docker compose
  config` proved it invalid.
- `/tmp/rebuild/*.json`, `/tmp/generate_commands.py`, `/home/sumit/.ansible`
  leftovers were *not* removed — they are part of finding F-30; tell me and I
  will clean.
- No server configuration was modified.
