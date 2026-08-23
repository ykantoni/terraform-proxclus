# NVIDIA Device Plugin Addon Module

Installs the [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin)
so a node with a GPU mapped in advertises an `nvidia.com/gpu` resource that
pods can request, and gives GPU workloads a way to opt into the containerd
runtime the GPU actually needs.

## Responsibilities

This module manages:

- a `RuntimeClass` named `nvidia` (handler `nvidia`), matching the containerd
  runtime the `siderolabs/nvidia-container-toolkit-production` system
  extension registers on the host — GPU pods request it with
  `spec.runtimeClassName: nvidia`
- an `nvidia.com/gpu.present=true` label on each Kubernetes Node that
  corresponds to one of `var.gpu_node_ips`
- the `nvidia-device-plugin` Helm release, with `runtimeClassName: nvidia` and
  a `nodeSelector` on that same label, so its DaemonSet only ever schedules
  onto nodes that actually have a GPU

It expects a bootstrapped cluster and the `helm`/`kubernetes` providers to be
configured by the caller. It does not touch machine configuration — the
kernel-module patch and image schematic that give the node a GPU driver in
the first place live in `modules/talos-cluster` and `schematic.tf` and are
selected by the same `pcigpu` field this module reads.

## Why nodes are matched by IP, not name

The root module's `var.nodes` knows each GPU node's Proxmox VM name and
static IP, but nothing pins the *Kubernetes* Node name to either: Talos
derives it from the node's hostname, which this cluster never sets
explicitly. Rather than assume the two line up, this module reads
`data.kubernetes_nodes` and matches each `var.gpu_node_ips` entry against the
Node's own reported `InternalIP`.

## Why a nodeSelector instead of relying on the chart's defaults

The upstream chart has no built-in way to target only GPU nodes — that's
normally Node Feature Discovery's job. Without it, the DaemonSet's pods would
also land on GPU-less nodes, where there is no `nvidia` containerd runtime
and no driver, and just sit stuck. Labelling the nodes this module already
knows have a GPU (from `pcigpu`, via `gpu_node_ips`) and feeding that label
back in as the chart's `nodeSelector` gets the same result without pulling in
NFD.

## Inputs

- `gpu_node_ips`
- `nvidia_device_plugin_version`
- `namespace`
- `runtime_class_name`
- `gpu_node_label`
- `nvidia_device_plugin_extra_values`
- `helm_timeout`

## Outputs

- `runtime_class_name`
- `gpu_node_names`
- `namespace`

## Notes

Requesting the GPU from a workload takes two things on the pod spec, not
just the `nvidia.com/gpu` resource request:

```yaml
spec:
  runtimeClassName: nvidia
  containers:
    - name: cuda-workload
      resources:
        limits:
          nvidia.com/gpu: 1
```

Skipping `runtimeClassName` schedules the pod through the plain `runc`
runtime, which never sees the GPU even though the device plugin advertised
one.
