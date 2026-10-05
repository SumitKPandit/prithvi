# g3plus home server

Notes and scripts to rebuild my home server from a fresh Ubuntu install. The rule of this repo: **every step is a short script or a short compose file that I have read and run by hand.** No tools I don't understand, nothing hidden.

## Hardware

- GMKtec NucBox G3 Plus: Intel N150, 16 GB RAM, 512 GB NVMe
- Quick Sync GPU (`/dev/dri`) for Jellyfin transcoding later
- Ethernet port (2.5GbE capable) and Wi-Fi

## How the pieces are layered

| Layer | What lives there | Here |
|---|---|---|
| Hardware | physical parts, BIOS | the NucBox |
| OS | kernel, drivers, users, disks | Ubuntu Server 26.04 (minimal) |
| Host services | things that must work without Docker | SSH, Tailscale, Docker itself |
| Container runtime | runs and isolates containers | Docker + Compose (Ubuntu's own packages) |
| Containers | one app each, defined by a compose file | Jellyfin, etc. (see `services/`) |

Rule of thumb: keep the host small and boring. Everything else is a container, so `docker compose down` removes it cleanly. Things that change the host itself (disk mounts, firewall, Docker's config) stay on the host.

## Layout

```
homelab/
├── README.md
├── setup/                 # host setup, one script per step, run in order
│   ├── 01-base.sh         # updates, nano, htop, tmux
│   ├── 02-tailscale.sh    # Tailscale (login is manual)
│   └── 03-docker.sh       # Docker, no-sudo group, log size cap
└── services/              # one folder per service (added step by step)
    └── <name>/compose.yaml
```

## Manual steps (cannot be scripted)

Do these once, and again after any reinstall.

1. **BIOS:** set "Restore on AC Power Loss" to Power On. Choose a performance mode (leaving it off keeps idle power and heat lower; stress tests showed no throttling without it).
2. **Install Ubuntu Server (minimal) from USB:**
   - storage: whole disk, plain ext4, no LVM
   - hostname `g3plus`, user `sumit`
   - install OpenSSH server
   - select no snaps
   - plug in Ethernet during install if possible
3. **Router:** create a DHCP reservation so the server keeps its address. Ethernet hardware address: `e0:51:d8:1e:75:68`. (Wi-Fi has a different one.) Find the current address on the server with `ip -br addr`.
4. **SSH key from the Mac:**
   ```bash
   ssh-keygen -R <server-address>          # clears the old host key after a reinstall
   ssh-copy-id -i ~/.ssh/sumit_g3plus.pub sumit@<server-address>
   ```
   `~/.ssh/config` on the Mac:
   ```
   Host g3plus
       HostName <server-address>
       User sumit
       IdentityFile ~/.ssh/sumit_g3plus
       IdentitiesOnly yes
   ```
5. **Tailscale login** (after running `02-tailscale.sh`):
   ```bash
   sudo tailscale up --hostname=g3plus
   ```
   Open the link it prints and sign in. Then, in the Tailscale admin console: delete any old `g3plus` entry first, and choose **Disable key expiry** for the new one.
6. **Take a baseline** right after the install and updates (see below).

## Running the setup scripts

From the Mac, in this repo:

```bash
scp -r setup sumit@g3plus:~/
ssh -t sumit@g3plus 'bash setup/01-base.sh'
ssh -t sumit@g3plus 'bash setup/02-tailscale.sh'
ssh -t sumit@g3plus 'bash setup/03-docker.sh'
```

`-t` gives `sudo` a terminal to ask for your password. Scripts are written to be safe to re-run (a second run should change nothing). **They have not yet been tested from a clean install**; the first real test is the next reinstall.

After `03-docker.sh`, log out and back in so the `docker` group applies, then check:

```bash
id                          # should list docker
docker run --rm hello-world
```

## Know what each step changed

Before installing anything new, record the current state:

```bash
mkdir -p ~/baseline && cd ~/baseline
dpkg-query -W -f='${Package}\n' | sort > packages.txt
systemctl list-unit-files --state=enabled > services.txt
sudo ss -tulpn > ports.txt
ip -br addr > network.txt
```

After a step, compare:

```bash
dpkg-query -W -f='${Package}\n' | sort | diff ~/baseline/packages.txt -
systemctl list-unit-files --state=enabled | diff ~/baseline/services.txt -
sudo ss -tulpn | diff ~/baseline/ports.txt -
ip -br addr | diff ~/baseline/network.txt -
```

Lines starting with `>` were added, `<` were removed, and no output means nothing changed. To see every package install ever made on this machine:

```bash
grep -E "Start-Date|Commandline" /var/log/apt/history.log
```

## Watching resources

```bash
free -h            # memory
htop               # live CPU and memory per process
docker stats       # live CPU and memory per container
docker system df   # disk used by images, containers, volumes
df -h /            # disk free
sensors            # temperatures (install lm-sensors first)
```

## What each step changes on the host

- **01-base:** installs Ubuntu packages (updates, nano, htop, tmux). Undo: `sudo apt purge nano htop tmux`.
- **02-tailscale:** adds Tailscale's apt repo (`/etc/apt/sources.list.d/tailscale.list`), installs the `tailscale` package, enables the `tailscaled` service. Undo: `sudo tailscale logout && sudo apt purge tailscale`, then delete the `tailscale.list` file.
- **03-docker:** installs `docker.io`, `docker-compose-v2` and dependencies from Ubuntu's repos; creates the `docker` group and a `docker0` bridge; adds the user to the `docker` group (members can effectively act as root on this machine); writes `/etc/docker/daemon.json` (container logs capped at 3 files of 10 MB); Docker manages its own firewall rules. Undo: `sudo apt purge docker.io docker-compose-v2`. To also delete all images and data: `sudo rm -rf /var/lib/docker` (destructive).

## Rules for adding a service

1. Create `services/<name>/compose.yaml`. One folder per service.
2. Keep the data in a visible folder (a bind mount, for example `/srv/<name>`), not in a hidden named volume.
3. Pin image versions (no `:latest`).
4. Bind ports to a specific address where possible, and never port-forward on the router. Reach services over Tailscale.
5. Run it with `docker compose up -d` and remove it with `docker compose down`.
6. Take a baseline before, compare after, and write down any host-level change here.

## Not decided yet

- Reverse proxy and HTTPS names for services (nothing needed until there is more than one web UI)
- Backups (start simple: copy config folders; later maybe restic to an external drive or cloud)
- SSH hardening (key-only login) once key login is proven from every device I use
- Firewall (ufw): note that Docker-published ports bypass ufw, so bind ports to specific addresses instead of relying on it
- NAS storage (external drives, SnapRAID/mergerfs) when the hardware arrives
- AI agent and web app hosting, after the media services work

## Progress

- [x] Fresh Ubuntu Server (minimal), SSH with key
- [x] Tailscale installed and logged in
- [ ] Docker installed and tested
- [ ] Jellyfin with Quick Sync
- [ ] Download tools, one at a time
- [ ] Backups
- [ ] AI agent
- [ ] Web apps