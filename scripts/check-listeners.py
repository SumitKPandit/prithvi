#!/usr/bin/env python3
"""Assert no listening socket falls outside the documented allow-list.

Loopback-bound compose ports are all fine; everything else must be named
here. tailscaled's own sockets are ephemeral, matched by owner + address.
Usage: check-listeners.py <tailscale_ip> <lan_ip>; exits 1 listing offenders.
"""
import re
import subprocess
import sys

ts_ip, lan = sys.argv[1], sys.argv[2]
out = subprocess.run(["ss", "-H", "-tlnp"], capture_output=True, text=True).stdout
out += subprocess.run(["ss", "-H", "-ulnp"], capture_output=True, text=True).stdout
bad = []
for line in out.splitlines():
    m = re.match(r"^(TCP|UDP)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+(.*)$", line, re.I)
    if not m:
        continue
    proto, local, rest = m.group(1).lower(), m.group(2), m.group(3)
    addr, _, port = local.rpartition(":")
    addr = addr.strip("[]").split("%")[0]
    procs = re.findall(r'\("([^",]+)"', rest)
    ok = False
    if addr.startswith("127.") or addr == "::1":
        ok = True  # loopback-only bindings (compose publishes)
    elif addr == ts_ip and proto == "tcp" and (port == "443" or (port.isdigit() and int(port) >= 32768)):
        ok = True  # Caddy 443 + tailscaled's ephemeral local API
    elif addr.startswith("fd7a:") and proto == "tcp" and port.isdigit() and int(port) >= 32768:
        ok = True  # tailscaled v6 local API
    elif addr in ("0.0.0.0", "::", "*") and proto == "tcp" and port in ("22", "53", "3000", "2377", "7946"):
        ok = True  # ssh, resolver stub, dokploy (DOCKER-USER-gated), swarm (UFW-denied)
    elif addr in ("0.0.0.0", "::", "*") and proto == "udp" and port in ("53", "4789", "7946", "41641"):
        ok = True  # resolver stub, swarm overlay/member (UFW-denied), tailscaled wg
    elif addr == lan and proto == "tcp" and port in ("443", "6881"):
        ok = True  # Caddy HTTPS, qBittorrent torrent port
    elif addr == lan and proto == "udp" and port in ("6881", "68"):
        ok = True  # qBittorrent torrent port, DHCP client
    elif addr == "127.0.0.54" and proto == "udp" and port == "53":
        ok = True  # systemd-resolved stub
    if not ok:
        bad.append(f"{proto} {addr}:{port} procs={procs or ['?']}")
if bad:
    print("BAD LISTENERS:")
    print("\n".join(bad))
    sys.exit(1)
print("listeners OK")
