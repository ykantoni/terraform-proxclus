---
name: proxmox-dmesg
description: >
  Read the Proxmox host's kernel ring buffer (dmesg --ctime). Use for
  host-level hardware/storage errors, OOM kills, or IOMMU/VFIO messages
  relevant to GPU passthrough.
agents: [proxmox]
target: ssh
connection: proxmox
safe: true
timeout: 20
command: ["dmesg", "--ctime"]
---

For GPU passthrough problems specifically, search for "vfio" or "iommu" —
a passthrough failure at this level means the guest VM never sees the
card at all, before Talos or the driver ever get a chance to.
