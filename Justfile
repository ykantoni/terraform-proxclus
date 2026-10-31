# Orchestrates the three stacks (git submodules). Run `just --list` to see all
# recipes; each submodule's own Justfile has the per-stack ones.

vm := "terraform-proxclus-vm-infra"
k8s := "terraform-proxclus-k8s-infra"

# OpenTofu by default. For Terraform: `TF=terraform just <recipe>` or
# `just tf=terraform <recipe>`. After changing tools, run `just switch` once.
tf := env("TF", "tofu")

# VMs first, then the cluster that runs on them.
apply:
    just -f {{vm}}/Justfile tf={{tf}} apply
    just -f {{k8s}}/Justfile tf={{tf}} apply

# Reverse order: the cluster, then the VMs under it.
destroy:
    just -f {{k8s}}/Justfile tf={{tf}} destroy
    just -f {{vm}}/Justfile tf={{tf}} destroy

# Install providers for the selected tool, in both stacks.
init:
    just -f {{vm}}/Justfile tf={{tf}} init
    just -f {{k8s}}/Justfile tf={{tf}} init

# Run once after changing tools, in both stacks.
switch:
    just -f {{vm}}/Justfile tf={{tf}} switch
    just -f {{k8s}}/Justfile tf={{tf}} switch

plan:
    just -f {{vm}}/Justfile tf={{tf}} plan
    just -f {{k8s}}/Justfile tf={{tf}} plan

fmt:
    just -f {{vm}}/Justfile tf={{tf}} fmt
    just -f {{k8s}}/Justfile tf={{tf}} fmt

t-create:
    just -f {{vm}}/Justfile tf={{tf}} t-create

t-destroy:
    just -f {{vm}}/Justfile tf={{tf}} t-destroy

generate:
    just -f {{k8s}}/Justfile tf={{tf}} generate

endpoints:
    just -f {{k8s}}/Justfile tf={{tf}} endpoints
