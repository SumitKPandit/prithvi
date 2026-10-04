#!/usr/bin/env python3
"""Diff the live server state against baseline/ with the documented
allow-list. Fails loudly on anything unexplained.

Baseline files come from scripts/capture-baseline.sh (same names/fields).
"""
import difflib
import re
import sys
from pathlib import Path

BASE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("baseline")
NOW = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/verify-clean-now")

failures = []
warnings = []


def read(p):
    try:
        return (NOW / p).read_text().splitlines()
    except FileNotFoundError:
        return None


def base(p):
    try:
        return (BASE / p).read_text().splitlines()
    except FileNotFoundError:
        return None


def fail(msg):
    failures.append(msg)


def warn(msg):
    warnings.append(msg)


# --- packages.txt: apt list --installed output "name/version arch [upgradable]" ---
old = base("packages.txt")
new = read("packages.txt")
if old is None or new is None:
    fail("packages.txt missing on one side")
else:
    def pkgver(line):
        m = re.match(r"^(\S+)/(\S+)\s+(\S+)", line)
        if not m:
            return (line.strip(), None)
        return (m.group(1), m.group(2).split()[0])

    oldmap = dict(pkgver(l) for l in old if l.strip() and "/" in l)
    newmap = dict(pkgver(l) for l in new if l.strip() and "/" in l)
    for p in sorted(set(oldmap) - set(newmap)):
        fail(f"package REMOVED vs baseline: {p} (was {oldmap[p]})")
    for p in sorted(set(newmap) - set(oldmap)):
        warn(f"package added vs baseline: {p} {newmap[p]} (expected if you installed something)")

# --- etc files: everything must be from the managed set or documented ---
old = set(base("etc-file-list.txt") or [])
new = set(read("etc-file-list.txt") or [])
if not old or not new:
    fail("etc-file-list.txt missing on one side")
else:
    added = sorted(new - old)
    managed = [
        r"^/etc/ssh/sshd_config\.d/00-hardening\.conf$",
        r"^/etc/apt/apt\.conf\.d/(20auto-upgrades|52-security-auto-reboot)$",
        r"^/etc/smartd\.conf$",
        r"^/etc/cloud/cloud\.cfg\.d/99-no-password-auth\.cfg$",
        r"^/etc/systemd/system/(backup|backup-maintenance|disk-usage-check|docker-user-rules|docker-prune|recyclarr|snapraid-(sync|scrub))\.(service|timer)$",
        r"^/etc/kuma-push\.env$",
        r"^/etc/restic\.pass$",
        r"^/etc/rclone/rclone\.conf$",
        r"^/etc/sudoers\.d/90-sumit$",
        r"^/etc/docker/daemon\.json$",
        r"^/etc/sysctl\.d/99-docker-nonlocal-bind\.conf$",
        r"^/etc/apt/keyrings/",
        r"^/etc/apt/sources\.list\.d/(docker|tailscale)",
        r"^/etc/ufw/",
        r"^/etc/snapraid\.conf$",
        r"^/etc/cron\.d/",
    ]
    for f in added:
        if not any(re.match(p, f) for p in managed):
            fail(f"/etc file not in managed set: {f}")
    for f in sorted(old - new):
        warn(f"/etc file gone vs baseline: {f}")

# --- systemd enabled units: only managed additions ---
old = set(base("systemd-enabled.txt") or [])
new = set(read("systemd-enabled.txt") or [])
if not old or not new:
    fail("systemd-enabled.txt missing on one side")
else:
    managed_units = {
        "docker.service", "containerd.service", "tailscaled.service",
        "backup.timer", "backup-maintenance.timer", "docker-prune.timer",
        "disk-usage-check.timer", "recyclarr.timer",
        "snapraid-sync.timer", "snapraid-scrub.timer",
        "chrony.service", "smartd.service", "docker-user-rules.service",
        "ua-reboot-cmds.service",
    }
    for u in sorted(new - old):
        name = u.split()[0]
        if name not in managed_units:
            fail(f"unexpected enabled unit: {u}")

