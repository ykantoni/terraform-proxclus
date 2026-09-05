---
name: proxmox-disk-usage
description: >
  Show host filesystem usage (df -h). Use when VM starts, snapshots, or
  backups are failing — a full root or storage filesystem breaks all of
  them.
agents: [proxmox]
target: ssh
connection: proxmox
safe: true
timeout: 15
command: ["df", "-h"]
---

`/var/lib/vz` (or wherever local storage is mounted) filling up is the
most common cause of VM-start and backup failures on a single-node
Proxmox host.
