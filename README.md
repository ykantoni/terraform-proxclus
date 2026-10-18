# terraform-proxclus

Talos Linux Kubernetes cluster on Proxmox VE, split into three independently
applied Terraform stacks, each its own repo included here as a git submodule.

## Layout

- `terraform-proxclus-vm-infra/` — Proxmox VMs, VM templates, Talos image
  schematics, Proxmox host config
- `terraform-proxclus-k8s-infra/` — Talos bootstrap, Cilium, Longhorn,
  metrics-server, Prometheus, GPU Operator; reads vm-infra's outputs through
  `terraform_remote_state`
- `terraform-proxclus-k8s-apps/` — applications (ollama, postgres), each an
  independent Terraform root that only needs a kubeconfig
- `troubleshooting-agents/` — LangGraph troubleshooting agents (Talos,
  Ollama, NVIDIA GPU, Proxmox host) with a small React GUI, independent of
  Terraform entirely; see `troubleshooting-agents/README.md`

| Stack     | State file (`/home/yurick/terraform/state/`) |
| --------- | -------------------------------------------- |
| vm-infra  | `vm-infra.tfstate`                           |
| k8s-infra | `k8s-infra.tfstate`                          |
| k8s-apps  | `<app>.tfstate`, one per app                 |

## Usage

```bash
git clone --recurse-submodules git@github.com:ykantoni/terraform-proxclus.git
just t-create   # build Proxmox templates 9000/9001 (once)
just apply      # vm-infra, then k8s-infra
just generate   # writes ~/talosconfig and ~/.kube/config
```

`just destroy` runs in reverse: k8s-infra, then vm-infra. Apps are applied
separately from their own directories under `terraform-proxclus-k8s-apps/`;
see its README.
