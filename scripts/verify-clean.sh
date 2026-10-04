#!/bin/sh
# verify-clean: fetch the live server state, diff it against baseline/ with
# the documented allow-list (fail loudly on anything unexplained).
# Run from the repo root.
set -eu
OUT=/tmp/verify-clean-now
rm -rf "$OUT"
mkdir -p "$OUT"

remote() {
  ssh g3plus "$1"
}

remote "apt list --installed 2>/dev/null | sort" > "$OUT/packages.txt"
remote "find /etc -type f | grep -vE '(/ssh/ssh_host_|/systemd/|/apt/|/cups/|/logrotate.d/)' | sort" > "$OUT/etc-file-list.txt"
remote "systemctl list-unit-files --state=enabled --no-legend | sort" > "$OUT/systemd-enabled.txt"
remote "getent passwd | sort" > "$OUT/users.txt"
remote "getent group | sort" > "$OUT/groups.txt"
remote "ss -H -tlnp 2>/dev/null | sort" > "$OUT/listening-ports.txt"
remote "sudo ufw status numbered 2>/dev/null || ufw status 2>/dev/null || echo 'UFW not installed or inactive'" > "$OUT/ufw-status.txt"
remote "sysctl -a 2>/dev/null | grep -v '^net\.ipv4\.ip_nonlocal_bind' | sort; sysctl -n net.ipv4.ip_nonlocal_bind | sed 's/^/net.ipv4.ip_nonlocal_bind = /'" > "$OUT/sysctl.txt"
remote "find /opt /srv /data /var/lib /mnt -type d 2>/dev/null | sort" > "$OUT/dirs.txt"
remote "uname -r" > "$OUT/kernel.txt"
remote "sudo iptables-save 2>/dev/null" > "$OUT/iptables.txt"

python3 scripts/verify-clean.py baseline "$OUT"
