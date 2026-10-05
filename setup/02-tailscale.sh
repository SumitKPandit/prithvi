#!/usr/bin/env bash
set -euo pipefail
curl -fsSL https://tailscale.com/install.sh | sh
# Login is interactive, so do it by hand once:
#   sudo tailscale up --hostname=g3plus
# Undo: sudo tailscale logout && sudo apt purge tailscale