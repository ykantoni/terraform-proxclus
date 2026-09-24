# Proxmox VM Module

Creates Proxmox VE virtual machines intended to run Ubuntu + RKE2. Replaces
`modules/proxmox-talos-vm`.

## Responsibilities

This module manages:

- Proxmox VM creation
- CPU and memory
- VM disks
- virtual network interfaces
- fixed MAC addresses
- static IP/gateway/DNS via Proxmox's native cloud-init integration
  (`initialization.ip_config`/`dns`)
- attaching each node's rendered cloud-init user-data (hostname, RKE2
  config, kube-vip manifest, SSH key — from `module.rke2_config`) by
  snippet file ID

Each VM is a full clone of an existing Proxmox template (`template_vm_id_common`
or `template_vm_id_gpu`), built ahead of time by `packer/` and the `just
t-create`/`just t-destroy` recipes — this module does not install Ubuntu
from an ISO itself, and does not configure RKE2 or Kubernetes.

## Why cloud-init lives partly here and partly in `modules/rke2-config`

Static IP/gateway/DNS are intrinsically Proxmox VM settings (the
`initialization` block on the VM resource itself), so they're set here,
directly from `var.nodes`. The actual user-data *content* — RKE2's
`config.yaml`, the kube-vip manifest, the admin SSH key — has nothing to do
with Proxmox and everything to do with how the cluster bootstraps, so it's
rendered and uploaded as a snippet by `modules/rke2-config`, and this module
only wires in the resulting file ID via `var.cloudinit_file_ids`.

This split also breaks what would otherwise be a dependency cycle: cloud-init
content must exist *before* a VM can reference it at creation time, while
cluster-readiness checks (in `modules/rke2-cluster`) can only run *after* the
VM exists and has booted. One module can't be on both sides of that
dependency, so provisioning splits into three modules instead of Talos's two
— see the root README's "Layout" section.

## Inputs

- `proxmox_node`
- `datastore_id`
- `bridge`
- `gateway`
- `nameservers`
- `template_vm_id_common`
- `template_vm_id_gpu`
- `cloudinit_file_ids`
- `nodes`

## Outputs

- `nodes`
- `vm_ids`
