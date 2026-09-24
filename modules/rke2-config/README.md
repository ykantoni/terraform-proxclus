# RKE2 Config Module

Renders and uploads each node's cloud-init user-data as a Proxmox snippet.
Replaces the machine-config-generation half of `modules/talos-cluster`
(`data.talos_machine_configuration`), reworked for cloud-init instead of the
`talos` provider's API-driven config apply.

## Responsibilities

This module manages:

- `random_password.rke2_token` — the shared RKE2 cluster join token, generated
  once so every node's cloud-init can reference it with no bootstrap-order
  dependency (unlike RKE2's own auto-generated token, which only exists on
  the server after it's already up)
- `tls_private_key.ssh` — the keypair Terraform itself uses to reach nodes
  after boot (see `modules/rke2-cluster`); only the public half is ever sent
  to a node
- one `proxmox_virtual_environment_file` (content type `snippets`) per node,
  rendered from `templates/user-data.yaml.tftpl`: hostname, an admin user
  with the Terraform SSH key, RKE2's `/etc/rancher/rke2/config.yaml`
  (role-conditional: server vs agent, token, `cni: none`,
  `disable-kube-proxy: true`, the RKE2-bundled components this repo's own
  addons replace, `profile: cis`), and — control-plane only — the kube-vip
  static-manifest that replaces Talos's `Layer2VIPConfig` patch

It does not create VMs (`modules/proxmox-vm`) and does not wait for the
cluster to come up or fetch a kubeconfig (`modules/rke2-cluster`) — see the
root README's "Layout" section for why provisioning is three modules here
instead of Talos's two.

## Why the join token and SSH key are generated here, not in modules/rke2-cluster

Both are needed by cloud-init content that must exist *before* a VM is
created, so they have to live in the module that has no dependency on VMs
existing. `modules/rke2-cluster` only borrows the SSH private key (as an
output) to SSH into nodes after they've booted.

## Prerequisite: the snippets content type

`var.snippet_datastore_id` must point at a Proxmox datastore with the
`snippets` content type enabled (Datacenter > Storage > *datastore* >
Content, in the Proxmox UI) — Terraform can't turn this on itself. Same kind
of one-time, host-side prerequisite as the PCI resource mapping GPU nodes
reference (see `modules/proxmox-vm`).

## Inputs

- `proxmox_node`
- `snippet_datastore_id`
- `controlplane_vip`
- `external_ip`
- `ssh_admin_user`
- `nodes`

## Outputs

- `cloudinit_file_ids`
- `ssh_admin_user`
- `ssh_private_key_pem` (sensitive)
- `bootstrap_ip`
