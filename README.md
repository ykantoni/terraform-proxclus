# terraform-proxclus

Talos Linux Kubernetes cluster on Proxmox VE, split into three independently
applied Terraform stacks, each its own repo included here as a git submodule.

## Layout

- `terraform-proxclus-vm-infra/` — Proxmox VMs, VM templates, Talos image
  schematics, Proxmox host config
- `terraform-proxclus-k8s-infra/` — Talos bootstrap, Cilium, Longhorn,
  metrics-server, Prometheus, GPU Operator; reads vm-infra's outputs through
  `terraform_remote_state`
- `terraform-proxclus-k8s-apps/` — applications (ollama, open-webui,
  postgres), as ArgoCD `Application`s; k8s-infra's ArgoCD syncs them from
  GitHub, no Terraform involved
- `troubleshooting-agents/` — LangGraph troubleshooting agents (Talos,
  Ollama, NVIDIA GPU, Proxmox host) with a small React GUI, independent of
  Terraform entirely; see `troubleshooting-agents/README.md`

| Stack     | State file (`/home/yurick/terraform/state/`) |
| --------- | -------------------------------------------- |
| vm-infra  | `vm-infra.tfstate`                           |
| k8s-infra | `k8s-infra.tfstate`                          |
| k8s-apps  | none; ArgoCD reconciles from Git             |

## Usage

```bash
git clone --recurse-submodules git@github.com:ykantoni/terraform-proxclus.git
just t-create   # build Proxmox templates 9000/9001 (once)
just apply      # vm-infra, then k8s-infra
just generate   # writes ~/talosconfig and ~/.kube/config
```

`just destroy` runs in reverse: k8s-infra, then vm-infra. Apps deploy
themselves: k8s-infra's ArgoCD watches `terraform-proxclus-k8s-apps` on
GitHub, so push to its `main` to change them; see its README.
