# Prithvi

Prithvi is a self-hosted platform built using Infrastructure as Code principles.

The project aims to provide a reproducible, production-inspired environment for running self-hosted services while following modern platform engineering practices.

## Objectives

* Infrastructure defined as code
* Git as the single source of truth
* Automated provisioning
* Declarative application deployment
* Secure remote administration
* Reliable disaster recovery
* Scalable architecture

## Technology Stack

| Layer                    | Technology                          |
| ------------------------ | ----------------------------------- |
| Operating System         | Ubuntu Server 26.04 LTS             |
| Configuration Management | Ansible                             |
| Container Runtime        | Docker Engine                       |
| Application Deployment   | Docker Compose                      |
| Reverse Proxy            | Traefik (planned)                   |
| Authentication           | Authentik (planned)                 |
| Monitoring               | Prometheus, Grafana, Loki (planned) |
| Backup                   | Restic or Kopia (planned)           |
| Remote Access            | Tailscale (planned)                 |

## Project Philosophy

This project intentionally avoids manual server configuration.

The desired workflow is:

1. Install Ubuntu Server.
2. Clone this repository.
3. Provision the host using Ansible.
4. Deploy applications using Docker Compose.
5. Restore application data if required.

The repository should contain everything necessary to recreate the platform except runtime data and encrypted secrets.

## Repository Structure

```text
ansible/    Infrastructure provisioning
compose/    Containerized applications
docs/       Project documentation
.github/    CI/CD workflows
```

## Current Status

The project is under active development.

The current focus is establishing a reproducible platform foundation before deploying services.

## Long-Term Goal

A complete server rebuild should require only:

* A fresh Ubuntu installation
* Access to this repository
* Encrypted secrets
* Application backups

Everything else should be recreated automatically.
