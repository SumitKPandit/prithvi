# Hardware Inventory

## System

| Component        | Value                     |
| ---------------- | ------------------------- |
| Hostname         | prithvi                   |
| Vendor           | ASUSTeK COMPUTER INC.     |
| Model            | TUF GAMING FX504GD_FX80GD |
| Operating System | Ubuntu Server 26.04 LTS   |
| Kernel           | Linux 7.0.0-27-generic    |

## Firmware

| Component         | Value       |
| ----------------- | ----------- |
| BIOS Version      | FX504GD.322 |
| BIOS Release Date | 2021-08-23  |

## Processor

| Component | Value                  |
| --------- | ---------------------- |
| CPU       | Intel Core i5-8300H    |
| Cores     | 4 Physical / 8 Threads |

## Memory

| Component        | Value          |
| ---------------- | -------------- |
| Installed Memory | 8 GB DDR4-2667 |

## Storage

| Device            | Capacity | Purpose                                 |
| ----------------- | -------- | --------------------------------------- |
| Kingston NVMe SSD | 128 GB   | Operating system, Docker, configuration |
| Seagate HDD       | 1 TB     | Application data, media, downloads      |

Current filesystem layout:

| Mount     | Filesystem |
| --------- | ---------- |
| /         | NVMe       |
| /boot/efi | EFI        |
| /data     | HDD        |

## Networking

Current configuration:

* Wi-Fi interface (wlo1)
* Dynamic IPv4 address assigned by DHCP

Future target:

* Prefer Ethernet when practical
* DHCP reservation for a stable local IP
* Secure remote administration using Tailscale

## Notes

This document should be updated whenever hardware changes occur, including memory upgrades, storage replacements, or network topology changes.
