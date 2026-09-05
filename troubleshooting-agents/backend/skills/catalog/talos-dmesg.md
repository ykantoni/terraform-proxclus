---
name: talos-dmesg
description: >
  Read the kernel ring buffer of a Talos node (talosctl dmesg). Use to
  find OOM kills, driver load failures, hardware errors, or other
  kernel-level evidence a specific node is unhealthy.
agents: [talos]
target: local
safe: true
timeout: 30
command: ["talosctl", "-n", "{node}", "dmesg"]
params:
  node:
    type: string
    description: Node IP to read
    default: "${TALOS_VIP}"
---

Output can be long; the tool truncates it, so if you're hunting for
something specific (a driver name, "Out of memory", "Xid") search the
returned text rather than assuming the whole buffer is present.
