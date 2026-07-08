# Architecture

## Overview

Prithvi is a self-hosted platform built using Infrastructure as Code principles.

The objective is to make the server reproducible, maintainable, and recoverable from source control.

## Architecture Layers

```
GitHub Repository
        │
        ▼
GitHub Actions
        │
        ▼
Ansible
        │
        ▼
Ubuntu Server
        │
        ▼
Docker Engine
        │
        ▼
Docker Compose
        │
        ▼
Applications
```

## Responsibilities

### GitHub

Source of truth for infrastructure, documentation, automation, and application definitions.

### Ansible

Responsible for provisioning and configuring the operating system.

### Docker Engine

Provides the container runtime.

### Docker Compose

Defines and manages containerized workloads.

### Applications

Self-hosted services deployed on the platform.

## Guiding Principles

* Git is the single source of truth.
* Infrastructure is reproducible.
* Configuration is declarative.
* Manual changes should be avoided.
* Disaster recovery is considered a first-class requirement.
* The platform should scale to additional servers without redesigning the repository.
