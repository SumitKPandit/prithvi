#!/usr/bin/env bash
set -euo pipefail
# Docker from Ubuntu's own packages
sudo apt-get install -y docker.io docker-compose-v2

# run docker without sudo (applies at next login)
sudo usermod -aG docker "$USER"

# cap container logs: 3 files x 10 MB each
sudo tee /tmp/daemon.json >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
# restart Docker only if the config actually changed
if ! sudo cmp -s /tmp/daemon.json /etc/docker/daemon.json; then
  sudo install -m 0644 /tmp/daemon.json /etc/docker/daemon.json
  sudo systemctl restart docker
fi
# Undo: sudo apt purge docker.io docker-compose-v2