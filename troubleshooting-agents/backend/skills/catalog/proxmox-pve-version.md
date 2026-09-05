---
name: proxmox-pve-version
description: >
  Show installed Proxmox VE package versions (pveversion -v). Use first,
  to confirm which PVE build you're troubleshooting.
agents: [proxmox]
target: ssh
connection: proxmox
safe: true
timeout: 15
command: ["pveversion", "-v"]
---

Useful to have on hand before searching for a known-issue match against
release notes or bug trackers.
