---
name: proxmox-vm-list
description: >
  List VMs and their running/stopped state as Proxmox sees them (qm list).
  Use to confirm a Talos node's VM is actually up before looking any
  deeper (Talos/Kubernetes level questions belong to the talos agent).
agents: [proxmox]
target: ssh
connection: proxmox
safe: true
timeout: 15
command: ["qm", "list"]
---

This is Proxmox's view only — "running" here says nothing about whether
the guest OS booted cleanly or Kubernetes is healthy inside it.
