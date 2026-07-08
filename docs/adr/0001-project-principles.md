# Architecture Decision Log

This document records significant architectural decisions made during the development of the platform.

---

## ADR-001

### Decision

Use Ubuntu Server 26.04 LTS as the operating system.

### Rationale

Ubuntu LTS provides long-term support, a mature ecosystem, and excellent compatibility with Docker and Ansible.

---

## ADR-002

### Decision

Manage the operating system using Ansible.

### Rationale

Ansible provides idempotent configuration management and supports reproducible infrastructure without requiring additional agents on managed hosts.

---

## ADR-003

### Decision

Use Docker Compose for application deployment.

### Rationale

Docker Compose provides a simple, declarative way to manage a single-host platform while remaining portable and widely supported.

---

## ADR-004

### Decision

Separate infrastructure provisioning from application deployment.

### Rationale

The operating system and the applications have different responsibilities and lifecycle requirements.

Ansible provisions the host.

Docker Compose manages applications.

---

## ADR-005

### Decision

Store runtime data outside the Git repository.

### Rationale

Git should contain only source code, documentation, and configuration.

Application data, media libraries, downloads, and backups remain on dedicated storage outside the repository.
