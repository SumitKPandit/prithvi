#!/usr/bin/env bash
# One-time secrets setup on the Mac:
#   1. create the age key OUTSIDE the repo (~/.config/sops/age/keys.txt)
#   2. write .sops.yaml (public key only; safe to commit)
#   3. create ansible/secrets.sops.yaml from the example, generating the
#      internal API keys that don't come from you
#
# The age private key is the one thing this repo cannot recreate. Back it up
# (password manager, USB stick). Without it the encrypted secrets are unreadable.
set -euo pipefail

# sops on macOS looks for age keys here by default (Linux uses ~/.config/sops/age)
AGE_DIR="${HOME}/Library/Application Support/sops/age"
AGE_KEY="${AGE_DIR}/keys.txt"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SOPS_YAML="${REPO}/.sops.yaml"
SECRETS="${REPO}/ansible/secrets.sops.yaml"

if ! command -v sops >/dev/null || ! command -v age >/dev/null; then
  echo "ERROR: install sops and age first: brew install sops age" >&2
  exit 1
fi

mkdir -p "${AGE_DIR}"
if [[ ! -f "${AGE_KEY}" ]]; then
  age-keygen -o "${AGE_KEY}" >/dev/null
  chmod 0600 "${AGE_KEY}"
  echo "Created ${AGE_KEY} -- back this file up, it decrypts your secrets."
fi
PUB="$(age-keygen -y "${AGE_KEY}")"

if [[ ! -f "${SOPS_YAML}" ]]; then
  cat > "${SOPS_YAML}" <<EOF
---
# Encrypt ansible/secrets.sops.yaml with age. Only the public key lives here;
# the private key is ~/.config/sops/age/keys.txt on your Mac (never committed).
creation_rules:
  - path_regex: secrets\\.sops\\.yaml$
    age: ${PUB}
EOF
  echo "Wrote .sops.yaml"
fi

if [[ ! -f "${SECRETS}" ]]; then
  TMP="$(mktemp)"
  # internal_* keys and the restic repository password are machine secrets,
  # so we generate them.
  python3 - "$REPO/ansible/secrets.example.yaml" "$TMP" <<'PY'
import secrets as s, sys, re
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
def gen(key):
    v = s.token_hex(24) if "password" not in key else s.token_urlsafe(18)
    return re.sub(rf'^(internal_{key}: ).*$', rf'\g<1>"{v}"', text, flags=re.M)
for k in ("sonarr_api_key", "radarr_api_key", "prowlarr_api_key", "bazarr_api_key",
          "jellyseerr_api_key", "qbittorrent_admin_password", "restic_repository_password"):
    text = gen(k)
open(dst, "w").write(text)
PY
  mv "$TMP" "$SECRETS"
  sops --encrypt --in-place "$SECRETS"
  echo "Created and encrypted ${SECRETS}"
else
  sops -d "$SECRETS" >/dev/null  # fail loudly if this Mac lacks the matching age key
  echo "${SECRETS} already exists and decrypts fine."
fi
