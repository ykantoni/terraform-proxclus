---
name: nvidia-dmesg
description: >
  Read the GPU node's kernel ring buffer (talosctl dmesg). Use to find
  NVIDIA driver load failures or Xid errors (lines containing "NVRM" or
  "Xid").
agents: [nvidia]
target: local
safe: true
timeout: 30
command: ["talosctl", "-n", "{node}", "dmesg"]
params:
  node:
    type: string
    description: GPU node's IP
    default: "${GPU_NODE}"
---

Search the (possibly truncated) output for "NVRM" or "Xid" specifically —
those lines are the actual evidence; the rest of the kernel log is noise
for this purpose.
