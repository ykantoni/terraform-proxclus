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
- Talos ISO attachment

It does not configure Talos Linux or Kubernetes.

## Inputs

- `proxmox_node`
- `datastore_id`
- `bridge`
- `talos_iso`
- `nodes`

## Outputs

- `nodes`
- `vm_ids`

## Networking

IP addresses are passed through as metadata for the Talos module.

This module does not use Proxmox cloud-init to configure Talos networking.