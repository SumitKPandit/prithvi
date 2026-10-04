#!/usr/bin/env python3
"""Print /etc/hosts lines so a Mac can reach the private hostnames without
DNS. Pick the block that matches the network you are on:

- LAN: point them at 192.168.0.2 (works on the home wifi only)
- Tailscale: point them at 100.88.141.33 (works anywhere the tailnet reaches)
Caddy proxies all of these; browsers still warn until the internal root CA
is trusted (see `make caddy-root-cert`).
"""
lan = "192.168.0.2"
tailscale = "100.88.141.33"
names = [
    "jellyfin", "sonarr", "radarr", "prowlarr", "bazarr", "jellyseerr",
    "qbittorrent", "uptime", "dockge", "homepage", "hermes",
]
suffix = "home.sumitkpandit.in"
print("# LAN block (home wifi only):")
for n in names:
    print(f"{lan} {n}.{suffix}")
print()
print("# Tailscale block (anywhere on the tailnet) - use ONE block only:")
for n in names:
    print(f"# {tailscale} {n}.{suffix}")
