# Prithvi

A private server only available over LAN. Access it on [lan.sumitkpandit.in](lan.sumitkpandit.in) when connected to home network.

## Domain Name System

Following A Records on Cloudflare direct traffic to local network.

| Name | IP |
|------|----|
| lan.sumitkpandit.in | 192.168.0.2 |
| *.lan.sumitkpandit.in | 192.168.0.2 |

192.168.0.2 is secured on router to point to Prithvi permanently.

## Services

### Services running on bare metal

- OpenSSH
- Docker
- Vim
- Git

### Services running in container

- Adguard Home
- Traefik
