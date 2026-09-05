---
name: proxmox-systemd-failed
description: >
  List any failed systemd units on the Proxmox host (systemctl --failed).
  Use as a fast first check for host-level service trouble.
agents: [proxmox]
target: ssh
connection: proxmox
safe: true
timeout: 15
command: ["systemctl", "--failed", "--no-pager"]
---

An empty list is a genuinely useful negative result — say so plainly
rather than treating "nothing failed" as an unfinished investigation.
