# Prithvi homeserver

Phase 1: Docker + Uptime Kuma only. The full previous setup lives on the `full-draft` branch.

## Run

    ansible-galaxy collection install community.docker   # once
    ansible-playbook -i 192.168.0.2, -K ansible/site.yml

## Verify

- Run the playbook twice; the second run must report `changed=0`.
- Open http://192.168.0.2:3001 — Uptime Kuma — and confirm it still loads after a server reboot.
- `/mnt/data` does not exist yet; a data drive will be mounted there when Jellyfin/qBittorrent arrive.
