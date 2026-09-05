---
name: nvidia-pci-devices
description: >
  List PCI devices Talos sees on a node (talosctl get pciDevices). Use to
  confirm the GPU actually enumerates on the bus before assuming a driver
  or Kubernetes-level problem.
agents: [nvidia]
target: local
safe: true
timeout: 20
command: ["talosctl", "-n", "{node}", "get", "pciDevices"]
params:
  node:
    type: string
    description: GPU node's IP
    default: "${GPU_NODE}"
---

If the GPU is missing entirely from this list, the problem is at the
Proxmox/VFIO passthrough level, not the guest OS or Kubernetes — hand off
to the `proxmox` agent (check its dmesg for IOMMU/VFIO errors) rather than
continuing to chase it here.
