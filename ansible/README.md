# Ansible

This directory contains the Infrastructure as Code (IaC) used to provision and manage the Prithvi server.

## Purpose

Ansible is responsible for configuring the operating system. It manages the host itself rather than the applications running on it.

Examples include:

* Installing system packages
* Configuring Docker Engine
* Managing users and groups
* Hardening SSH
* Configuring the firewall
* Applying system configuration
* Creating required directories
* Managing system services

Application deployment is intentionally **not** handled here. Containerized applications are defined separately under the `compose/` directory.

## Design Principles

* Declarative configuration
* Idempotent execution
* Git as the source of truth
* No manual server configuration after bootstrap
* Repeatable provisioning from a clean Ubuntu installation

## Repository Layout

This directory will grow as the project evolves. Typical contents include:

* Inventories
* Playbooks
* Roles
* Variables
* Templates

Directories are created only when they contain meaningful content.

## Goal

A freshly installed Ubuntu Server should become a fully configured host by executing a single Ansible playbook from a control machine.
