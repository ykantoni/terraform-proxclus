---
name: nvidia-device-plugin-logs
description: >
  Tail the NVIDIA device plugin DaemonSet's own logs (kube-system
  namespace). Use when nvidia.com/gpu isn't showing up as an allocatable
  resource, or a GPU pod won't schedule.
agents: [nvidia]
target: kubectl
safe: true
timeout: 20
mode: logs
namespace: kube-system
selector: "app.kubernetes.io/instance=nvidia-device-plugin"
tail: 200
---

A crash-looping or repeatedly-restarting plugin pod usually means the
NVIDIA kernel driver isn't loaded yet on that node — check `nvidia-dmesg`
and `nvidia-pci-devices` next. If the selector here doesn't match anything,
list pods in `kube-system` with `k8s-get-pods` to find the plugin's actual
pod name/labels for this chart version.
