---
name: proxmox-node-status
description: >
  Show host-level status: load average, memory, uptime, CPU (pvesh get
  /nodes/<node>/status). Use to check whether the hypervisor itself is
  under resource pressure.
agents: [proxmox]
target: ssh
connection: proxmox
safe: true
timeout: 15
command: ["pvesh", "get", "/nodes/{node}/status", "--output-format", "json-pretty"]
params:
  node:
    type: string
    description: Proxmox node name (as PVE names it, e.g. "pve")
    default: "pve"
---

`node` is the Proxmox node *name*, not an IP — check with the Proxmox web
UI or `pvesh get /nodes` if the default doesn't match this host.
