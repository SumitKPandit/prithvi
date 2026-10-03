# g3plus home server

Infrastructure-as-code for a private home server (GMKtec NucBox G3 Plus: Intel N150, 16 GB RAM, 512 GB NVMe, Ubuntu Server 26.04 LTS).

The goal: anything configured on the server is described in this repo, so the server can be rebuilt from a fresh Ubuntu install.

- **Ansible** configures the host: packages, groups, sudo, Docker, and later Tailscale, firewall and SSH hardening.
- **Docker Compose** (planned, under `stacks/`) defines the services: Arr stack, qBittorrent, Jellyfin, reverse proxy, AI agent, web apps.

## Layout

```
.
├── README.md
└── ansible/
    ├── ansible.cfg              # points Ansible at inventory.yml
    ├── inventory.yml            # the server: address, user, SSH key
    ├── site.yml                 # the play: which roles run on which host
    └── roles/
        ├── base/
        │   └── tasks/main.yml   # admin tools, GPU groups, passwordless sudo
        └── docker/
            ├── tasks/main.yml   # Docker apt repo, packages, service, docker group
            └── handlers/main.yml
```

A role is a folder of tasks for one job. `site.yml` lists roles in the order they run. Handlers run only when a task reports a change (for example, refreshing apt after the Docker repo is added).

## Prerequisites (on the Mac)

```bash
brew install ansible
```

SSH key for the server, with this entry in `~/.ssh/config`:

```
Host g3plus
    HostName 192.168.0.2
    User sumit
    IdentityFile ~/.ssh/sumit_g3plus
    IdentitiesOnly yes
```

Install the public key on the server once:

```bash
ssh-copy-id -i ~/.ssh/sumit_g3plus.pub sumit@192.168.0.2
```

## Manual steps outside this repo

These cannot be automated from Ansible. Redo them when rebuilding.

1. **BIOS:** set "Restore on AC Power Loss" to Power On, and enable GMKtec high-performance mode. If idle CPU temperature creeps toward 60 °C, turn high-performance mode back off.
2. **Router:** DHCP reservation of `192.168.0.2` for the server (Wi-Fi interface `wlp1s0`). Ethernet (`enp3s0`) needs its own reservation if used later.
3. **Ubuntu install:** Ubuntu Server 26.04 LTS on the whole NVMe (ext4, no LVM, no encryption), hostname `g3plus`, user `sumit`, OpenSSH enabled.
4. **Passwordless sudo bootstrap (first run only).** Ubuntu 26.04 uses `sudo-rs`, whose password prompt Ansible does not recognize, so Ansible cannot escalate with a password. On a fresh install, run this once on the server:

   ```bash
   echo 'sumit ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-sumit
   sudo chmod 440 /etc/sudoers.d/90-sumit
   ```

   After that, the `base` role keeps this file correct.
5. **Ghostty terminal:** if tmux or other programs misbehave over SSH, run `export TERM=xterm-256color`, or install the terminfo from the Mac:

   ```bash
   infocmp -x xterm-ghostty | ssh sumit@192.168.0.2 -- tic -x -
   ```

## Usage

Run everything from the `ansible/` folder.

Check the connection:

```bash
ansible g3plus -m ping
```

Dry run (shows what would change, changes nothing):

```bash
ansible-playbook site.yml --check --diff
```

Apply for real:

```bash
ansible-playbook site.yml --diff
```

Run it twice. The second run should report `changed=0`. That is how you know the playbook is idempotent and matches the server.

Notes on dry runs: `--check` cannot fully simulate a fresh install. Tasks that depend on earlier changes (a package from a newly added repo, a group created by a package) may fail in check mode even though the real run works.

After `docker` or GPU group changes, reconnect SSH so the new groups apply.

## Verify the server

```bash
ssh g3plus 'groups; docker --version; docker compose version; docker run --rm hello-world'
ssh g3plus 'vainfo'    # should list the iHD driver and VA-API profiles
```

## Adding something new

- **A host-level change** (package, service, config file): add a task to an existing role, or create `ansible/roles/<name>/tasks/main.yml` and add `- <name>` under `roles:` in `site.yml`.
- **A service** (planned): add `stacks/<name>/compose.yaml`.
- Test with `--check --diff` first, then apply, then run again to confirm `changed=0`.

## Secrets (planned)

API keys and VPN credentials will be encrypted with SOPS and age before being committed. Plain `.env` files must never be committed. The age private key is kept outside the repo and backed up separately.

## Roadmap

1. Host foundation: SSH hardening (key-only login), UFW firewall, automatic security updates, Tailscale for remote access.
2. Media: Gluetun VPN with qBittorrent, Prowlarr, Sonarr, Radarr, Jellyfin with Quick Sync (`/dev/dri`), Dockge, Uptime Kuma.
3. Reverse proxy (Caddy or Traefik) and a repeatable pattern for deploying web apps.
4. 24/7 AI agent container using an external LLM API.
5. NAS: powered enclosure with CMR 3.5" drives, SnapRAID plus mergerfs, and a separate backup. The bus-powered Seagate portable drives were ruled out (bus-powered, likely SMR, not built for 24/7).

## Hardware notes

- Intel N150 with Quick Sync: H.264, HEVC 8/10-bit and VP9 encode and decode, AV1 decode only.
- Power: Artis PS-600VA UPS for the mini PC and drive enclosure. It likely has no USB data port, so there is no automatic shutdown on power loss.
- Secure Boot key updates (UEFI CA 2011 to 2023, dbx revocations) are available via `fwupdmgr` and are optional. Apply them with a screen and keyboard attached; if boot fails, temporarily disable Secure Boot in the BIOS.