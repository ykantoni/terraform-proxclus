# Talos Kubernetes Cluster Module

Configures Talos Linux nodes and bootstraps Kubernetes.

## Responsibilities

This module manages:

- Talos machine secrets
- Talos client configuration
- control-plane configuration
- worker configuration
- static networking
- Talos configuration application
- cluster bootstrap
- kubeconfig generation
- a health check dependents can gate on

It does not create virtual machines, and it installs no CNI. With
`cni = "cilium"` it patches the control plane to deploy neither Flannel nor
kube-proxy, which leaves the cluster without pod networking until something
installs Cilium; see `modules/addons/cilium`.

## Addon prerequisites

Addons that need machine configuration reach it through `config_patches`,
`controlplane_config_patches` and `worker_config_patches`, so this module never
has to know which addons exist. Longhorn's kubelet mounts, for example, would
live in `modules/addons/longhorn/patches/` and be passed in by the root module.

Those patches must be static YAML — a literal or `file()`. A value derived from
the running cluster would make the cluster depend on its own addons, which are
in turn deployed onto it.

## Inputs

- `cluster_name`
- `talos_version`
- `talos_schematic_id`
- `gateway`
- `nameservers`
- `controlplane_vip`
- `cni`
- `kube_prism_port`
- `wait_for_health`
- `config_patches`, `controlplane_config_patches`, `worker_config_patches`
- `nodes`

## Outputs

- `controlplane_ips`
- `worker_ips`
- `talosconfig`
- `kubeconfig`