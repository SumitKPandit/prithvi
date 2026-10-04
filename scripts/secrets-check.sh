#!/bin/sh
# List the secrets that are EMPTY, by name only, with a one-line note on
# what each unlocks. Never prints a value. Run from the repo root.
set -eu
sops -d ansible/secrets.sops.yaml | python3 scripts/secrets-check.py
