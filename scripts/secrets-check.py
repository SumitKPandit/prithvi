#!/usr/bin/env python3
"""Report which secrets are empty (names only, never values) and which
deployments depend on them. Reads decrypted YAML on stdin."""
import sys

notes = {
    'tailscale_auth_key': 'Tailscale registration without a manual login',
    'cloudflare_api_token': 'DNS records for *.home.*, real LetsEncrypt certs',
    'cloudflare_tunnel_token': 'the cloudflared connector (public apps)',
    'telegram_bot_token_uptime_kuma': 'Uptime Kuma alerts to your chat',
    'telegram_chat_id': 'which chat Telegram bots are allowed to talk to',
    'uptime_kuma_disk_push_token': 'disk-usage-check.timer (alert at 85%)',
    'uptime_kuma_backup_push_token': 'backup result pushed to Uptime Kuma',
    'hermes_openrouter_api_key': 'the Hermes role deploys at all',
    'hermes_telegram_bot_token': 'Hermes proactive Telegram messages',
    'hermes_dashboard_password': 'Hermes dashboard login',
    'vpn_provider': 'VPN kill switch for the media stack',
    'vpn_username': 'VPN kill switch for the media stack',
    'vpn_password': 'VPN kill switch for the media stack',
    'rclone_drive_token': 'off-site Google Drive backup',
    'jellyfin_admin_password': 'Jellyfin wizard finishes automatically (admin, libraries, QSV)',
    'restic_repository_password': 'local restic repo',
    'internal_sonarr_api_key': 'Sonarr API access from this repo',
    'internal_radarr_api_key': 'Radarr API access from this repo',
    'internal_prowlarr_api_key': 'Prowlarr API access from this repo',
    'internal_bazarr_api_key': 'Bazarr API access from this repo',
    'internal_jellyseerr_api_key': 'Jellyseerr API access from this repo',
    'internal_qbittorrent_admin_password': 'qBittorrent WebUI login',
    'jellyfin_admin_username': 'Jellyfin admin username',
}

data = {}
for line in sys.stdin:
    line = line.rstrip('\n')
    if not line or line.startswith('#') or ':' not in line:
        continue
    k, _, v = line.partition(':')
    v = v.strip()
    if v and v[0] in '"\'':
        v = v[1:-1]
    data[k.strip()] = v

print('=== Secrets status (names only, never values) ===')
for k in sorted(data):
    is_empty = data[k] is None or data[k].strip() == ''
    tag = 'EMPTY' if is_empty else 'set  '
    print(f'{tag} {k}: {notes.get(k, "no note")}')

gated = [
    ('hermes role deploys', 'hermes_openrouter_api_key'),
    ('tunnel role deploys', 'cloudflare_tunnel_token'),
    ('DNS records + real certs', 'cloudflare_api_token'),
    ('Drive off-site backup', 'rclone_drive_token'),
    ('Jellyfin auto-wizard', 'jellyfin_admin_password'),
    ('disk-usage-check.timer', 'uptime_kuma_disk_push_token'),
    ('Uptime Kuma backup push monitor', 'uptime_kuma_backup_push_token'),
    ('Uptime Kuma Telegram alerts', 'telegram_bot_token_uptime_kuma'),
    ('Hermes Telegram', 'hermes_telegram_bot_token'),
    ('VPN media stack', 'vpn_provider'),
    ('backup role (restic)', 'restic_repository_password'),
]
print()
print('=== Silently off because its secret is empty ===')
for what, key in gated:
    missing = data.get(key) is None or data.get(key, '').strip() == ''
    if missing:
        print(f'SKIPPED: {what} (missing {key})')
