## Adguard Home

Adguard Home serves as the private DNS server which blocks ads and trackers throughout local network.

Adguard Home dashboard can be accessed on [adguard.lan.sumitkpandit.in](adguard.lan.sumitkpandit.in).

## Installation Steps

1. SSH into the private server
2. Clone this repository
3. Change directory to `./prithvi/adguard-home/`
4. Start the service
```bash
docker compose up -d
```
5. Navigate to <private-server-ip>:3001 on browser to complete initial setup
6. After completing initial step, navigate to <private-server-ip>:8001 for Adguard Home dashboard

If you're also running Traefik, traefik will find the service and try to relsolve [adguard.lan.sumitkpandit.in](adguard.lan.sumitkpandit.in) to Adguard Home Dashboard. For this to work, proper A Records must be set on TLD Domain Name Server.