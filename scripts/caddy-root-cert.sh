#!/bin/sh
# Export Caddy's internal root CA so macOS/iOS trust the private hostnames.
# Usage (from the repo root): make caddy-root-cert
# Then:
#   macOS: open the downloaded file -> Keychain Access -> System keychain ->
#     double-click "Caddy Local Authority" -> Trust -> "Always Trust".
#   iOS: AirDrop the file to the phone -> Settings -> Profile Downloaded ->
#     install -> Settings -> General -> About -> Certificate Trust Settings ->
#     enable full trust for "Caddy Local Authority".
# The CA lives only inside the caddy container's data volume; nothing secret
# outside this repo leaves the server except the PUBLIC root certificate.
set -eu
OUT="${1:-/tmp/caddy-local-root.crt}"
docker_cmd() { ssh g3plus "$@"; }
docker_cmd "sudo docker cp caddy:/data/caddy/pki/authorities/local/root.crt /tmp/caddy-local-root.crt && sudo chmod 644 /tmp/caddy-local-root.crt"
scp "g3plus:/tmp/caddy-local-root.crt" "$OUT"
docker_cmd "sudo rm -f /tmp/caddy-local-root.crt"
echo "Root CA saved to $OUT"
openssl x509 -in "$OUT" -noout -subject -issuer
