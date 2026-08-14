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

It does not create virtual machines.

## Inputs

- `cluster_name`
- `talos_version`
- `gateway`
- `nameservers`
- `nodes`

## Outputs

- `controlplane_ips`
- `worker_ips`
- `talosconfig`
- `kubeconfig`