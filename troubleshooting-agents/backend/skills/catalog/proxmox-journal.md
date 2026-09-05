---
name: proxmox-journal
description: >
  Tail the systemd journal for one unit on the Proxmox host (journalctl -u
  <unit>). Use once proxmox-systemd-failed (or a hunch) points at a
  specific service — pveproxy, pvedaemon, pvestatd, pve-cluster, and
  corosync are the usual suspects.
agents: [proxmox]
target: ssh
connection: proxmox
safe: true
timeout: 20
command: ["journalctl", "-u", "{unit}", "-n", "{lines}", "--no-pager"]
params:
  unit:
    type: string
    description: systemd unit name
  lines:
    type: integer
    description: Number of most recent lines to fetch
    default: 200
---

For cluster-quorum problems specifically, `corosync` and `pve-cluster`
together usually tell the whole story.
