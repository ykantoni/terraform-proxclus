---
name: talos-health
description: >
  Run the aggregate Talos cluster health check (talosctl health) across
  all nodes. Use as the first check in any cluster-wide investigation.
agents: [talos]
target: local
safe: true
timeout: 60
command: ["talosctl", "-n", "{node}", "health", "--server=false"]
params:
  node:
    type: string
    description: Node IP to run the check against/through
    default: "${TALOS_VIP}"
---

`--server=false` runs the checks from this CLI process instead of expecting
a talosctl server on the other end — matches how this backend's host is
already set up to reach the cluster (same assumption `terraform apply`
makes; see the repo's top-level README "Ordering" section).

Known false positive: nodes without a GPU can report stage `booting`
forever because of `ext-nvidia-persistenced` waiting on a PCI device that
will never appear (see the repo README's "Known issue" section) — that's
expected, not a new problem, if it's the only failing check.
