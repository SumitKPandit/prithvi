#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu install so Ansible can take over.
# Single manual step after installing Ubuntu: `make bootstrap` from the Mac.
#
# Why this exists: Ubuntu 26.04 ships sudo-rs, whose password prompt Ansible's
# become does not recognize, so Ansible cannot escalate with a password. We
# install the SSH public key and create the passwordless-sudo file manually in
# one TTY session; the `base` role keeps the file correct afterwards.
set -euo pipefail

HOST="${1:-g3plus}"   # uses ~/.ssh/config entry (HostName 192.168.0.2, User sumit)
KEY="${HOME}/.ssh/sumit_g3plus"

if [[ ! -f "${KEY}" ]]; then
  echo "ERROR: ${KEY} not found. Generate it first:"
  echo "  ssh-keygen -t ed25519 -f ${KEY}"
  exit 1
fi

echo "==> Step 1/3: install SSH public key (will ask for the password once)"
# If key login already works, BatchMode ssh succeeds and we skip ssh-copy-id.
if ! ssh -o BatchMode=yes "${HOST}" true 2>/dev/null; then
  ssh-copy-id -i "${KEY}.pub" "${HOST}"
fi

echo "==> Step 2/3: passwordless sudo for ${HOST} (one sudo password prompt)"
# Only writes the file if passwordless sudo is not already working.
ssh -t "${HOST}" 'sudo -n true 2>/dev/null || { echo "sumit ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-sumit >/dev/null && sudo chmod 0440 /etc/sudoers.d/90-sumit && sudo visudo -cf /etc/sudoers.d/90-sumit; }'

echo "==> Step 3/3: checking Ansible can reach the host"
cd "$(dirname "$0")/../ansible" && ansible "${HOST#*@}" -m ping

echo "Bootstrap done. Next: make secrets-init, make secrets-edit, make apply."
