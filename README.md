# Prithvi

Private home server (GMKtec G3 Plus, `g3plus`). LAN-only at [lan.sumitkpandit.in](https://lan.sumitkpandit.in).

## Rebuild (one command)

After Ubuntu reinstall + SSH key added:

```bash
make server
```

What it does: Ansible (from this Mac) hardens SSH, firewall, upgrades, Docker, Tailscale, then deploys all Compose stacks. Prompts for sudo password once.

Preview without changes:

```bash
make check
```

## Layout

- `ansible/` — inventory, `site.yml`, roles, `group_vars/all/vault.yml` (encrypted secrets)
- `<service>/compose.yml` — source of truth, synced to `/srv/stacks/<stack>/`
- Runtime data — `/srv/appdata/<stack>/` (never rsynced with `--delete`)
- Media — `/mnt/data` (NVMe for now; future mergerfs pool mounts here unchanged)
- `.vault-pass` — gitignored vault password so `make` never prompts

Secrets: `make vault-edit` (needs `.vault-pass`). Tailscale uses a reusable tagged auth key in the vault.

## DNS

Cloudflare A records to `192.168.0.2` (router DHCP reservation):

| Name | IP |
|------|----|
| lan.sumitkpandit.in | 192.168.0.2 |
| *.lan.sumitkpandit.in | 192.168.0.2 |

## Ghostty over SSH

```bash
export TERM=xterm-256color
```

Or install terminfo once:

```bash
infocmp -x xterm-ghostty | ssh sumit@192.168.0.2 -- tic -x -
```

## Notes

- Tailscale runs as a host package (survives Docker failures), not a container.
- `sumit` is added to `render`/`video` for Jellyfin Quick Sync (`/dev/dri/renderD128`).
- IaC rebuilds config, not data — `/srv/appdata` backup is still TODO.
- Set `mnt_data_require_mount: true` in `ansible/group_vars/all.yml` once the NAS pool exists, so stacks fail instead of writing media to NVMe.