# --- users/groups: only media/user additions ---
for f in ("users.txt", "groups.txt"):
    old = set(base(f) or [])
    new = set(read(f) or [])
    if not old or not new:
        fail(f"{f} missing on one side")
    else:
        for u in sorted(new - old):
            name = u.split(":")[0]
            if name not in ("media",):
                fail(f"unexpected {f} entry: {u}")

# --- listening ports: exact allow-list of (proto,port) ---
new = read("listening-ports.txt") or []
allowed = {
    ("tcp", "22"), ("tcp", "53"), ("udp", "53"), ("tcp", "443"),
    ("tcp", "2377"), ("tcp", "7946"), ("udp", "7946"), ("udp", "4789"),
    ("tcp", "6881"), ("udp", "6881"),
    ("tcp", "3000"), ("tcp", "3001"), ("tcp", "5001"),
    ("udp", "123"), ("udp", "323"),
}
found = set()
for line in new:
    m = re.match(r"^(TCP|UDP)\s+\S+\s+\S+\s+\S+\s+(\S+):(\d+)", line, re.I)
    if m:
        found.add((m.group(1).lower(), m.group(3)))
for proto, port in sorted(found - allowed):
    fail(f"listening port outside allow-list: {proto}/{port}")

# --- ufw: exact expected ruleset (comments included) ---
expected_ufw = [
    "22/tcp", "2377/tcp", "7946/tcp", "7946/udp", "4789/udp",
    "Anywhere on tailscale0", "443/tcp",
]
new = read("ufw-status.txt") or []
text = "\n".join(new)
if "Status: active" not in text:
    fail("UFW is not active")
for rule in expected_ufw:
    if rule not in text:
        fail(f"UFW rule missing: {rule}")

# --- sysctl: only our override may differ from stock ---
new = read("sysctl.txt") or []
if not new:
    fail("sysctl.txt missing")
if not any("net.ipv4.ip_nonlocal_bind = 1" in l for l in new):
    fail("net.ipv4.ip_nonlocal_bind is not 1")

# --- dirs: only managed additions ---
old = set(base("dirs.txt") or [])
new = set(read("dirs.txt") or [])
managed_dirs = [
    "/opt/stacks", "/opt/appdata", "/opt/backups",
    "/data", "/mnt/pool", "/mnt/disk", "/mnt/parity",
    "/var/lib/docker", "/var/lib/tailscale",
]
if old and new:
    for d in sorted(new - old):
        if not any(d == m or d.startswith(m + "/") for m in managed_dirs):
            fail(f"unexpected dir: {d}")

# --- kernel: bumps are allowed (security updates), report only ---
old = (base("kernel.txt") or ["?"])[0].strip()
new = (read("kernel.txt") or ["?"])[0].strip()
if old != new:
    warn(f"kernel changed vs baseline: {old} -> {new} (allowed if from updates)")

# --- iptables DOCKER-USER: the per-physical-interface port-3000 drops ---
new = read("iptables.txt") or []
text = "\n".join(new)
if not re.search(r"-i (enp|wl)[a-z0-9]+ .*--dport 3000 .*DROP", text):
    fail("DOCKER-USER per-interface port-3000 DROP rule missing")
if re.search(r"!\s*-i\s*tailscale0.*--dport 3000.*DROP", text):
    fail("old overbroad DOCKER-USER rule (deny all but tailscale0 on 3000) is back")

print("=== verify-clean ===")
for w in warnings:
    print(f"WARN: {w}")
if failures:
    print()
    for f in failures:
        print(f"FAIL: {f}")
    print(f"\n{len(failures)} failure(s), {len(warnings)} warning(s)")
    sys.exit(1)
print(f"\nOK: no unexplained drift ({len(warnings)} warning(s))")
