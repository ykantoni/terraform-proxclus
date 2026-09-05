---
name: talos-service-status
description: >
  Show the status of Talos-managed services on a node (talosctl service).
  Use to see which OS-level services are running, stopped, or
  crash-looping on a given Talos node.
agents: [talos]
target: local
safe: true
timeout: 20
command: ["talosctl", "-n", "{node}", "service", "{service}"]
params:
  node:
    type: string
    description: Node IP to query
    default: "${TALOS_VIP}"
  service:
    type: string
    description: Specific service name (e.g. kubelet, etcd), or empty for all services
    default: ""
---

`node` defaults to the control-plane VIP, which talosctl transparently
proxies to whichever control-plane node answers — good for a first look,
but pass a specific node IP (192.168.1.201-204) to check a worker or to
make sure you're looking at one node consistently across several calls.
