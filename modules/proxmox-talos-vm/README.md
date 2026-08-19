# Proxmox Talos VM Module

Creates Proxmox VE virtual machines intended to run Talos Linux.

## Responsibilities

This module manages:

- Proxmox VM creation
- CPU and memory
- VM disks
- EFI configuration
- virtual network interfaces
- fixed MAC addresses

Each VM is a full clone of an existing Proxmox template (`vm_id = 9000`),
built ahead of time by `vm-templates/` and the `just t-create`/`just
t-destroy` recipes — this module does not install Talos from an ISO itself.

It does not configure Talos Linux or Kubernetes.

## Inputs

- `proxmox_node`
- `datastore_id`
- `bridge`
- `nodes`

## Outputs

- `nodes`
- `vm_ids`

## Networking

IP addresses are passed through as metadata for the Talos module.

This module does not use Proxmox cloud-init to configure Talos networking.
