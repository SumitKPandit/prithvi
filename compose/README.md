# Docker Compose

This directory contains the application definitions for the Prithvi platform.

## Purpose

Docker Compose is responsible for deploying and managing containerized services.

Infrastructure provisioning belongs to Ansible.

Application lifecycle management belongs to Docker Compose.

## Design Principles

* One compose project per logical stack
* Minimal coupling between stacks
* Reproducible deployments
* Configuration stored in Git
* Persistent application data stored outside the repository

## Planned Stacks

As the platform evolves, compose projects will be added for services such as:

* Reverse proxy
* Authentication
* Media services
* Monitoring
* Logging
* Backup

Each stack will have its own directory containing its Compose specification and any supporting configuration.

## Goal

Application deployments should be reproducible using the Docker Compose Specification without requiring manual configuration on the server.
