# Orchestrates the three stacks (git submodules). Run `just --list` to see all
# recipes; each submodule's own Justfile has the per-stack ones.

vm := "terraform-proxclus-vm-infra"
k8s := "terraform-proxclus-k8s-infra"

# VMs first, then the cluster that runs on them.
apply:
    just -f {{vm}}/Justfile apply
    just -f {{k8s}}/Justfile apply

# Reverse order: the cluster, then the VMs under it.
destroy:
    just -f {{k8s}}/Justfile destroy
    just -f {{vm}}/Justfile destroy

plan:
    just -f {{vm}}/Justfile plan
    just -f {{k8s}}/Justfile plan

fmt:
    just -f {{vm}}/Justfile fmt
    just -f {{k8s}}/Justfile fmt

t-create:
    just -f {{vm}}/Justfile t-create

t-destroy:
    just -f {{vm}}/Justfile t-destroy

generate:
    just -f {{k8s}}/Justfile generate

endpoints:
    just -f {{k8s}}/Justfile endpoints
