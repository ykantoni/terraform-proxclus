# RKE2 Cluster Module

Waits for the cluster to come up and fetches its kubeconfig. Replaces the
readiness/bootstrap half of `modules/talos-cluster`
(`talos_machine_bootstrap`, `terraform_data.wait_for_api`,
`talos_cluster_kubeconfig`), reworked for SSH instead of the `talos`
provider's API.

## Responsibilities

This module manages:

- an SSH keypair file on disk (`local_sensitive_file.ssh_key`, from
  `module.rke2_config`'s Terraform-managed key) for its own `local-exec`
  steps to use
- `terraform_data.wait_for_rke2_server` — polls the bootstrap node over SSH
  until `rke2-server` is active. This is the direct analog of
  `terraform_data.wait_for_api` in `modules/talos-cluster`, just checking a
  systemd unit instead of curling the API directly, since cloud-init +
  RKE2's own startup is asynchronous after the VM boots (unlike Talos's
  synchronous `talos_machine_bootstrap` API call)
- `terraform_data.fetch_kubeconfig` — SSHes in, reads
  `/etc/rancher/rke2/rke2.yaml`, and rewrites its embedded
  `https://127.0.0.1:6443` to `https://<controlplane_vip>:6443`, so the
  kubeconfig this module hands back is usable by clients outside the
  bootstrap node itself
- `data.local_file.kubeconfig` — reads that rewritten file back into an
  output

It does not create VMs (`modules/proxmox-vm`) and does not render or upload
any cloud-init content (`modules/rke2-config`) — see the root README's
"Layout" section for why provisioning is three modules here instead of
Talos's two.

## Why `var.nodes` here is `module.proxmox_vm.nodes`, not the raw `var.nodes`

This module's whole job only makes sense once VMs exist and have booted.
Taking `module.proxmox_vm.nodes` (rather than the same static `var.nodes`
`modules/rke2-config` reads) is what gives Terraform that dependency —
without it, nothing would stop these `local-exec` steps from racing the VM
creation itself.

## Why there's no Kubernetes-level health check like `data.talos_cluster_health`

Talos's health data source can (and does) skip its node-readiness/coredns
checks once machine config says `cni: none`, because Talos itself knows
that state. There's no equivalent RKE2 Terraform data source to do the same
skip, so this module doesn't attempt a "wait for all nodes Ready" gate at
all — `wait_for_rke2_server`/`fetch_kubeconfig` only prove the API server
exists, exactly as much as `terraform_data.wait_for_api` proves today.
Addons that need real pod networking still get it the same way they already
do: by depending on `module.cilium`'s `helm_release` directly in root
`addons.tf`, not on this module's readiness check.

## Inputs

- `controlplane_vip`
- `bootstrap_ip`
- `ssh_admin_user`
- `ssh_private_key_pem`
- `wait_for_api`
- `api_wait_timeout`
- `api_wait_interval`
- `nodes`

## Outputs

- `controlplane_ips`
- `worker_ips`
- `kubeconfig`
