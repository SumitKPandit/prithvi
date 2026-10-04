#!/usr/bin/env bash
# Capture the baseline state of a FRESH Ubuntu 26.04 install.
# Run this ONCE on a throwaway VM or a genuinely fresh server, NOT on the
# already-provisioned g3plus. The output is committed to baseline/ in the repo.
# The baseline contains no secrets.
set -euo pipefail

BASELINE_DIR="${BASELINE_DIR:-$(cd "$(dirname "$0")/../baseline" && pwd)}"
mkdir -p "$BASELINE_DIR"

# Where we are running this (the fresh install)
HOST="${1:-localhost}"
OUT="$BASELINE_DIR"

echo "Capturing baseline from $HOST to $OUT"

# Helper to run commands on target
run() {
  if [[ "$HOST" == "localhost" ]]; then
    eval "$1"
  else
    ssh "$HOST" "$1"
  fi
}

# 1. Installed packages (manual vs automatic)
echo "==> Installed packages"
run "apt list --installed 2>/dev/null | sort" > "$OUT/packages.txt"
run "apt-mark showmanual 2>/dev/null | sort" > "$OUT/packages-manual.txt"
run "apt-mark showauto 2>/dev/null | sort" > "$OUT/packages-auto.txt"

# 2. /etc file list (excluding runtime state like /etc/ssh/ssh_host_*)
echo "==> /etc file list"
run "find /etc -type f | grep -vE '(/ssh/ssh_host_|/systemd/|/apt/|/cups/|/logrotate.d/)' | sort" > "$OUT/etc-file-list.txt"

# 3. Enabled systemd units and timers
echo "==> Systemd units/timers"
run "systemctl list-unit-files --state=enabled --no-legend | sort" > "$OUT/systemd-enabled.txt"
run "systemctl list-timers --all --no-legend | sort" > "$OUT/systemd-timers.txt"

# 4. Users and groups
echo "==> Users and groups"
run "getent passwd | sort" > "$OUT/users.txt"
run "getent group | sort" > "$OUT/groups.txt"

# 5. Listening ports
echo "==> Listening ports"
run "ss -H -tlnp 2>/dev/null | sort" > "$OUT/listening-ports.txt"

# 6. UFW status
echo "==> UFW status"
run "ufw status verbose 2>/dev/null || echo 'UFW not installed or inactive'" > "$OUT/ufw-status.txt"

# 7. Sysctl overrides (plus the single value verify-clean asserts)
echo "==> Sysctl overrides"
run "sysctl -a 2>/dev/null | grep -v '^net\\.ipv4\\.ip_nonlocal_bind' | sort; sysctl -n net.ipv4.ip_nonlocal_bind 2>/dev/null | sed 's/^/net.ipv4.ip_nonlocal_bind = /'" > "$OUT/sysctl.txt"

# 8. Files under /opt, /srv, /data, /var/lib (just structure, no contents)
echo "==> Directory structure under /opt /srv /data /var/lib"
run "find /opt /srv /data /var/lib /mnt -type d 2>/dev/null | sort" > "$OUT/dirs.txt"

# 9. Network links
echo "==> Network links"
run "ip link show | grep -E '^[0-9]+:' | sed 's/.*: \\([^:]*\\):.*/\\1/' | sort" > "$OUT/net-links.txt"

# 10. iptables rules (full)
echo "==> iptables rules"
run "iptables-save 2>/dev/null || iptables -L -n -v 2>/dev/null || echo 'iptables not available'" > "$OUT/iptables.txt"

# 11. Kernel version
echo "==> Kernel"
run "uname -r" > "$OUT/kernel.txt"

# 12. Disk layout
echo "==> Disk layout"
run "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,TYPE" > "$OUT/disk-layout.txt"

echo "Done. Baseline written to $OUT"
echo "Commit with: git add baseline && git commit -m 'baseline: fresh Ubuntu 26.04 state'"
